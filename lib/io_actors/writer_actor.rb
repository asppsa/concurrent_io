class IOActors::WriterActor < Concurrent::Actor::Context

  def initialize io
    @io = io
    @writes = []
  end

  def on_message message
    case message
    when IOActors::OutputMessage
      append message.bytes
    when String
      append message
    when :write
      write
    when :close
      close
    end
  end

  def terminate!
    @writes = nil
    super
  end

  private

  def close
    @io.close rescue nil

    parent << :closed
    terminate!
  end

  def append bytes
    @writes.push bytes
    write
  end
    
  # This method will write whatever it can out of the first item in
  # the write queue.  If it can't write it all, it puts the rest back
  def write
    return unless bytes = @writes.shift

    num_bytes = begin
                  @io.write_nonblock(bytes)
                rescue IO::WaitWritable, Errno::EAGAIN
                  0
                end

    if num_bytes > 0
      @io.flush
    end

    # If the write could not be completed in one go, or if there are
    # more writes pending ...
    if num_bytes == 0
      @writes.unshift bytes
      self << :write
    elsif num_bytes < bytes.bytesize
      @writes.unshift bytes.byteslice(num_bytes..bytes.bytesize)
      self << :write
    elsif !@writes.empty?
      self << :write
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    close
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  end
end
