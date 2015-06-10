class PingPongActor < Concurrent::Actor::Context

  def initialize io
    @received = ""
    @controller = IOActors::Controller.spawn('controller', io)
    log(Logger::INFO, "New")
  end

  def on_message message
    case message
    when IOActors::InputMessage
      @received += message.bytes
      dispatch_received
    when :start
      @controller << 'ping'
    when :die
      @controller.ask!(:close)
      terminate!
    when :closed
      terminate!
    end
  end

  def dispatch_received
    case @received
    when "ping"
      log(Logger::DEBUG, "got PING")
      PingPongStats.inc_pings
      @controller << 'pong'
      @received = ''
    when 'pong'
      log(Logger::DEBUG, "got PING")
      PingPongStats.inc_pongs
      @controller << 'ping'
      @received = ''
    end
  end
end
