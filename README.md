# io_actors

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


## License

io_actors is copyright (C) 2015 Alastair Pharo.  Distributed under
[the Apache License, Version 2.0][license].

[license]: http://www.apache.org/licenses/LICENSE-2.0
