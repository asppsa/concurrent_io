require 'securerandom'

class PingPongActor < Concurrent::Actor::Context

  PING = SecureRandom.random_bytes(1000)
  PONG = SecureRandom.random_bytes(1000)

  def initialize io
    @received = ""
    @controller = IOActors::Controller.spawn('controller', io)
    log(Logger::INFO, "New")
  end

  def on_message message
    case message
    when IOActors::InputMessage
      @received << message.bytes
      dispatch_received
    when :start
      @controller << PING
    when :die
      @controller.ask!(:close)
      terminate!
    when :closed
      terminate!
    end
    nil
  end

  def dispatch_received
    case @received
    when PING
      log(Logger::DEBUG, "got PING")
      PingPongStats.inc_pings
      @controller << PONG
      @received = ''
    when PONG
      log(Logger::DEBUG, "got PING")
      PingPongStats.inc_pongs
      @controller << PING
      @received = ''
    end
    nil
  end
end
