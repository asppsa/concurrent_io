# Tell libevent that we are using threads
FFI::Libevent.use_threads!

class IOActors::FFILibeventSelector
  include IOActors::BasicSelector
  include Concurrent::Concern::Logging

  def initialize timeout=nil, opts=nil
    @base = FFI::Libevent::Base.new(opts)

    # Create a trapper event that stops the loop on SIGINT, and then
    # passes the interrupt on
    @trapper = FFI::Libevent::Event.new(@base, "INT", :signal) do |_,_,base|
      base.loopbreak!
      self.stop!
      Process.kill("INT", Process.pid)
    end
    @trapper.add!

    @events = Concurrent::Agent.new({}, error_handler: proc{ |e| log(Logger::ERROR, self.to_s, e.to_s) })

    run!
  rescue => e
    log(Logger::ERROR, self.to_s + '#initialize', e.to_s)
  end

  def stop!
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
    rescue => e
      log(Logger::ERROR, self.to_s + '#stop!', e.to_s)
    end
  rescue => e
    log(Logger::ERROR, self.to_s + '#stop!', e.to_s)
  end

  def run_loop
    log(Logger::INFO, self.to_s + '#run_loop', "Starting")
    result = @base.loop!(:no_exit_on_empty)
    log(Logger::INFO, self.to_s + '#run_loop', "Loop done: #{result}")

    if result == 0
      @stopped.try_set true
    end
  end

  def stop!
    @base.loopbreak! rescue nil
  end

  def add io, listener
    @events.send do |events|
      if events.key? io
        events
      else
        # Set the io object to non-blocking
        #FFI::Libevent::Util.make_socket_nonblocking io

        # Create the bufferevent, enabled for both reading and writing
        bev = FFI::Libevent::BufferEvent.socket(@base, io, :close_on_free)

        # Create the callback object
        event_handler = EventHandler.new(self, io, listener)

        # Set the methods from the object as libevent callbacks
        bev.set_callbacks(read: event_handler.method(:on_read).to_proc,
                          event: event_handler.method(:on_event).to_proc)

        # Enable the bufferevent
        bev.enable!

        events.merge(io => bev)
      end
    end
  rescue => e
    log(Logger::ERROR, self.to_s + '#add', e.to_s)
  end

  def add! io, listener
    add io, listener
    @events.await
    nil
  end

  def remove ios
    @events.deref.tap do |events|
      ios.each do |io|
        if bev = events[io]
          bev.disable!
          bev.unset_callbacks
        end
      end
    end
    
    @events.send do |events|
      hash_without_keys(events, ios)
    end
  rescue => e
    log(Logger::ERROR, self.to_s + '#remove', e.to_s)
  end

  def write io, bytes
    return unless bev = @events.deref[io]
    bev.write bytes
    nil
  rescue Exception => e
    log(Logger::ERROR, self.to_s + '#write', e.to_s)
  end

  def length
    @events.deref.length
  end

  class Error < StandardError
    def initialize events
      @events = events
      super nil
    end

    def message
      ms = []
      ms.push "generic error" if error?
      ms.push "timeout" if timeout?
      ms.push "EOF" if eof?

      ms.join "; "
    end

    alias to_s message

    def error?
      @events & FFI::Libevent::BEV_EVENT_ERROR != 0
    end

    def eof?
      @events & FFI::Libevent::BEV_EVENT_EOF != 0
    end

    def timeout?
      @events & FFI::Libevent::BEV_EVENT_TIMEOUT != 0
    end
  end

  ##
  # These methods are used as callbacks in libevent.  They are kept
  # here to ensure that they don't accidentally access the listener's
  # variables.  Because libevent itself is single-threaded, it's safe
  # to share variables between the callbacks though.
  class EventHandler
    include Concurrent::Concern::Logging

    def initialize selector, io, listener
      @listener = listener
      @selector = selector
      @io = io
    end

    ##
    # This is called whenever a read occurs
    def on_read bev
      # Create an empty EvBuffer
      evb = FFI::Libevent::EvBuffer.new

      # Read into evbuffer
      bev.read evb

      # Stop right now, thank you very much
      return unless @listener

      # Do this in a separate thread so that the loop doesn't get held
      # up
      @listener.trigger_read evb.copyout(evb.length)
    rescue => e
      log(Logger::ERROR, self.to_s + '#on_read', "#{e.to_s}\n#{e.backtrace}")
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

      # The instance vars below may have been unset already
      return unless @selector

      # Dispatch in a separate thread in order not to hold up the loop
      @selector.remove [@io]
      @listener.trigger_error Error.new(events)

      # Remove refs in this object
      @selector = @listener = @io = nil
    rescue => e
      log(Logger::ERROR, self.to_s + '#on_event', e.to_s)
    end
  end
end
