class PingPongActor < Concurrent::Actor::Context

  def initialize io
    @controller = IOActors::ControllerActor.spawn('controller', io)
    @controller.ask! IOActors::SelectMessage.new(IOActors.selector)
  end

  def on_message message
    log(Logger::DEBUG, message)
    
    case message
    when IOActors::InputMessage
      log(Logger::INFO, message.bytes)
      self << message.bytes.to_sym
    when :start
      @controller << 'ping'
    when :ping
      log(Logger::INFO, "got PING")
      @controller << 'pong'
    when :pong
      log(Logger::INFO, "got PONG")
      @controller << 'ping'
    when :die
      @controller << :close
      terminate!
    end
  end
end
