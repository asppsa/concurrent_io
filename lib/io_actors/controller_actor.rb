class IOActors::ControllerActor < Concurrent::Actor::RestartingContext

  def initialize io, logger=nil
    @io = io
    @reader = IOActors::ReaderActor.spawn("#{io}.reader", io, logger)
    @writer = IOActors::WriterActor.spawn("#{io}.writer", io, logger)
    @selector = nil
    @listener = nil
  end

  def on_message message
    case message
    when IOActors::SelectMessage
      select message.actor
    when IOActors::InformMessage
      @listener = message.actor
      @reader << message
    when :read
      @reader << message
    when IOActors::OutputMessage
      @writer << message
    when :close
      close
    when :reader
      @reader
    when :writer
      @writer
    end
  end

  private

  def close
    @selector << IOActors::DeregisterMessage.new(@io) if @selector
    @listener << :close if @listener
    @io.close rescue nil
    terminate!
  end

  def select actor
    # Deregister if there is an existing selector
    @selector << IOActors::DeregisterMessage.new(@io) if @selector

    @selector = actor
    @selector << IOActors::RegisterMessage.new(@io, @reader)
  end
end
