require 'concurrent/promise'

# Tell libevent that we are using threads
FFI::Libevent.use_threads!

class IOActors::FFILibeventSelectActor < Concurrent::Actor::RestartingContext

  def initialize timeout=nil
    @base = FFI::Libevent::Base.new

    # Create a trapper event that stops the loop on SIGKILL
    @trapper = FFI::Libevent::Event.new(@base, "INT", FFI::Libevent::EV_SIGNAL) do
      ref << :stop
    end
    @trapper.add!

    @heartbeat = FFI::Libevent::Event.new(@base, -1, FFI::Libevent::EV_PERSIST) do
      log(Logger::WARN, "Loop Running")
    end
    @heartbeat.add! FFI::Libevent::Timeval.s 2

    @events = {}
    run!
    log(Logger::INFO, "Running")
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  def on_message message
    log(Logger::INFO, message.to_s)

    case message
    when :run, :reset!, :restart!
      run!
    when IOActors::RegisterMessage
      register message.io, message.actor, message.direction
    when IOActors::DeregisterMessage
      deregister message.io, message.direction
    when :stop
      @base.loopbreak
      terminate!
    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  private

  def run!
    # Start the loop in a separate thread
    @p = Concurrent::Promise.new do
      begin
        @base.loop(FFI::Libevent::EVLOOP_NO_EXIT_ON_EMPTY)
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
  end

  def register io, actor, direction
    flag = case direction
           when Fixnum
             direction
           when :r
             FFI::Libevent::EV_READ
           when :w
             FFI::Libevent::EV_WRITE
           when :rw
             FFI::Libevent::EV_READ | FFI::Libevent::EV_WRITE
           end

    # Note that the proc will be called within the event loop thread
    log(Logger::INFO, "Create Event")
    event = begin
              FFI::Libevent::Event.new(@base, io, flag) do |fd, flag|
                begin
                  log(Logger::INFO, "event #{flag}")

                  case flag
                  when FFI::Libevent::EV_READ
                    actor << :read
                  when FFI::Libevent::EV_WRITE
                    actor << :write
                  end

                  ref << IOActors::DeregisterMessage.new(io, direction)
                rescue Exception => e
                  log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
                end
              end
            rescue IOError
              envelope.sender << :close if envelope.sender
              nil
            end

    if event
      log(Logger::INFO, "Event Created")

      # Add event to the loop
      log(Logger::INFO, "Add Event")
      event.add!
      log(Logger::INFO, "Event Added")

      # This holds the event in memory, which will keep it alive
      @events[event_key(io, direction)] = event
      log(Logger::INFO, "#{@events}")
    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  def event_key io, direction
    "#{io.hash}#{direction}"
  end

  def deregister io, direction
    log(Logger::INFO, "Deregister #{io}, #{direction}")

    key = event_key(io, direction)
    if event = @events[key]
      log(Logger::INFO, "#{event}")
      
      # Reap from the event loop
      event.del!

      # Remove it from memory
      @events.delete key
    end
    nil
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end
end

