require 'securerandom'
require 'digest/sha1'

describe ConcurrentIO::Writer do

  let(:sockets){ UNIXSocket.pair }
  let(:selector){ spy("selector") }
  let(:listener){ spy("listener") }

  subject{ described_class.new(selector, sockets[0], listener) }

  after do
    subject.clear!
  end

  it "can write bytes" do
    subject.append "test1"
    expect(sockets[1].recv(5)).to eq("test1")

    subject.append "test2"
    expect(sockets[1].recv(5)).to eq("test2")
  end

  it "can write large numbers of bytes" do
    bytes = SecureRandom.random_bytes(1_000_000)
    hash = Digest::SHA1.hexdigest bytes
    subject.append bytes

    input = ""
    while input.bytesize < 1_000_000
      subject.flush!
      input << sockets[1].recv(1_000_000 - input.bytesize)
    end

    expect(Digest::SHA1.hexdigest(input)).to eq(hash)
    expect(listener).to have_received(:trigger_write).
                         with(kind_of(Integer)).
                         at_least(:once)
  end
end
