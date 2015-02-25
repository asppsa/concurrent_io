class IOActors::ReaderActor < Concurrent::Actor::Context

  def initialize io, listener=nil, buffer_size=4096
    @io = io
    @buffer_size = buffer_size
    @listener = listener
    @selector = nil
  end

  def on_message message
    case message
    when IOActors::InformMessage
      @listener = message.actor
    when IOActors::SelectMessage
      @selector = message.actor
    when :read
      read
    when :close
      close(envelope.sender == parent)
    end
  end

  def close from_parent=false
    @io.close rescue nil
    @selector << IOActors::DeregisterMessage.new(@io) if @selector
    @io = nil
    @selector = nil
    @listener << :closed if @listener
    @listener = nil
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    parent << :close unless from_parent
    terminate!
  end

  private

  def register
    @selector << IOActors::RegisterMessage.new(@io, ref, :r) if @selector
  end

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
        register
        break
      end
    end
  rescue IOError, Errno::EBADF, Errno::ECONNRESET
    close
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    total
  end
end
