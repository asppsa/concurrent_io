require 'nio'

class IOActors::SelectActor < Concurrent::Actor::RestartingContext

  def initialize timeout=0.1
    @timeout = timeout or raise "timeout cannot be nil"
    @selector = NIO::Selector.new

    self << :tick
  end

  def on_message message
    case message
    when IOActors::RegisterMessage
      register message.io, message.actor
    when IOActors::DeregisterMessage
      deregister message.io
    when :tick
      tick
    when :stop
      terminate!
    end
  end

  private

  def register io, actor
    log(Logger::DEBUG, "register(#{io}, #{actor})")
    monitor = @selector.register(io, :r)
    monitor.value = actor
  rescue IOError
    envelope.sender << :closed if envelope.sender
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end

  def deregister io
    return unless @selector.registered? io
    log(Logger::INFO, "deregister(#{io})")
    @selector.deregister(io)
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end

  def close io
    log(Logger::INFO, "close(#{io})")
    io.close rescue nil
    self << IOActors::DeregisterMessage.new(io)
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end

  def tick
    @selector.select(@timeout) do |m|
      log(Logger::INFO, "#{m.io}: #{m.io.closed?}")
      
      begin
        if m.io.nil?
          log(Logger::WARN, "nil IO object")
        elsif m.io.closed?
          log(Logger::INFO, "Closing #{m.io} -- already closed")
          m.value << :close

          # Do this in case the actor is already dead
          close m.io
        else
          #log(Logger::INFO, "Issuing read to #{m.value}")
          m.value << :read
        end
      rescue IOError, Errno::EBADF, Errno::ECONNRESET
        log(Logger::INFO, "Closing #{m.io} -- error")
        m.value << :close

        # Do this in case the actor is already dead
        close m.io
      end
    end
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    self << :tick
  end
end
