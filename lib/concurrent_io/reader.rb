class ConcurrentIO::Reader
  include Concurrent::Concern::Logging

  def initialize selector, io, listener, buffer_size=4096
    @selector = selector
    @io = io
    @listener = listener
    @buffer_size = buffer_size
  end

  ##
  # Reads as much from the IO as possible in non-blocking mode
  def read!
    Concurrent::Future.execute(:executor => :fast) do
      begin
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
            @listener.trigger_read(bytes)
          end

          # Keep reading if we filled the string.  Otherwise if there is a
          # selector, ask it to notify us when there's something available.
          if bytes.nil? || bytes.bytesize < @buffer_size
            @selector.enable_read @io
            break
          end
        end
      rescue IOError, Errno::EBADF, Errno::ECONNRESET => e
        @listener.trigger_error e
        @selector.remove [@io]
      rescue => e
        log(Logger::ERROR, self.to_s + '#read!', e.to_s)
        @selector.enable_read @io
      ensure
        return total
      end
    end
  end
end
