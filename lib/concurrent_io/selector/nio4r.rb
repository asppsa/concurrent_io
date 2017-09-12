require 'nio'

module ConcurrentIO

  class NIO4RSelector < Selector
    def initialize timeout=0.1
      @nio = Concurrent::Agent.new(NIO::Selector.new, error_handler: proc{ |a,e| log(Logger::ERROR, a.to_s, e.to_s) })
      super
    end

    def add io, listener
      super
      @nio.send do |selector|
        selector.register(io, :rw)
        selector
      end
    end

    def remove ios
      @nio.send(ios.dup) do |selector, ios|
        ios.each &selector.method(:deregister)
        selector
      end
      super
    end

    def run_loop
      loop do
        begin
          read_active = @readers.deref.active
          write_active = @writers.deref.active

          to_error = []
          to_read = []
          to_write = []

          readers = @readers.deref.receivers
          writers = @writers.deref.receivers

          @nio.deref.select(@timeout) do |m|
            io = m.io

            if io.nil?
              log(Logger::WARN, self.to_s + "#run_loop", "nil IO object")
            elsif io.closed?
              to_error.push io
            else
              if m.readable? && read_active.member?(io)
                to_read.push io
              end

              if m.writable? && write_active.member?(io)
                to_write.push io
              end
            end
          end

          # Shortcut
          return if [to_error, to_read, to_write].all?(&:empty?)

          # These are async operations
          set_inactive @readers, to_read
          set_inactive @writers, to_write

          # Tell readers and writers to go to work
          to_read.map{ |io| readers[io] }.compact.each(&:read!)
          to_write.map{ |io| writers[io] }.compact.each(&:flush!)

          # Trigger errors for all errored states and remove from
          # the selector
          trigger_error_and_remove to_error
        rescue IOError => e
          # Remove closed fds
          all = @listeners.deref.keys
          trigger_error_and_remove all.select(&:closed?), e
        ensure
          # Wait for the agents to finish what they are doing before
          # continuing
          await

          # Stop if we've been stopped
          break if @stopped.fulfilled?
        end
      end

      def await
        super
        @nio.await
      end
    end
  end
end
