describe ConcurrentIO::Reader do

  let(:sockets){ UNIXSocket.pair }
  let(:listener) { spy("listener") }
  let(:selector) { spy("selector") }

  subject{ described_class.new(selector, sockets[0], listener) }

  after do
    sockets[0].close
    subject.read!.value
  end

  it "can read bytes" do
    expect(listener).to receive(:trigger_read).with("test")

    sockets[1].send("test", 0)
    subject.read!
    sleep 1
  end

  it "can read a large number of bytes" do
    bytes = SecureRandom.random_bytes(1_000_000)
    hash = Digest::SHA1.hexdigest bytes

    input = ""
    expect(listener).to receive(:trigger_read) do |bytes|
      input << bytes
      if input.bytesize == 1_000_000
        expect(Digest::SHA1.hexdigest input).to eq hash
      end
    end.at_most(1_000_000).times
    
    writer = ConcurrentIO::Writer.new(selector, sockets[1], listener)
    writer.append bytes

    times = 0
    while input.bytesize < 1_000_000 && times < 100
      writer.flush!
      times += 1
    end

    writer.clear!
  end
end
  
