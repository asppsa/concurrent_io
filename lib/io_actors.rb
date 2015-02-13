require "io_actors/version"

require 'concurrent'

module IOActors
  SelectMessage = Struct.new(:actor)
  RegisterMessage = Struct.new(:io, :actor)
  DeregisterMessage = Struct.new(:io)
  InputMessage = Struct.new(:bytes)
  OutputMessage = Struct.new(:bytes)
  InformMessage = Struct.new(:actor)

  @selector = Concurrent::Delay.new{ SelectActor.spawn 'io_actors_selector' }
  
  class << self
    def selector
      @selector.value
    end
  end
end

require "io_actors/controller_actor"
require "io_actors/reader_actor"
require "io_actors/select_actor"
require "io_actors/writer_actor"
