require 'eventmachine'

class ConcurrentIO::EventMachineSelector
  include Concurrent::Concern::Logging
  include ConcurrentIO::BasicSelector

  def initialize timeout=nil
    @handlers = Concurrent::Agent.new(Hash.new, error_handler: proc{ |a,e| log(Logger::ERROR, a.to_s, e.to_s) })
    run!
  end

  def run
    @eventmachine_running = Concurrent::IVar.new
    super
  end

  def run!
    super

    # Force us to wait until EM is running
    @eventmachine_running.value
  end

  def running?
    super && @eventmachine_running.fulfilled? && EM.reactor_running?
  end

  def run_loop
    log(Logger::INFO, self.to_s + '#run_loop', 'Starting ...')
    EventMachine.run do
      EventMachine.error_handler do |e|
        log(Logger::ERROR, self.to_s + '#run_loop', e.to_s)
      end

      EventMachine.next_tick do
        @eventmachine_running.set true
        log(Logger::INFO, self.to_s + '#run_loop', 'Started')
      end
    end

    log(Logger::INFO, self.to_s + '#run_loop', 'Loop exited')
  rescue => e
    if @eventmachine_running.fulfilled?
      log(Logger::INFO, self.to_s + '#run_loop', 'Loop errored')
    else
      log(Logger::INFO, self.to_s + '#run_loop', 'Loop failed to start')
    end

    # This seems to be necessary (on Java, at least) in order to be able to restart
    EventMachine.cleanup_machine

    # Get rid of the existing handlers -- we can't know if these are in a consistent state or not
    @handlers.send do |handlers|
      handlers.each do |io, handler|
        io.close rescue nil
        if value = handler.value
          value.listener.trigger_error e
        end
      end

      Hash.new
    end
    @handlers.await

    # Rethrow
    raise e
  end

  def stop!
    # Make sure not to stop till we've started
    @eventmachine_running.value

    @stopped.try_set do
      EventMachine.stop_event_loop
      true
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

  def await
    @handlers.await
  end

  def remove ios
    @handlers.send do |handlers|
      ios.each do |io|
        if handler = handlers[io]
          # This blocks until EM is done adding the handle
          if value = handler.value
            value.remove_async
          else
            io.close rescue nil
          end
        end
      end

      hash_without_keys(handlers, ios)
    end

    nil
  end

  def write io, bytes
    return unless handler = @handlers.deref[io]
    handler.value.write_async bytes
    nil
  end

  def length
    @handlers.deref.length
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
      EventMachine.next_tick do
        unless @unbound
          send_data data
          listener.trigger_write data.bytesize
        end
      end
    end

    def remove_async
      EventMachine.next_tick do
        unless @unbound
          @intentional_remove = true
          close_connection
        end
      end
    end

    class << self
      include Concurrent::Concern::Logging

      def create_async selector, io, listener
        raise "EM is not running" unless EventMachine.reactor_running?

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
