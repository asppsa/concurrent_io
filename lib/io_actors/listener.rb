module IOActors::Listener
  def on_read &block
    @listener_on_read = block
  end

  def trigger_read bytes
    if @listener_on_read
      @listener_on_read.call bytes rescue nil
    end
    nil
  end

  def on_write &block
    @listener_on_write = block
  end

  def trigger_write count
    if @listener_on_write
      @listener_on_write.call count rescue nil
    end
    nil
  end

  def on_error &block
    @listener_on_error = block
  end

  def trigger_error e
    if @listener_on_error
      @listener_on_error.call e rescue nil
    end
    nil
  end

end
