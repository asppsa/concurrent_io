# io_actors

**This is a work in progress -- do not use!**

This gem provides an actor-based framework for working with IO objects
such as files and sockets.  It is based on the Actors implementation
in [concurrent-ruby][cr].  It includes actors for reading, writing and
selecting/reacting.  The last of these uses [nio4r][nio] for its
`select` implementation.

This gem is intended for use with a Ruby implementation that does not
have a GIL, such as [Rubinius][rbx] or [JRuby][jruby].

[cr]: http://concurrent-ruby.com/
[nio]: https://github.com/celluloid/nio4r
[rbx]: http://rubini.us/
[jruby]: http://jruby.org/


## Usage

Sorry, there's no good API documentation yet.  In short, the main use
case for this gem goes like this:

~~~ ruby
# Given some IO object, create a controller
controller = IOActors::ControllerActor.spawn('my_controller', my_io)

# Tell the controller about your "listener" actor (or any other object
# that responds to :<<).  This object will receive incoming packets.
# If you spawn the controller inside of another actor then that actor
# will receive these notifications by default.
controller << IOActors::InformMessage.new(my_listener)

# Tell the controller to register itself with the global selector so
# that it can react whenever input comes in.
controller << IOActors::SelectMessage.new(IOActors.selector)

# Whenever you want to write something, do like so:
controller << IOActors::OutputMessage.new("My text I want to write")

# Or, equivalently
controller << "My text I want to write"

# When you are done, tell the actor to clean up.
controller << :close
~~~

A `:closed` message will also be sent to your listener, if you have
provided one, once the IO object is closed (either by you or by
someone else).

You can use the `ReaderActor` and `WriterActor` individually if you
want.  Below is an example of using a reader

~~~ ruby
# Create the reader
reader = IOActors::ReaderActor.spawn('my_actor', some_socket)

# Tell the reader to post notifications to some other actor
reader << IOActors::InformMessage.new(my_listener)

# Tell the reader to do a read.  It will post IOActors::InputMessage
# objects to my_listener until it exhausts itself.
reader << :read

# Close the IO object and kill the actor
reader << :close
~~~

Here is an example using a writer.

~~~ ruby
# Create it
writer = IOActors::WriterActor.spawn('my_writer', some_io)

# Tell the writer to write some string.
writer << IOActors::OutputMessage.new("my message")

# Close the IO object and kill the actor
writer << :close
~~~

You can extract the reader and writer objects from the controller too:

~~~ ruby
# Create it
controller = IOActors::Controller.spawn('my_controller', some_io)

# Get the reader and writer
reader = controller.ask!(:reader)
writer = controller.ask!(:writer)
~~~

## Ping pong example

In the `examples` folder there is an executable that will send "ping"
and "pong" messages between actors over a UNIX socket.  You can run it
as follows:

~~~ bash
$ bundle exec examples/ping_pong.rb
~~~

The actor code for this example is in `examples/ping_pong_actor.rb`.

While runnning, it will print out details about the number of actors
currently alive in `ObjectSpace`, like so:

~~~
TOTAL: 1374
TERMINATED: 1102
ALIVE: 272
~~~

The above example text shows a very large number of terminated actors
still in memory.  This is an unresolved problem at the moment, and the
main reason that this gem should not be used at present.

You can also view the actual pings and pongs using the
`IOACTORS_DEBUG` environment variable:

~~~ bash
$  IOACTORS_DEBUG=1 bundle exec examples/ping_pong.rb
~~~

You should see output like the following:

~~~
I, [2015-02-17T11:43:06.494979 #16596]  INFO -- ping: /ponger_8
I, [2015-02-17T11:43:06.494949 #16596]  INFO -- ping: /ponger_9
I, [2015-02-17T11:43:06.499075 #16596]  INFO -- ping: /ponger_7
I, [2015-02-17T11:43:06.500541 #16596]  INFO -- got PING: /ponger_8
I, [2015-02-17T11:43:06.499241 #16596]  INFO -- ping: /ponger_6
I, [2015-02-17T11:43:06.501079 #16596]  INFO -- got PING: /ponger_7
I, [2015-02-17T11:43:06.501524 #16596]  INFO -- got PING: /ponger_6
I, [2015-02-17T11:43:06.501992 #16596]  INFO -- got PING: /ponger_9
I, [2015-02-17T11:43:06.503248 #16596]  INFO -- ping: /ponger_4
I, [2015-02-17T11:43:06.503457 #16596]  INFO -- ping: /ponger_1
I, [2015-02-17T11:43:06.503743 #16596]  INFO -- got PING: /ponger_4
I, [2015-02-17T11:43:06.504315 #16596]  INFO -- got PING: /ponger_1
I, [2015-02-17T11:43:06.504584 #16596]  INFO -- ping: /ponger_5
I, [2015-02-17T11:43:06.505156 #16596]  INFO -- got PING: /ponger_5
I, [2015-02-17T11:43:06.505748 #16596]  INFO -- ping: /ponger_3
I, [2015-02-17T11:43:06.508852 #16596]  INFO -- got PING: /ponger_3
I, [2015-02-17T11:43:06.509022 #16596]  INFO -- ping: /ponger_0
I, [2015-02-17T11:43:06.509778 #16596]  INFO -- got PING: /ponger_0
I, [2015-02-17T11:43:06.510781 #16596]  INFO -- ping: /ponger_2
I, [2015-02-17T11:43:06.511515 #16596]  INFO -- got PING: /ponger_2
I, [2015-02-17T11:43:06.523050 #16596]  INFO -- pong: /pinger_6
I, [2015-02-17T11:43:06.523179 #16596]  INFO -- pong: /pinger_3
I, [2015-02-17T11:43:06.523568 #16596]  INFO -- got PONG: /pinger_6
I, [2015-02-17T11:43:06.523740 #16596]  INFO -- pong: /pinger_2
I, [2015-02-17T11:43:06.524349 #16596]  INFO -- pong: /pinger_4
I, [2015-02-17T11:43:06.524484 #16596]  INFO -- pong: /pinger_9
I, [2015-02-17T11:43:06.524688 #16596]  INFO -- pong: /pinger_0
I, [2015-02-17T11:43:06.524483 #16596]  INFO -- got PONG: /pinger_3
I, [2015-02-17T11:43:06.525364 #16596]  INFO -- pong: /pinger_1
~~~


## License

io_actors is copyright (C) 2015 Alastair Pharo.  Distributed under
[the Apache License, Version 2.0][license].

[license]: http://www.apache.org/licenses/LICENSE-2.0
