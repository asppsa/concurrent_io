class IOActors::ControllerActor < Concurrent::Actor::RestartingContext

  def initialize io
    @io = io
    listener = if parent != Concurrent::Actor.root
                 parent
               end
    @reader = IOActors::ReaderActor.spawn("reader", io, listener)
    @writer = IOActors::WriterActor.spawn("writer", io)
    @selector = nil
  end

  def on_message message
    case message
    when IOActors::SelectMessage
      select message.actor
    when IOActors::InformMessage
      @reader << message
    when :read
      @reader << message
    when IOActors::OutputMessage, String
      @writer << message
    when :close
      close
    when :closed
      closed
    when :reader
      @reader
    when :writer
      @writer
    when :listener
      listener
    end
  end

  private

  def listener
    @reader.ask! :listener
  rescue
    nil
  end

  def close
    @io.close rescue nil
    closed
  end

  def closed
    @selector << IOActors::DeregisterMessage.new(@io) if @selector
    if l = listener
      l << :closed
    end
    terminate!
  end

  def select actor
    # Deregister if there is an existing selector
    @selector << IOActors::DeregisterMessage.new(@io) if @selector

    @selector = actor
    @selector << IOActors::RegisterMessage.new(@io, @reader)
  end
end
