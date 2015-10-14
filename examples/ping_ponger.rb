require 'securerandom'

class PingPonger
  include IOActors::Listener
  include Concurrent::Concern::Logging

  PING = 'ping' #SecureRandom.random_bytes(1000)
  PONG = 'PONG' #SecureRandom.random_bytes(1000)

  def initialize type, generation, number, io
    @io = io

    @label = "#{type}-#{generation}-#{number}"

    @selector = IOActors.default_selector
    @received = Concurrent::Agent.new([], error_handler: proc{ |e| log(Logger::ERROR, @label, e.to_s) })

    on_read do |bytes|
      @received.send do |received|
        dispatch_received received.dup.push(bytes)
      end
    end

    on_error do |e|
      log(Logger::ERROR, @label, e.to_s)
    end

    on_write do |count|
      log(Logger::DEBUG, @label, "Wrote #{count} bytes")
    end

    @selector.add @io, self
  end

  def start!
    @selector.write @io, PING
  end

  def die!
    @selector.remove [@io]
  end

  def dispatch_received received
    received.join("").tap do |str|
      case str
      when PING
        log(Logger::DEBUG, @label, "got PING")
        PingPongStats.inc_pings
        received.clear
        @selector.write @io, PONG rescue die!
      when PONG
        log(Logger::DEBUG, @label, "got PONG")
        PingPongStats.inc_pongs
        received.clear
        @selector.write @io, PING rescue die!
      end
    end
  rescue => e
    log(Logger::ERROR, @label + "#dispatch_received", e.to_s)
  ensure
    return received
  end
end
