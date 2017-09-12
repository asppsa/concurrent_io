# concurrent_io

This gem provides a concurrency-friendly for working with large
numbers of IO objects such as files and sockets without needing to
spawn a thread per handle.  In theory this gem should make it possible
to scalably deal with lots of open files at once, without having to
convert everything in one's app to async IO, as is the case with a
plain [EventMachine][em] setup, etc.  It should be noted that this
theory is not well-tested (not by me at least).

concurrent_io is based on [concurrent-ruby][cr], and includes a means
for working with concurrent-ruby's Actor implementation.

This gem is in use in some small-scale production environments, but
it's still pretty green, so your mileage may vary.  In particular,
although the intention is to support IO in general, so far TCP sockets are
the only thing that has really been tested.  It's also probably best suited for
use with a Ruby implementation that does not have a GIL, such as
[Rubinius][rbx] or [JRuby][jruby].


## Select Loop Implementations

The basic mechanism by which `concurrent_io` works is that somewhere in
a lone thread, a select-loop is running, monitoring IO objects for
readiness to read or write.  When an IO becomes read-ready, the loop
reads as many bytes as it can and dispatches them to some listener;
similarly when an IO becomes write-ready, the loop writes as many
pending bytes as it can and notifies the listener.  Some concurrency
synchronisation is then used to add or remove IO objects, and to
sequence reads and writes.

`concurrent_io` implements a basic reactor pattern select-loop using
Ruby's built-in `IO::select`.  As many will know though, `IO::select`
has a reputation for being slow.  Furthermore, this implementation
does all its looping, reading and writing in Ruby, which it turns out
isn't very fast either.  For improved performance (hopefully),
`concurrent_io` can optionally make use of a number of other
 libraries.  At the moment these are:

* [EventMachine][em], the well-known Ruby reactor; and
* [NIO4R][nio], created by the [Celluloid][celluloid] people.

There's also a broken libevent wrapper using my unfinished
[FFI-Libevent][ffi-libevent] gem.  Don't use this one!

In my experience, EventMachine is the most stable alternative backend
at the moment.


## Usage

Sorry, there's no good API documentation yet.  The following is a very
brief example of low-level usage.

~~~ ruby
require 'concurrent_io'

# Optionally, tell concurrent_io which implementation to use.  This is
# a good idea
ConcurrentIO.use_select!
#ConcurrentIO.use_nio4r!
#ConcurrentIO.use_eventmachine!

# Get a select-loop object
selector = ConcurrentIO.default_selector

# Let's make some sockets
require 'socket'
s1, s2 = UNIXSocket.pair

# We need to supply objects for getting notifications about the
# sockets.  It needs to implement three methods: trigger_read,
# trigger_write and trigger_error
class MyReactor
  def initialize selector, socket
    @selector = selector
    @socket = socket

    # Tell the selector to monitor the socket and notify us
    @selector.add @socket, self
  end

  # Note these methods will be called from within the select-loop
  # thread, so you should hand the bytes to another thread before
  # doing blocking IO, etc.
  def trigger_read bytes
    Concurrent::Future.execute do
      puts "GOT: #{bytes}"
    end
  end

  def trigger_write count
    Concurrent::Future.execute do
      puts "WROTE #{count} bytes"
    end
  end

  def trigger_error e
    Concurrent::Future.execute do
      puts "ERROR: #{e}"
    end
  end

  def write bytes
    @selector.write @socket, bytes
  end

  def close
    @selector.remove [@socket]
  end
end

# Create reactors
reactor1 = MyReactor.new(selector, s1)
reactor2 = MyReactor.new(selector, s2)

# Tell 1 to write to 2
reactor1.write "Hi from reactor1"

# Wait for things to happen on other threads
sleep 1

# Close the IO objects, stop listening for events
[reactor1, reactor2].each(&:close)
~~~

As stated in the example, the `trigger_*` methods get called within
the select-loop's thread, so at this basic level, it's the
implmenter's responsibility to dispatch these to some other thread in
the right order.  If you want to use [concurrent-ruby actors][actors],
concurrent_io has an actors implmentation that does this for you, as
the following example shows.

~~~ ruby
require 'concurrent_io'

# This is the actor
require 'concurrent_io/controller'

# Here's a simple actor that stores some app state
class MyState < Concurrent::Actor::Context
  def initialize socket
    # This makes a child actor which will control the IO object for us,
    # and pass messages to us
    @controller = ConcurrentIO::Controller.spawn('my_controller', socket)
    @bytes_read = ''
    @count_written = 0
  end

  def on_message message
    case message
    when ConcurrentIO::ReadMessage
      @bytes_read << message.bytes
      log(Logger::INFO, "READ: #{@bytes_read}")
    when ConcurrentIO::WriteMessage
      @count_written += message.count
      log(Logger::INFO, "WRITTEN: #{@count_written}")
    when :closed
      log(Logger::INFO, "The socket has been closed")
      terminate!
    else
      redirect @controller
    end
  end
end

# Make two sockets
require 'socket'
s1, s2 = UNIXSocket.pair

# Make two actors
a1 = MyState.spawn('actor1', s1)
a2 = MyState.spawn('actor2', s2)

# Tell actor1 to send some text to actor2
a1 << "Line 1\n"
a1 << "Line 2\n"
a1 << "Line 3\n"

# Kill the actors.  The supervision tree will ensure that the IO
# objects are closed.
a1 << :terminate!
a2 << :terminate!
~~~

Similar setups are possible using [Async objects][async],
[Agents][agents], queues, etc.


## Ping pong example

In the `examples` folder there is an executable that will send "ping"
and "pong" messages between actors over a TCP socket.  It also kills
all the sockets intermittently and creates a bunch of new ones, in
order to simulate a network environment with lots of connections and
disconnections.  State is managed using agents.  You can run it as
follows:

~~~ bash
$ bundle exec examples/ping_pong.rb [implementation]
~~~

Where `[implementation]` is one of the following strings:

* `select`
* `eventmachine`
* `nio4r`

The agent code for this example is in `examples/ping_ponger.rb`.

While runnning, it will print out details about the numbers of pings
and pongs that have been received, and the number of IO objects that
are presnet in the object space.  Hopefully you can satisfy yourself
that things are being garbage-collected at an acceptable rate!


## Alternatives

Firstly, it's only really worth your while to use this library if you
are dealing with lots of IO objects at once, i.e. where having a thread
per object won't work.  Otherwise, you can probably just launch a some
threads (or futures, or some such thing in concurrent-ruby) do your
blocking reads/writes there, and pass the info on to your actor or
whatever.

[Celluloid::IO][celluloid-io] gives you this library's functionality
and much more on top of Celluloid.

You could also investigate using [EventMachine][em] by itself.


## History

Initially, actors were used for everything in this library, and so the
gem was called [io_actors][io_actors].  A new name because necessary
once actors stopped being the basic building block.


## License

concurrent_io is copyright (C) 2017 Alastair Pharo.  Distributed under
[the Apache License, Version 2.0][license].

[cr]: http://concurrent-ruby.com/
[rbx]: http://rubini.us/
[jruby]: http://jruby.org/
[nio]: https://github.com/celluloid/nio4r
[em]: http://rubyeventmachine.com/
[ffi-libevent]: https://github.com/asppsa/ffi-libevent
[celluloid]: https://celluloid.io/
[celluloid-io]: https://github.com/celluloid/celluloid-io
[le]: http://libevent.org/
[actors]: http://ruby-concurrency.github.io/concurrent-ruby/Concurrent/Actor.html
[async]: http://ruby-concurrency.github.io/concurrent-ruby/Concurrent/Async.html
[agents]: http://ruby-concurrency.github.io/concurrent-ruby/Concurrent/Agent.html
[license]: http://www.apache.org/licenses/LICENSE-2.0
