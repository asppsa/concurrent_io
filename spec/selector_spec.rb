describe 'selectors' do

  shared_examples :selector do
    let(:sockets){ UNIXSocket.pair }
    subject!{ described_class.spawn('my_selector') }

    let(:listener){ Array.new }
    before{ subject << IOActors::AddMessage.new(sockets[0], listener) }

    after(:each){ subject.ask! :stop rescue nil }

    it "passes InputMessage objects to listeners" do
      sockets[1].send("test", 0)
      sleep 0.2
      expect(listener.length).to eq 1
      expect(listener.first).to be_a IOActors::InputMessage
      expect(listener.first.bytes).to eq 'test'
    end

    it "doesn't pass any InputMessages unless there is something there" do
      # Check that we're not immediately inundated with :read messages
      sleep 0.2
      expect(listener.length).to eq 0

      # Now do the write and then clear after we expect it to have
      # been added
      sockets[1].send("test", 0)
      sleep 0.2
      listener.clear

      # Check again that no more read messages are written subsequently
      sleep 0.2
      expect(listener.length).to eq 0
    end

    it "doesn't pass :read once a listener is removed" do
      # Do a write and read with a lag in-between
      sockets[1].send("test", 0)
      sleep 0.2
      expect(listener.length).to be > 0
      listener.clear

      subject << IOActors::RemoveMessage.new(sockets[0])
      sleep 0.2

      # Now send another message and make sure that nothing happens as a
      # result
      sockets[1].send("test", 0)
      sleep 0.2
      expect(listener.length).to eq 0
    end

    it "passes :closed if a socket gets closed" do
      # Close the socket and check to see that no :closed message
      # appears
      sockets[1].close
      sleep 0.5
      expect(listener.length).to eq 1
      expect(listener.first).to eq :closed
    end

    it "can process a large number of bytes" do
      # Create lots of bytes.
      bytes = SecureRandom.random_bytes(1_000_000)
      hash = Digest::SHA1.hexdigest bytes

      # Tell the selector to listen on this one too.
      listener2 = []
      subject << IOActors::AddMessage.new(sockets[1], listener2)

      # Write to socket[1]
      subject << IOActors::WriteMessage.new(sockets[1], bytes)

      # Wait a while
      start = Time.now
      sleep 0.5 while Time.now - start < 10 and
        listener.
        map(&:bytes).
        map(&:bytesize).
        inject(0, :+) < 1_000_000

      # Expect that we've received the bytes
      expect(listener.length).to be > 0
      received = listener.map(&:bytes).join
      expect(Digest::SHA1.hexdigest(received)).to eq hash

      # Remove socket[1]
      subject.ask! IOActors::RemoveMessage.new(sockets[1])
    end
  end

  describe IOActors::Selector do
    include_examples :selector
  end

  require 'io_actors/selector/ffi_libevent'
  describe IOActors::FFILibeventSelector do
    include_examples :selector
  end

  require 'io_actors/selector/nio4r'
  describe IOActors::NIO4RSelector do
    include_examples :selector
  end
end
