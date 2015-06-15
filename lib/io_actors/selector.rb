module IOActors
  class Selector < Concurrent::Actor::Context

    def initialize timeout=0.1
      @timeout = timeout or raise "timeout cannot be nil"
      @read_active = []
      @read_inactive = []
      @readers = {}

      @write_active = []
      @write_inactive = []
      @writers = {}

      @actors = {}

      @all = []

      tick
    end

    def on_message message
      case message
      when :tick #, :reset!, :restart!
        tick

      when IOActors::AddMessage
        add message.io, message.actor

      when IOActors::RemoveMessage
        remove message.io

      when IOActors::CloseMessage
        close message.io

      when IOActors::WriteMessage
        write message.io, message.bytes

      when IOActors::EnableReadMessage
        enable_read message.io

      when IOActors::EnableWriteMessage
        enable_write message.io

      when :stop
        terminate!

      end
    end

    private

    def tick
      log(Logger::WARN, "TICK -- reading: #{@read_active.length}; writing: #{@write_active.length}; all: #{@all.length}")

      if ready = IO.select(@read_active, @write_active, @all, @timeout)
        to_read, to_write, to_error = ready

        disable_read to_read
        to_read.each{ |io| @readers[io] << :read }

        disable_write to_write
        to_write.each{ |io| @writers[io] << :write }

        to_error.each(&method(:close))
      end
    rescue IOError
      # Remove closed fds & tick
      @all.select(&:closed?).each(&method(:close))
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    ensure
      ref << :tick
    end

    def enable_read io
      # Don't add if it's been removed/killed already
      return unless @actors.key?(io)

      case io
      when Array
        @read_inactive -= io
        @read_active += io
      else
        @read_inactive.delete io
        @read_active.push io
      end
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end

    def disable_read io
      case io
      when Array
        @read_active -= io
        @read_inactive += io
      else
        @read_active.delete io
        @read_inactive.push io
      end
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end

    def enable_write io
      # Don't add if it's been removed/killed already
      return unless @actors.key?(io)

      case io
      when Array
        @write_inactive -= io
        @write_active += io
      else
        @write_inactive.delete io
        @write_active.push io
      end
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end

    def disable_write io
      case io
      when Array
        @write_active -= io
        @write_inactive += io
      else
        @write_active.delete io
        @write_inactive.push io
      end
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end

    def add io, actor
      raise "already added" if @all.member?(io)

      @readers[io] = IOActors::Reader.spawn('reader', io, actor)
      @writers[io] = IOActors::Writer.spawn('writer', io)
      @actors[io] = actor

      enable_read io
      disable_write io

      @all.push io
      true
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end

    def remove io
      if reader = @readers.delete(io)
        reader << :stop
      end

      if writer = @writers.delete(io)
        writer << :stop
      end

      @read_active.delete io
      @read_inactive.delete io
      @write_active.delete io
      @write_inactive.delete io
      @all.delete io

      # Return the actor
      @actors.delete(io)
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end

    def close io
      if actor = remove(io) and envelope.sender != actor
        actor << :closed
      end
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    ensure
      io.close rescue nil
    end

    def write io, bytes
      if writer = @writers[io]
        writer << bytes
      end
    rescue Exception => e
      log(Logger::ERROR, "#{e.to_s}\n#{e.backtrace}")
    end
  end
end
