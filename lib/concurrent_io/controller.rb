require 'concurrent/actor'

module ConcurrentIO

  InformMessage = Concurrent::ImmutableStruct.new(:recipient)
  OutputMessage = Concurrent::ImmutableStruct.new(:bytes)

  ReadMessage = Concurrent::ImmutableStruct.new(:bytes)
  WriteMessage = Concurrent::ImmutableStruct.new(:count)
  ErrorMessage = Concurrent::ImmutableStruct.new(:error)

  class Controller < Concurrent::Actor::Context
    def initialize io, selector=nil
      @io = io
      @selector = selector || ConcurrentIO.default_selector
      @selector.add! @io, Translator.new(self.ref)

      @recipient = if parent != Concurrent::Actor.root
                     parent
                   end
    end

    def on_message message
      case message
      when ConcurrentIO::InformMessage
        @recipient = message.recipient

      when ConcurrentIO::OutputMessage
        @selector.write(@io, message.bytes)

      when String
        @selector.write(@io, message)

      when :close
        close!

      when :recipient
        @recipient

      when ConcurrentIO::ReadMessage, ConcurrentIO::WriteMessage
        redirect @recipient if @recipient

      when ConcurrentIO::ErrorMessage
        closed! message

      end
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end

    private

    def close!
      @selector.remove [@io]
    rescue Exception => e
      log(Logger::ERROR, e.to_s)
    ensure
      closed!
    end

    def closed! message = :closed
      @recipient << message if @recipient
    ensure
      terminate!
    end

    class Translator
      include ConcurrentIO::Listener

      def initialize ref
        on_read do |bytes|
          ref << ReadMessage.new(bytes)
        end

        on_write do |count|
          ref << WriteMessage.new(count)
        end

        on_error do |e|
          ref << ErrorMessage.new(e)
        end
      end
    end
  end
end
