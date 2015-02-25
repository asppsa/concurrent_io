require 'nio'

class IOActors::SelectActor < Concurrent::Actor::RestartingContext

  def initialize timeout=0.1
    @timeout = timeout or raise "timeout cannot be nil"
    @selector = NIO::Selector.new

    @registered = {}

    ref << :tick
  end

  def on_message message
    case message
    when IOActors::RegisterMessage
      register message.io, message.actor, message.direction
    when IOActors::DeregisterMessage
      deregister message.io
    when :tick, :reset!, :restart!
      tick
    when :stop
      terminate!
    end
  end

  private

  def registered? io, direction=nil
    return false unless exists = @registered.key?(io)

    case direction
    when nil
      exists
    when :r
      [:r, :rw].member? @registered[io]
    when :w
      [:w, :rw].member? @registered[io]
    when :rw
      @registered[io] == :rw
    end && @registered[io]
  end

  def register io, actor, direction
    log(Logger::DEBUG, "register(#{io}, #{actor}, #{direction})")

    return false if registered? io, direction

    actors = {direction => actor}

    # The only way this can be true is if we are upgrading from :r or
    # :w to :rw
    if registered?(io) and monitor = deregister(io)
      direction = :rw
      actors.merge!(monitor.value)
    end

    monitor = @selector.register(io, direction)
    @registered[io] = direction
    monitor.value = actors
    true
  rescue IOError
    envelope.sender << :close if envelope.sender
    false
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
    false
  end

  def deregister io, direction=nil
    return unless @registered.key?(io)
    log(Logger::DEBUG, "deregister(#{io}, #{direction})")

    # Completely deregister
    monitor = @selector.deregister(io)
    @registered.delete(io)

    # Re-register if necessary
    if direction and other = monitor.value.keys.find{ |k| k != direction }
      log(Logger::DEBUG, "reregister(#{io}, #{monitor.value[other]}, #{other})")
      register io, monitor.value[other], other
    end

    true
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
    false
  end

  def close m
    m.io.close rescue nil
    deregister m.io
    m.value.each do |dir,actor|
      actor << :close
    end
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end

  def tick
    ready = @selector.select(@timeout)
    (ready || []).each do |m|
      begin
        if m.io.nil?
          log(Logger::WARN, "nil IO object")
        elsif m.io.closed?
          log(Logger::DEBUG, "Closing #{m.io} -- already closed")
          close m
        else
          if [:r, :rw].member? m.readiness
            m.value[:r] << :read if m.value[:r]
            deregister m.io, :r
          end

          if [:w, :rw].member? m.readiness
            m.value[:w] << :write if m.value[:w]
            deregister m.io, :w
          end
        end
      rescue IOError, Errno::EBADF, Errno::ECONNRESET
        close m
      end
    end
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    ref << :tick
    true
  end
end
