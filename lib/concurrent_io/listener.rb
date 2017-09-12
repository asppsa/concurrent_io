module ConcurrentIO::Listener

  def self.included mod
    mod.include Concurrent::Concern::Logging
  end

  def on_read &block
    @listener_on_read = block
  end

  def trigger_read bytes
    if @listener_on_read
      begin
        @listener_on_read.call bytes
      rescue => e
        log(Logger::ERROR, "#{self}.trigger_read", e.to_s)
      end
    end
    nil
  end

  def on_write &block
    @listener_on_write = block
  end

  def trigger_write count
    if @listener_on_write
      begin
        @listener_on_write.call count
      rescue => e
        log(Logger::ERROR, "#{self}.trigger_write", e.to_s)
      end
    end
    nil
  end

  def on_error &block
    @listener_on_error = block
  end

  def trigger_error e
    if @listener_on_error
      begin
        @listener_on_error.call e
      rescue => e
        log(Logger::ERROR, "#{self}.trigger_error", e.to_s)
      end
    end
    nil
  end

end
