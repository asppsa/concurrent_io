class IOActors::ReaderActor < Concurrent::Actor::RestartingContext

  def initialize io, logger=nil, buffer_size=4096
    @io = io
    @logger = logger
    @buffer_size = buffer_size
    @listener = nil
  end

  def on_message message
    case message
    when IOActors::InformMessage
      @listener = message.actor
    when :read
      read
    when :close
      close
    end
  end

  private

  def close
    parent << :close if parent
    @io.close rescue nil
    terminate!
  end

  def read
    # Read bytes if any are available.
    bytes = begin
              @io.read_nonblock(@buffer_size)
            rescue IO::WaitReadable
              nil
            end

    if bytes && @listener
      @listener << IOActors::InputMessage.new(bytes)
    end

    # Keep reading if we filled the string
    if bytes && bytes.bytesize == @buffer_size
      self << :read
    end
  rescue IOError, Errno::EBADF, Errno::ECONNRESET
    close
  end
end
