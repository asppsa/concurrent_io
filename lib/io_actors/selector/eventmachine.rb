require 'eventmachine'

class IOActors::EventMachineSelector < Concurrent::Actor::Context

  def initialize timeout=nil
    @handlers = {}
    run!
  end

  def on_message message
    case message
    when :run
      begin
        EventMachine.stop
      rescue RuntimeError
      ensure
        run!
      end

    when IOActors::AddMessage
      add message.io, message.actor

    when IOActors::RemoveMessage
      remove message.io

    when IOActors::WriteMessage
      write message.io, message.bytes

    when IOActors::CloseMessage
      close message.io

    when :stop
      begin
        EventMachine.stop
      rescue RuntimeError
      ensure
        terminate!
      end
    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  private

  def run!
    ivar = Concurrent::IVar.new
    
    @p = Concurrent::Promise.fulfill([ref,ivar]).then do |ref,ivar|
      begin
        EventMachine.run do
          #Signal.trap("INT")  { EventMachine.stop }
          #Signal.trap("TERM") { EventMachine.stop }
          ivar.set true
        end
      rescue Exception => e
        puts "#{e.to_s}\n#{e.backtrace}"
        ref << :run
      end
    end

    # Freeze until we're running
    ivar.value
  end

  def add io, actor
    @handlers[io] = Handler.create_async(io, actor)
    nil
  end

  def remove io
    return unless handler = @handlers.delete(io)
    handler.value.remove_async
    nil
  end

  def write io, bytes
    return unless handler = @handlers[io]
    handler.value.write_async bytes
    nil
  end

  def close io
    return unless handler = @handlers.delete(io)
    handler.value.close_async
    nil
  end

  class Handler < EventMachine::Connection
    attr_accessor :actor

    def receive_data data
      @actor << IOActors::InputMessage.new(data)
    end

    def unbind
      actor << :closed if actor
    end

    def write_async data
      EventMachine.next_tick{ send_data data }
    end

    def close_async
      EventMachine.next_tick{ close_connection }
    end

    def remove_async
      EventMachine.next_tick{ detach }
    end

    def self.create_async io, actor
      ivar = Concurrent::IVar.new

      EventMachine.next_tick do
        begin
          handler = EventMachine.attach(io, self) do |c|
            c.actor = actor
          end
          ivar.set handler
        rescue Exception => e
          p e
          raise e
        end
      end

      ivar
    end
  end
end
