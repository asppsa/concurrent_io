require 'eventmachine'

class IOActors::EventMachineSelector
  include Concurrent::Concern::Logging
  include IOActors::BasicSelector

  def initialize timeout=nil
    @handlers = Concurrent::Agent.new({}, error_handler: proc{ |e| log(Logger::ERROR, self.to_s, e.to_s) })

    @ivar = Concurrent::IVar.new
    run!

    # Force us to wait until EM is running
    @ivar.value
  end

  def run_loop
    EventMachine.run do
      EventMachine.error_handler do |e|
        log(Logger::ERROR, self.to_s + '#run_loop', e.to_s)
      end

      @ivar.set true
    end
  end

  def add io, listener
    @handlers.send do |handlers|
      if handlers.key? io
        handlers
      else
        handlers.merge(io => Handler.create_async(self, io, listener))
      end
    end

    nil
  end

  def remove ios
    @handlers.send do |handlers|
      ios.each do |io|
        if handler = handlers[io]
          handler.value.remove_async unless handler.value.unbound
        end
      end

      hash_without_keys(handlers, ios)
    end

    nil
  end

  def write io, bytes
    raise "Failed to acquire handler for #{io}" unless handler = @handlers.deref[io]
    handler.value.write_async bytes
    nil
  end

  def length
    @handlers.deref.length
  end

  def await
    @handlers.await
  end
  
  class Handler < EventMachine::Connection
    include Concurrent::Concern::Logging

    attr_accessor :listener, :selector, :io, :unbound

    def receive_data data
      listener.trigger_read(data)
    end

    def unbind
      @unbound = true
      unless @intentional_remove
        listener.trigger_error IOError
        selector.remove [io]
      end
    end

    def write_async data
      EventMachine.next_tick{ send_data data }
    end

    def remove_async
      EventMachine.next_tick do
        @intentional_remove = true
        close_connection
      end
    end

    class << self
      include Concurrent::Concern::Logging

      def create_async selector, io, listener
        ivar = Concurrent::IVar.new

        EventMachine.next_tick do
          begin
            handler = EventMachine.attach(io, self) do |c|
              c.io = io
              c.selector = selector
              c.listener = listener
              c.unbound = false
            end
            ivar.set handler
          rescue => e
            log(Logger::ERROR, self.to_s + '.create_async', e.to_s)
            raise e
          end
        end

        ivar
      end
    end
  end
end
