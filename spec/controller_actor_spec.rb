require 'socket'

describe IOActors::ControllerActor do

  let(:sockets){ Socket.pair(:UNIX, :STREAM, 0) }
  
  subject{ described_class.spawn('my_controller', sockets[0]) }
  after(:each) { subject.ask!(:close) rescue nil }

  it "can return its reader" do
    expect(subject.ask!(:reader)).to be_a(Concurrent::Actor::Reference)
    expect(subject.ask!(:reader).parent).to eq(subject)
  end

  it "can return its writer" do
    expect(subject.ask!(:writer)).to be_a(Concurrent::Actor::Reference)
    expect(subject.ask!(:writer).parent).to eq(subject)
  end

  it "can write bytes" do
    subject << IOActors::OutputMessage.new("test")
    expect(sockets[1].recv(4)).to eq("test")
  end

  it "closes its IO object and kills its children on termination" do
    subject.ask! :close
    expect(subject.ask!(:terminated?)).to be_truthy
    expect(sockets[0].closed?).to be_truthy
  end

  it "can wire up a select actor" do
    selector = []
    subject.ask! IOActors::SelectMessage.new(selector)
    expect(selector.first).to be_a(IOActors::RegisterMessage)
    expect(selector.first.io).to eq(sockets[0])
    expect(selector.first.actor).to eq(subject.ask!(:reader))
  end

  it "can wire up a read-listener" do
    listener = []
    subject.ask! IOActors::InformMessage.new(listener)
    sockets[1].send("test", 0)
    subject << :read

    # freezes
    true while listener.empty?

    listener.each{ |i| expect(i).to be_a(IOActors::InputMessage) }
    expect(listener.map{ |i| i.bytes }.join).to eq("test")
  end

end
