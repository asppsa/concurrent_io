describe IOActors::Reader do

  let(:sockets){ UNIXSocket.pair }
  let(:listener) { [] }

  subject{ described_class.spawn('my_reader', sockets[0], listener) }
  after(:each) { subject.ask!(:stop) rescue nil }

  it "can read bytes" do
    sockets[1].send("test", 0)
    subject << :read

    sleep 1

    expect(listener.length).to be > 0
    expect(listener).to all( be_a(IOActors::InputMessage) )
    expect(listener.map(&:bytes).join).to eq("test")
  end

  it "can read a large number of bytes" do
    bytes = SecureRandom.random_bytes(1_000_000)
    hash = Digest::SHA1.hexdigest bytes

    writer = IOActors::Writer.spawn('my_writer', sockets[1])
    writer << IOActors::OutputMessage.new(bytes)
      
    input = ""
    while input.bytesize < 1_000_000
      writer << :write
      subject << :read
      sleep 0.1
      input = listener.map{ |i| i.bytes }.join
    end

    writer << :close

    expect(Digest::SHA1.hexdigest input).to eq(hash)
  end

  it "terminates on :stop" do
    subject.ask! :stop
    expect(subject.ask!(:terminated?)).to be_truthy
    expect(sockets[0].closed?).to be_falsey
  end
end
  
