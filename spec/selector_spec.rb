describe 'selectors' do

  shared_examples :selector do
    subject{ described_class.new }

    let(:sockets){ UNIXSocket.pair }

    let(:listener_class) do
      Class.new do
        attr_reader :read, :error

        def initialize
          @read = []
          @error = nil
        end

        def trigger_read s
          @read << s
        end

        # Do nothing
        def trigger_write c; end

        def trigger_error e
          @error = e
        end

        def all_read
          @read.join
        end
      end
    end

    let(:listener){ listener_class.new }
    before{ subject.add! sockets[0], listener }

    after(:example){ subject.stop! rescue nil }

    it "passes strings to listeners' trigger_read methods" do
      sockets[1].send("test", 0)

      # Wait a while
      start = Time.now
      sleep 0.2 while Time.now - start < 10 and
        listener.read.length < 1

      expect(listener.read.length).to be >= 1
      expect(listener.read).to all( be_a String )
      expect(listener.all_read).to eq 'test'
    end

    it "doesn't trigger a read unless something is read" do
      # Check that we're not immediately inundated with :read messages
      sleep 0.2
      expect(listener.read.length).to eq 0

      # Now do the write and then clear after we expect it to have
      # been added
      sockets[1].send("test", 0)
      sleep 0.2
      listener.read.clear

      # Check again that no more read messages are written subsequently
      sleep 0.2
      expect(listener.read.length).to eq 0
    end

    it "closes the IO when then listener is removed" do
      # Do a write and read with a lag in-between
      sockets[1].send("test", 0)
      sleep 0.2
      expect(listener.read.length).to be > 0
      listener.read.clear

      subject.remove! [sockets[0]]

      # Ensure that the IO has been closed at OS-level (possibly not
      # at ruby level)
      expect(sockets[0].closed?).to be true
    end

    it "triggers an error if a socket gets closed" do
      # Close the socket and check to see that no :closed message
      # appears
      sockets[1].close
      sleep 0.5
      expect(listener.error).not_to be_nil
    end

    it "can process a large number of bytes" do
      # Create lots of bytes.
      bytes = SecureRandom.random_bytes(1_000_000)
      hash = Digest::SHA1.hexdigest bytes

      # Tell the selector to listen on this one too.
      listener2 = listener_class.new
      subject.add! sockets[1], listener2

      # Write to socket[1]
      subject.write sockets[1], bytes

      # Wait a while
      start = Time.now
      sleep 0.5 while Time.now - start < 10 and
        listener.read.
        map(&:bytesize).
        inject(0, :+) < 1_000_000

      # Expect that we've received the bytes
      expect(listener.read.length).to be > 0
      received = listener.all_read
      expect(Digest::SHA1.hexdigest(received)).to eq hash

      # Remove socket[1]
      subject.remove! [sockets[1]]
    end
  end

  describe ConcurrentIO::Selector do
    include_examples :selector
  end

  require 'concurrent_io/selector/ffi_libevent'
  describe ConcurrentIO::FFILibeventSelector do
    include_examples :selector
  end

  require 'concurrent_io/selector/nio4r'
  describe ConcurrentIO::NIO4RSelector do
    include_examples :selector
  end

  require 'concurrent_io/selector/eventmachine'
  describe ConcurrentIO::EventMachineSelector do
    include_examples :selector
  end
end
