class PingPongActor < Concurrent::Actor::Context

  def initialize io
    @controller = IOActors::ControllerActor.spawn('controller', io)
    @controller.ask! IOActors::SelectMessage.new(IOActors.selector)
    @controller << :read
    log(Logger::INFO, "New")
  end

  def on_message message
    case message
    when IOActors::InputMessage
      log(Logger::DEBUG, message.bytes)
      ref << message.bytes.to_sym
    when :start
      @controller << 'ping'
    when :ping
      log(Logger::WARN, "got PING")
      @controller << 'pong'
    when :pong
      log(Logger::WARN, "got PONG")
      @controller << 'ping'
    when :die
      log(Logger::WARN, "got DIE")
      @controller.ask!(:close)
      terminate!
    when :closed
      log(Logger::WARN, "got CLOSED")
      terminate!
    end
  end
end
