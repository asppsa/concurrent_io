# Tell libevent that we are using threads
FFI::Libevent.use_threads!

class IOActors::FFILibeventSelector < Concurrent::Actor::RestartingContext

  def initialize timeout=nil, opts=nil
    @base = FFI::Libevent::Base.new(opts)

    # Create a trapper event that stops the loop on SIGINT
    @trapper = FFI::Libevent::Event.new(@base, "INT", :signal) do
      ref << :stop
    end
    @trapper.add!

    # # Create a pulse
    # @pulse = FFI::Libevent::Event.new(@base, -1, :persist) do
    #   puts "ping"
    # end
    # @pulse.add!(FFI::Libevent::Timeval.s 1)

    @events = {}

    run!
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  def on_message message
    case message
    when :run, :reset!, :restart!
      begin
        @base.loopbreak! if @base
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
        if @base
          @base.loopbreak!
        end
      rescue Exception => e
        log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
      ensure
        # Garbage collect
        @base = nil
        @events = nil
        terminate!
      end

    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  private

  def run!
    # Start the loop in a separate thread
    @p = Concurrent::Promise.fulfill(@base).then do |base|
      begin
        base.loop!(:no_exit_on_empty)
      rescue Exception => e
        log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
        raise e
      end
    end.then do |ret|
      if ret == 1
        log(Logger::INFO, "Restarting event loop")
        ref << :run
      else
        log(Logger::INFO, "Event loop is finished")
      end
    end.rescue do |e|
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
      ref << :run
    end

    @p.execute

    log(Logger::INFO, "Running promise")
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    ref << :run
  end

  def add io, actor
    raise "already added" if @events.key?(io)


    # Create an evbuffer for reading into.  This stays around because
    # of the below closure
    evb = FFI::Libevent::EvBuffer.new
    
    # This is called whenever a read occurs
    on_read = proc do |bev|
      begin
        # Read into evbuffer
        bev.read evb

        # Get the new buffer's length
        len = evb.length
        if len > 0
          actor << IOActors::InputMessage.new(evb.remove len)
        end
      rescue Exception => e
        log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
      end
    end

    # This occurs on certain error conditions, but it includes a
    # "connect" event
    on_event = proc do |bev,events|
      begin
        is_error = events & (FFI::Libevent::BEV_EVENT_ERROR |
                             FFI::Libevent::BEV_EVENT_EOF |
                             FFI::Libevent::BEV_EVENT_TIMEOUT) != 0

        return unless is_error

        # This is intended to render the bufferevent inert so that the
        # socket can be closed
        disable bev
        ref << IOActors::CloseMessage.new(io)
      rescue Exception => e
        log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
      end        
    end

    # Create the bufferevent, enabled for both reading and writing
    bev = FFI::Libevent::BufferEvent.socket(@base, io)
    bev.set_callbacks(read: on_read,
                      event: on_event)
    bev.enable!(FFI::Libevent::EV_READ |
                FFI::Libevent::EV_WRITE)

    @events[io] = [bev, actor]
    nil
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  def disable bev
    bev.disable!(FFI::Libevent::EV_READ | FFI::Libevent::EV_WRITE)
    bev.set_callbacks read: nil, event: nil
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  def close io
    if actor = remove(io)
      actor << :closed
    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  ensure
    io.close rescue nil
  end

  def remove io
    if data = @events.delete(io)
      bev, actor = data
      disable bev
      actor
    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  def write io, bytes
    return unless @events.key?(io)

    bev = @events[io].first
    bev.write bytes

    nil
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end
end

