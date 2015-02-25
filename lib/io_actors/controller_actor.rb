class IOActors::ControllerActor < Concurrent::Actor::Context

  def initialize io
    @io = io
    listener = if parent != Concurrent::Actor.root
                 parent
               end
    @reader = IOActors::ReaderActor.spawn("reader", io, listener)
    @writer = IOActors::WriterActor.spawn("writer", io)
  end

  def on_message message
    case message
    when IOActors::SelectMessage
      @reader << message
      @writer << message
    when IOActors::InformMessage, :read
      redirect @reader
    when IOActors::OutputMessage, String
      redirect @writer
    when :close
      close(envelope.sender == @reader, envelope.sender == @writer)
    when :reader
      @reader
    when :writer
      @writer
    when :listener
      listener
    end
  end

  def close from_reader, from_writer
    @io.close rescue nil
    @io = nil
    @reader.ask!(:close) unless from_reader
    @writer.ask!(:close) unless from_writer
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    terminate!
  end

  private

  def listener
    @reader.ask! :listener
  rescue
    nil
  end
end
