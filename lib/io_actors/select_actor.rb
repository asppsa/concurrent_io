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
    envelope.sender << :close if envelope.sender
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end

  def deregister io
    return unless @selector.registered? io
    log(Logger::DEBUG, "deregister(#{io})")
    @selector.deregister(io)
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end

  def close m
    log(Logger::DEBUG, "close(#{m})")
    m.io.close rescue nil
    self << IOActors::DeregisterMessage.new(m.io)
    m.value << :close
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end

  def tick
    @selector.select(@timeout) do |m|
      log(Logger::DEBUG, "#{m.io}: #{m.io.closed?}")
      
      begin
        if m.io.nil?
          log(Logger::WARN, "nil IO object")
        elsif m.io.closed?
          log(Logger::DEBUG, "Closing #{m.io} -- already closed")
          close m
        else
          m.value << :read
        end
      rescue IOError, Errno::EBADF, Errno::ECONNRESET
        log(Logger::DEBUG, "Closing #{m.io} -- error")
        close m
      end
    end
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    self << :tick
  end
end
