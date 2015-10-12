require 'nio'

module IOActors 

  class NIO4RSelector
    include BasicSelector
    include Concurrent::Concern::Logging

    def initialize timeout=0.1
      @timeout = timeout or raise "Timeout cannot be nil"
      @selector = NIO::Selector.new

      @listeners = Concurrent::Agent.new({}, :error_mode => :continue)
      @registered = Concurrent::Agent.new({}, :error_mode => :continue)
      @readers = Concurrent::Agent.new({}, :error_mode => :continue)
      @writers = Concurrent::Agent.new({}, :error_mode => :continue)

      run!
    end

    def add io, listener
      @readers.send do |readers|
        if readers.key? io
          readers
        else
          readers.merge(io => Reader.new(self, io, listener))
        end
      end

      @writers.send do |writers|
        if writers.key? io
          writers
        else
          writers.merge(io => Writer.new(self, io, listener))
        end
      end

      @listeners.send do |listeners|
        if listeners.key? io
          listeners
        else
          listeners.merge(io => listener)
        end
      end

      reregister io do |registered|
        registered || :r
      end
    rescue => e
      log(Logger::ERROR, self.to_s + '#add', e.to_s)
      trigger_error_and_remove [io], e
    ensure
      return nil
    end

    def remove ios
      # Eliminate from all agents
      [@readers, @writers, @listeners, @registered].each do |agent|
        agent.send do |state|
          hash_without_keys(state, ios)
        end
      end

      # Remove from selector
      ios.each(&@selector.method(:deregister))

      nil
    rescue => e
      log(Logger::ERROR, self.to_s + '#remove', e.to_s)
      raise e
    end

    def enable_read io
      reregister io do |registered|
        case registered
        when :w,:rw
          :rw
        else
          :r
        end
      end
    end

    def disable_read io
      reregister io do |registered|
        case registered
        when :rw, :w
          :w
        else
          nil
        end
      end
    end

    def enable_write io
      reregister io do |registered|
        case registered
        when :w, :rw
          :rw
        else
          :w
        end
      end
    end

    def disable_write io
      reregister io do |registered|
        case registered
        when :r, :rw
          :r
        else
          nil
        end
      end
    end

    def reregister io, &block
      @registered.send do |registered|
        # Deregister any existing registration
        @selector.deregister io if registered[io]
        
        # Register again, if instructed to
        if new_value = block.call(registered[io])
          begin
            @selector.register io, new_value
          rescue IOError => e
            trigger_error_and_remove [io], e
          end
        end

        # Store the new value
        registered.merge(io => new_value)
      end
    rescue => e
      log(Logger::ERROR, self.to_s + "#reregister", e.to_s)
    end

    def run_loop
      loop do
        begin
          if ready = @selector.select(@timeout)
            to_error = []

            readers = @readers.deref
            writers = @writers.deref

            ready.each do |m|
              io = m.io

              if io.nil?
                log(Logger::WARN, self.to_s + "#run_loop", "nil IO object")
              elsif io.closed?
                to_error.push m
              else
                if [:r, :rw].member? m.readiness
                  disable_read io
                  if reader = readers[io]
                    reader.read!
                  end
                end

                if [:w, :rw].member? m.readiness
                  disable_write io
                  if writer = writers[io]
                    writer.flush!
                  end
                end
              end
            end

            # Trigger errors for all errored states and remove from
            # the selector
            trigger_error_and_remove to_error
          end
        rescue IOError => e
          # Remove closed fds
          all = @listeners.deref.keys
          trigger_error_and_remove all.select(&:closed?), e
        ensure
          # Wait for the agents to finish what they are doing before
          # continuing
          @readers.await
          @writers.await
          @listeners.await
          @registered.await
        end
      end
    end

    def get_writer io
      @writers.deref[io]
    end
  end
end
