class ConcurrentIO::Writer
  include Concurrent::Concern::Logging

  def initialize selector, io, listener
    @selector = selector
    @io = io
    @listener = listener
    @writes = Concurrent::Agent.new([], error_handler: proc{ |a,e| log(Logger::ERROR, a.to_s, e.to_s) })
  end

  def append bytes
    @writes.send do |writes|
      flush writes.dup.push(bytes)
    end
  end

  def flush!
    @writes.send do |writes|
      flush writes.dup
    end
  end

  def await
    @writes.await
  end

  def clear
    @writes.send do |writes|
      []
    end
  end

  def clear!
    clear
    await
  end

  ##
  # This method will write whatever it can out of the first item in
  # the write queue.  It returns an array of items it failed to flush
  def flush writes
    total = 0
    while bytes = writes.shift
      next unless bytes.bytesize > 0

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
        writes.unshift bytes
        @selector.enable_write @io
        break
      elsif num_bytes < bytes.bytesize
        writes.unshift bytes.byteslice(num_bytes..bytes.bytesize)
        @selector.enable_write @io
        break
      end
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
    @selector.remove [@io]
    @listener.trigger_error e
  rescue => e
    log(Logger::ERROR, self.to_s + '#flush', e.to_s)
    @selector.enable_write @io
  ensure
    @listener.trigger_write total
    return writes
  end
end
