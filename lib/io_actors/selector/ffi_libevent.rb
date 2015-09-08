# Tell libevent that we are using threads
FFI::Libevent.use_threads!

class IOActors::FFILibeventSelector < Concurrent::Actor::Context

  def initialize timeout=nil, opts=nil
    @base = FFI::Libevent::Base.new(opts)

    # Create a trapper event that stops the loop on SIGINT, and then
    # passes the interrupt on
    r = ref
    @trapper = FFI::Libevent::Event.new(@base, "INT", :signal) do |_,_,base|
      base.loopbreak!
      r << :stop
      Process.kill("INT", Process.pid)
    end
    @trapper.add!

    @events = {}

    run!
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  def on_message message
    case message
    when :run #, :reset!, :restart!
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
        if @trapper
          @trapper.del!
        end

        if @base
          @base.loopbreak!

          # Wait for the base to stop
          while !@base.got_break?
            sleep 0.1
          end
        end
      rescue Exception => e
        log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
      ensure
        # Encourage garbage collection
        @base = @events = @trapper = nil
        terminate!
      end

    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  private

  def run!
    # Start the loop in a separate thread
    @p = Concurrent::Promise.fulfill([ref,@base]).then do |ref,base|
      begin
        unless base.loop!(:no_exit_on_empty) == 0
          ref << :run
        end
      rescue Exception => e
        puts "#{e.to_s}\n#{e.backtrace}"
        ref << :run
      end
    end

    @p.execute

    log(Logger::INFO, "Running promise")
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    ref << :run
  end

  def add io, actor
    raise "already added" if @events.key?(io)

    # Set the io object to non-blocking
    FFI::Libevent::Util.make_socket_nonblocking io

    # Create the bufferevent, enabled for both reading and writing
    bev = FFI::Libevent::BufferEvent.socket(@base, io)

    # Create the callback object
    event_handler = EventHandler.new(ref, io, actor)

    # Set the methods from the object as libevent callbacks
    bev.set_callbacks(read: event_handler.method(:on_read).to_proc,
                      event: event_handler.method(:on_event).to_proc)

    # Enable the bufferevent
    bev.enable!

    @events[io] = [bev, actor]
    nil
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
      bev.disable!
      bev.unset_callbacks
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

  ##
  # This is a special variety of InputMessage that takes an EvBuffer
  # instead of a string.
  class InputMessage < IOActors::InputMessage
    def bytes
      evb = super
      len = evb.length
      if len > 0
        evb.copyout len
      else
        ""
      end
    end
  end

  ##
  # These methods are used as callbacks in libevent.  They are kept
  # here to ensure that they don't accidentally access the actor's
  # variables.  Because libevent itself is single-threaded, it's safe
  # to share variables between the callbacks though.
  class EventHandler
    def initialize ref, io, actor
      @actor = actor
      @ref = ref
      @io = io
    end

    ##
    # This is called whenever a read occurs
    def on_read bev
      # Create an empty EvBuffer
      evb = FFI::Libevent::EvBuffer.new

      # Read into evbuffer
      bev.read evb

      # Pass the evb to the listener in a special subclassed
      # InputMessage.  This saves on a memory copy that would
      # otherwise need to happen in this thread
      @actor << InputMessage.new(evb)
    rescue Exception => e
      puts "#{e.to_s}\n#{e.backtrace}"
    end

    ##
    # This occurs on certain error conditions, but it includes a
    # "connect" event
    def on_event bev, events
      is_error = events & (FFI::Libevent::BEV_EVENT_ERROR |
                           FFI::Libevent::BEV_EVENT_EOF |
                           FFI::Libevent::BEV_EVENT_TIMEOUT) != 0

      return unless is_error

      # This is intended to render the bufferevent inert so that the
      # socket can be closed
      bev.disable!
      bev.unset_callbacks

      # Tell the actor to close this eventbuffer
      @ref << IOActors::CloseMessage.new(@io)
    rescue Exception => e
      puts "#{e.to_s}\n#{e.backtrace}"
    end
  end
end
