require 'securerandom'
require 'digest/sha1'

describe IOActors::WriterActor do

  let(:sockets){ UNIXSocket.pair }
  
  subject{ described_class.spawn('my_writer', sockets[0]) }
  after(:each) { subject.ask!(:close) rescue nil }

  it "can write bytes" do
    subject << IOActors::OutputMessage.new("test1")
    expect(sockets[1].recv(5)).to eq("test1")

    subject << "test2"
    expect(sockets[1].recv(5)).to eq("test2")
  end

  it "can write large numbers of bytes" do
    bytes = SecureRandom.random_bytes(1_000_000)
    hash = Digest::SHA1.hexdigest bytes
    subject << bytes

    input = ""
    while input.bytesize < 1_000_000
      input << sockets[1].recv(1_000_000 - input.bytesize)
    end
    
    expect(Digest::SHA1.hexdigest(input)).to eq(hash)
  end

  it "closes its IO object on termination" do
    subject.ask! :close
    expect(subject.ask!(:terminated?)).to be_truthy
    expect(sockets[0].closed?).to be_truthy
  end
end
