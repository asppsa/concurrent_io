describe IOActors::ReaderActor do

  let(:sockets){ UNIXSocket.pair(:STREAM) }

  subject{ described_class.spawn('my_reader', sockets[0]) }
  after(:each) { subject.ask!(:close) rescue nil }

  it "can read bytes" do
    listener = []
    subject.ask! IOActors::InformMessage.new(listener)
    sockets[1].send("test", 0)
    subject << :read

    sleep 1

    listener.each{ |i| expect(i).to be_a(IOActors::InputMessage) }
    expect(listener.map{ |i| i.bytes }.join).to eq("test")
  end

  it "can read a large number of bytes" do
    listener = []
    subject.ask! IOActors::InformMessage.new(listener)

    bytes = SecureRandom.random_bytes(1_000_000)
    hash = Digest::SHA1.hexdigest bytes

    writer = IOActors::WriterActor.spawn('my_writer', sockets[1])
    writer << IOActors::OutputMessage.new(bytes)
      
    input = ""
    while input.bytesize < 1_000_000
      subject << :read
      sleep 0.1
      input = listener.map{ |i| i.bytes }.join
    end

    writer << :close

    expect(Digest::SHA1.hexdigest input).to eq(hash)
  end
end
  
