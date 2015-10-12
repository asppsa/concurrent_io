require 'set'

module IOActors
  class SelectorState < Concurrent::ImmutableStruct.new(:active, :inactive, :receivers)

    def initialize active=Set.new, inactive=Set.new, receivers={}
      super active, inactive, receivers
    end

    class << self
      def agent
        state = self.new
        Concurrent::Agent.new(state, :error_mode => :continue)
      end
    end
  end

  class Selector
    include Concurrent::Concern::Logging
    include BasicSelector

    def initialize timeout=0.1
      @timeout = timeout or raise "timeout cannot be nil"

      @readers = SelectorState.agent
      @writers = SelectorState.agent
      @listeners = Concurrent::Agent.new({}, :error_mode => :continue)

      run!
    end

    def enable_read io
      set_active @readers, [io]
    end

    def disable_read io
      set_inactive @readers, [io]
    end

    def enable_write io
      set_active @writers, [io]
    end

    def disable_write io
      set_inactive @writers, [io]
    end

    def add io, listener
      @readers.send do |state|
        if state.receivers.key? io
          state
        else
          SelectorState.new(state.active + [io],
                            state.inactive,
                            state.receivers.merge(io => Reader.new(self, io, listener)))
        end
      end

      @writers.send do |state|
        if state.receivers.key? io
          state
        else
          SelectorState.new(state.active,
                            state.inactive + [io],
                            state.receivers.merge(io => Writer.new(self, io, listener)))
        end
      end

      @listeners.send do |listeners|
        if listeners.key? io
          listeners
        else
          listeners.merge(io => listener)
        end
      end
    rescue => e
      trigger_error_and_remove [io], e
    ensure
      return nil
    end

    def remove ios
      remove_from_state @readers, ios
      remove_from_state @writers, ios

      @listeners.send do |listeners|
        hash_without_keys(listeners, ios)
      end

      nil
    rescue => e
      log(Logger::ERROR, self.to_s + "#remove", e.to_s)
      raise e
    end

    def run_loop
      loop do
        begin
          # Dereference current state
          read_active = @readers.deref.active.to_a
          write_active = @writers.deref.active.to_a
          all = @listeners.deref.keys

          if ready = IO.select(read_active,
                               write_active,
                               all, @timeout)

            # Get the IO objects that are ready for something
            to_read, to_write, to_error = ready

            # Get current readers and writers
            readers = @readers.deref.receivers
            writers = @writers.deref.receivers

            # These are async operations
            set_inactive @readers, to_read
            set_inactive @writers, to_write

            # Tell readers to read, writers to write
            to_read.map{ |io| readers[io] }.compact.each(&:read!)
            to_write.map{ |io| writers[io] }.compact.each(&:flush!)

            # Trigger errors for all errored states and remove from
            # the selector
            trigger_error_and_remove to_error
          end
        rescue IOError => e
          # Remove closed fds
          trigger_error_and_remove all.select(&:closed?), e
        ensure
          # Wait for the agents to finish what they are doing before
          # continuing
          @readers.await
          @writers.await
          @listeners.await
        end
      end
    end

    ##
    # Take a list of IO objects to make inactive
    def set_inactive state, ios
      return if ios.empty?
      
      state.send do |state|
        # Update state with new object
        SelectorState.new(state.active - ios,
                          state.inactive + (ios & state.receivers.keys),
                          state.receivers)
      end
    rescue => e
      log(Logger::ERROR, self.to_s + "#set_inactive", e.to_s)
      raise e
    end

    ##
    # Take a list of IO objects to make active
    def set_active state, ios
      return if ios.empty?

      state.send do |state|
        # Replace the state with new object
        SelectorState.new(state.active + (ios & state.receivers.keys),
                          state.inactive - ios,
                          state.receivers)
      end
    rescue => e
      log(Logger::ERROR, self.to_s + "#set_inactive", e.to_s)
      raise e
    end

    ##
    # Take a list of IO objects to remove from selector
    def remove_from_state state, ios
      return if ios.empty?

      state.send do |state|
        SelectorState.new(state.active - ios,
                          state.inactive - ios,
                          hash_without_keys(state.receivers, ios))
      end
    rescue => e
      log(Logger::ERROR, self.to_s + '#remove_from_state', e.to_s)
    end

    def get_writer io
      @writers.deref.receivers[io]
    end
  end
end
