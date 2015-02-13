require 'nio'

class IOActors::SelectActor < Concurrent::Actor::RestartingContext

  def initialize timeout=0.1, logger=nil
    @timeout = timeout or raise "timeout cannot be nil"
    @logger = logger
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
    @logger.debug "register(#{io}, #{actor})" if @logger
    monitor = @selector.register(io, :r)
    monitor.value = actor
  rescue Exception => e
    @logger.error e if @logger
  end

  def deregister io
    @logger.debug "deregister(#{io})" if @logger
    @selector.deregister(io)
  rescue Exception => e
    @logger.error e if @logger
  end


  def close io
    io.close
    self << IOActors::DeregisterMessage.new(io)
  rescue
    nil
  end

  def tick
    @selector.select(@timeout) do |m|
      begin
        if m.io.nil?
          @logger.warn "nil IO object" if @logger
        elsif m.io.closed?
          m.value << :close

          # Do this in case the actor is already dead
          close m.io
        else
          m.value << :read
        end
      rescue IOError, Errno::EBADF, Errno::ECONNRESET
        m.value << :close

        # Do this in case the actor is already dead
        close m.io
      end
    end
  rescue Exception => e
    @logger.error e if @logger
  ensure
    self << :tick
  end
end
