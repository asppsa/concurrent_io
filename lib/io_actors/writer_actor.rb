class IOActors::WriterActor < Concurrent::Actor::Context

  def initialize io
    @io = io
    @writes = []
    @selector = nil
  end

  def on_message message
    case message
    when IOActors::SelectMessage
      @selector = message.actor
    when IOActors::OutputMessage
      append message.bytes
    when String
      append message
    when :write
      write
    when :close
      close(envelope.sender == parent)
    end
  end

  def close from_parent=false
    @io.close rescue nil
    @selector << IOActors::DeregisterMessage.new(@io, :w) if @selector
    @io = nil
    @selector = nil
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    parent << :close unless from_parent
    terminate!
  end

  private

  def append bytes
    @writes.push bytes
    write
  end

  def register
    @selector << IOActors::RegisterMessage.new(@io, ref, :w) if @selector
  end

  # This method will write whatever it can out of the first item in
  # the write queue.  If it can't write it all, it puts the rest back
  def write
    total = 0
    while bytes = @writes.shift
      num_bytes = begin
                    @io.write_nonblock(bytes)
                  rescue IO::WaitWritable, Errno::EAGAIN
                    0
                  end

      if num_bytes > 0
        @io.flush
        total += num_bytes
      end

      # If the write could not be completed in one go, or if there are
      # more writes pending ...
      if num_bytes == 0
        @writes.unshift bytes
        register
        break
      elsif num_bytes < bytes.bytesize
        @writes.unshift bytes.byteslice(num_bytes..bytes.bytesize)
        register
        break
      end
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    close
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    total
  end
end
