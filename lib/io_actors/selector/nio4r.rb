require 'nio'

class IOActors::NIO4RSelector < Concurrent::Actor::RestartingContext

  def initialize timeout=0.1
    @timeout = timeout or raise "timeout cannot be nil"
    @selector = NIO::Selector.new

    @read_active = []
    @read_inactive = []
    @readers = {}

    @write_active = []
    @write_inactive = []
    @writers = {}

    @actors = {}

    @all = []
    @registered = {}

    ref << :tick
  end

  def on_message message
    case message
    when :tick, :reset!, :restart!
      tick

    when IOActors::AddMessage
      add message.io, message.actor

    when IOActors::RemoveMessage
      remove message.io

    when IOActors::CloseMessage
      close message.io

    when IOActors::WriteMessage
      write message.io, message.bytes

    when IOActors::EnableReadMessage
      enable_read message.io

    when IOActors::EnableWriteMessage
      enable_write message.io

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
    end
  end

  def add io, actor
    raise "already added" if @all.member?(io)

    @readers[io] = IOActors::Reader.spawn('reader', io, actor)
    enable_read io

    @writers[io] = IOActors::Writer.spawn('writer', io)
    disable_write io

    @actors[io] = actor
    @all.push io
    true
  rescue IOError
    close io
    false
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    false
  end

  def remove io
    return unless @registered.key?(io)

    # Delete reader and writer
    @readers.delete(io) << :stop rescue nil
    @writers.delete(io) << :stop rescue nil

    # Completely deregister
    monitor = @selector.deregister(io)
    @registered.delete(io)

    # Return the actor
    @actors.delete(io)
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    false
  end

  def enable_read io
    reregister io do |registered|
      case registered
      when :w,:rw
        :rw
      else
        :r
      end
    end
  end

  def disable_read io
    reregister io do |registered|
      case registered
      when :rw, :w
        :w
      else
        nil
      end
    end
  end

  def enable_write io
    reregister io do |registered|
      case registered
      when :w, :rw
        :rw
      else
        :w
      end
    end
  end

  def disable_write io
    reregister io do |registered|
      case registered
      when :r, :rw
        :r
      else
        nil
      end
    end
  end

  def reregister io
    # Deregister if currently registered
    @selector.deregister io if @registered[io]

    # Reregister if necessary
    if @registered[io] = yield(@registered[io])
      @selector.register io, @registered[io]
    end

    # Wakeup (does this actually work?)
    @selector.wakeup
  end

  def close io
    if actor = remove(io) and envelope.sender != actor
      actor << :closed
    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  ensure
    io.close rescue nil
  end

  def tick
    ready = @selector.select(@timeout)
    (ready || []).each do |m|
      io = m.io
      begin
        if io.nil?
          log(Logger::WARN, "nil IO object")
        elsif io.closed?
          close io
        else
          if [:r, :rw].member? m.readiness
            @readers[io] << :read if @readers[io]
            disable_read io
          end

          if [:w, :rw].member? m.readiness
            @writers[io] << :write if @writers[io]
            disable_write io
          end
        end
      rescue IOError, Errno::EBADF, Errno::ECONNRESET
        close io
      end
    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  ensure
    ref << :tick
    true
  end

  def write io, bytes
    if writer = @writers[io]
      writer << bytes
    end
  end
end
