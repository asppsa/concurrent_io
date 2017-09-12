module ConcurrentIO
  module BasicSelector
    def run
      raise "No executor" unless @executor
      Concurrent::Promise.
        new(:executor => @executor, &method(:run_loop)).
        catch do |e|
          if RUBY_ENGINE == 'jruby' && java.lang.Exception === e
            log(Logger::ERROR, self.to_s + '#run!', e.inspect)
          else
            log(Logger::ERROR, self.to_s + '#run!', e)
          end
        end.
        flat_map{ run unless @stopped.fulfilled? }
    end

    def run!
      @executor = Concurrent::SingleThreadExecutor.new
      @stopped = Concurrent::IVar.new
      run.execute
    end

    def stop!
      @stopped.try_set true
    end

    def running?
      @stopped.pending?
    end

    def trigger_error_and_remove ios, e=IOError
      return if ios.empty?

      # Get the list of listeners
      listeners = @listeners.deref

      # Remove io objects from selector
      remove ios

      # Trigger error messages
      ios.each do |io|
        if listeners.key? io
          listeners[io].trigger_error e
        end
      end
    end

    def hash_without_keys hash, keys
      hash.dup.tap do |h|
        keys.each(&h.method(:delete))
      end
    end

    def write io, bytes
      if writer = get_writer(io)
        writer.append bytes
      else
        # Try again after the agent has processed pending requests,
        # with timeout to prevent deadlock
        @writers.wait(1)
        if writer = get_writer(io)
          writer.append bytes
        else
          raise "Failed to acquire writer for #{io}"
        end
      end

      nil
    end

    def length
      @listeners.deref.length
    end

    def remove! ios
      remove ios
      await
      nil
    end

    def add! io, listener
      add io, listener
      await
      nil
    end
  end
end
