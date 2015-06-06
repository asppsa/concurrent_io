class IOActors::Controller < Concurrent::Actor::Context

  def initialize io, selector=nil
    @io = io
    @selector = selector || IOActors.default_selector
    @selector << IOActors::AddMessage.new(@io, ref)

    @listener = if parent != Concurrent::Actor.root
                  parent
                end
  end

  def on_message message
    case message
    when IOActors::InformMessage
      @listener = message.listener

    when IOActors::OutputMessage
      @selector << IOActors::WriteMessage.new(@io, message.bytes)

    when String
      @selector << IOActors::WriteMessage.new(@io, message)

    when :close
      close!

    when :closed
      closed!

    when :listener
      @listener

    when IOActors::InputMessage
      redirect @listener if @listener

    end
  rescue Exception => e
    log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
  end

  private

  def close!
    @selector << IOActors::CloseMessage.new(@io)
  rescue Exception => e
    log(Logger::ERROR, e.to_s)
  ensure
    closed!
  end

  def closed!
    @listener << :closed if @listener
  ensure
    terminate!
  end
end
