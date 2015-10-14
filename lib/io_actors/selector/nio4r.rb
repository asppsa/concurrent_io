require 'nio'

module IOActors 

  class NIO4RSelector
    include BasicSelector
    include Concurrent::Concern::Logging

    def initialize timeout=0.1
      @timeout = timeout or raise "Timeout cannot be nil"
      @selector = NIO::Selector.new

      @listeners = Concurrent::Agent.new({}, error_handler: proc{ |e| log(Logger::ERROR, self.to_s, e.to_s) })
      @registered = Concurrent::Agent.new({}, error_handler: proc{ |e| log(Logger::ERROR, self.to_s, e.to_s) })
      @readers = Concurrent::Agent.new({}, error_handler: proc{ |e| log(Logger::ERROR, self.to_s, e.to_s) })
      @writers = Concurrent::Agent.new({}, error_handler: proc{ |e| log(Logger::ERROR, self.to_s, e.to_s) })

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

      # Used for error reporting
      @listeners.send do |listeners|
        if listeners.key? io
          listeners
        else
          listeners.merge(io => listener)
        end
      end

      # Add to selector
      reregister [io] do |registered|
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

      # Close the IO objects
      ios.each do |io|
        io.close rescue nil
      end

      nil
    rescue => e
      log(Logger::ERROR, self.to_s + '#remove', e.to_s)
      raise e
    end

    def readable registered
      case registered
      when :w,:rw
        :rw
      else
        :r
      end
    end

    def unreadable registered
      case registered
      when :rw, :w
        :w
      else
        nil
      end
    end

    def writable registered
      case registered
      when :w, :rw
        :rw
      else
        :w
      end
    end

    def unwritable registered
      case registered
      when :r, :rw
        :r
      else
        nil
      end
    end
    
    def enable_read io
      reregister [io], &method(:readable)
    end

    def disable_read io
      reregister [io], &method(:unreadable)
    end

    def enable_write io
      reregister [io], &method(:writable)
    end

    def disable_write io
      reregister [io], &method(:unwritable)
    end

    def reregister ios, &block
      return if ios.empty?

      @registered.send do |registered|
        registered.dup.tap do |r|
          to_error = {}

          ios.each do |io|
            # Get the new value
            new_value = block.call(r[io])

            # Deregister any existing registration if the value has
            # changed
            @selector.deregister io if r[io] && new_value != r[io]

            # Register again, if there is a new value
            if new_value
              begin
                @selector.register io, new_value
              rescue IOError => e
                to_error[e] ||= []
                to_error[e].push io
              end
            end

            # Store the value
            r[io] = new_value
          end

          # Trigger errors for failed registrations
          to_error.each do |e, ios|
            trigger_error_and_remove ios, e
          end

          # Wake the selector up
          @selector.wakeup
        end
      end
    rescue => e
      log(Logger::ERROR, self.to_s + "#reregister", e.to_s)
    end

    def run_loop
      loop do
        begin
          if ready = @selector.select(@timeout)
            to_error = []
            to_read = []
            to_write = []

            readers = @readers.deref
            writers = @writers.deref

            ready.each do |m|
              io = m.io

              if io.nil?
                log(Logger::WARN, self.to_s + "#run_loop", "nil IO object")
              elsif io.closed?
                to_error.push io
              else
                if [:r, :rw].member? m.readiness
                  to_read.push io
                end

                if [:w, :rw].member? m.readiness
                  to_write.push io
                end
              end
            end

            # Remove items from the selector
            reregister to_read, &method(:unreadable)
            reregister to_write, &method(:unwritable)

            # Tell readers and writers to go to work
            to_read.map{ |io| readers[io] }.compact.each(&:read!)
            to_write.map{ |io| readers[io] }.compact.each(&:flush!)

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
          await
        end
      end
    end

    def get_writer io
      @writers.deref[io]
    end

    def await
      @readers.await
      @writers.await
      @listeners.await
      @registered.await
    end
  end
end
