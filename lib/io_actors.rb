require "io_actors/version"

require 'concurrent/actor'

module IOActors
  SelectMessage = Struct.new(:actor)
  RegisterMessage = Struct.new(:io, :actor, :direction)
  DeregisterMessage = Struct.new(:io, :direction)
  InputMessage = Struct.new(:bytes)
  OutputMessage = Struct.new(:bytes)
  InformMessage = Struct.new(:actor)

  @selector = Concurrent::Delay.new{ SelectActor.spawn 'io_actors_selector' }

  class << self
    def selector
      @selector.value
    end

    def selector= selector
      @selector.value = selector
    end
  end
end

require "io_actors/controller_actor"
require "io_actors/reader_actor"
require "io_actors/select_actor"
require "io_actors/writer_actor"

if ENV['IOACTORS_DEBUG']
  Concurrent.configure do |c|
    l = Logger.new(STDOUT)
    limit = eval("Logger::#{ENV['IOACTORS_DEBUG']}")
    c.logger = lambda do |level, *params|
      return unless level >= limit
      l.add level, *params
    end
  end
end
