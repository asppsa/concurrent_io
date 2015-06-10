class IOActors::Reader < Concurrent::Actor::Context

  def initialize io, listener, buffer_size=4096
    @io = io
    @buffer_size = buffer_size
    @listener = listener
  end

  def on_message message
    case message
    when :read #, :reset!, :restart!
      read
    when :stop
      terminate!
    end
  end

  private

  def read
    # Read bytes if any are available.
    total = 0
    loop do
      bytes = begin
                @io.read_nonblock(@buffer_size)
              rescue IO::WaitReadable
                nil
              end

      if bytes
        total += bytes.bytesize
        @listener << IOActors::InputMessage.new(bytes) if @listener
      end

      # Keep reading if we filled the string.  Otherwise if there is a
      # selector, ask it to notify us when there's something available.
      if bytes.nil? || bytes.bytesize < @buffer_size
        parent << IOActors::EnableReadMessage.new(@io) if parent
        break
      end
    end
  rescue IOError, Errno::EBADF, Errno::ECONNRESET
    parent << IOActors::CloseMessage.new(@io) if parent
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    total
  end
end
