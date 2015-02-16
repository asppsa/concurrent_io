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
    subject << IOActors::OutputMessage.new("test1")
    expect(sockets[1].recv(5)).to eq("test1")

    subject << "test2"
    expect(sockets[1].recv(5)).to eq("test2")
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

  it "terminates if its reader receives :close" do
    reader = subject.ask!(:reader)
    reader.ask!(:close)
    expect(reader.ask! :terminated?).to be_truthy
    expect(subject.ask! :terminated?).to be_truthy
  end

  it "terminates if its writer receives :close" do
    writer = subject.ask!(:writer)
    writer.ask!(:close)
    expect(writer.ask! :terminated?).to be_truthy
    expect(subject.ask! :terminated?).to be_truthy
  end

  it "does not terminate when the IO object is closed" do
    reader = subject.ask!(:reader)
    writer = subject.ask!(:writer)

    sockets[0].close
    sleep 0.5

    expect(subject.ask! :terminated?).to be_falsy
    expect(reader.ask! :terminated?).to be_falsy
    expect(writer.ask! :terminated?).to be_falsy
  end

  it "terminates on write if the IO object is closed" do
    reader = subject.ask!(:reader)
    writer = subject.ask!(:writer)

    sockets[0].close
    subject << "testing 1 2 3"
    sleep 0.5

    expect(subject.ask! :terminated?).to be_truthy
    expect(reader.ask! :terminated?).to be_truthy
    expect(writer.ask! :terminated?).to be_truthy
  end

  it "terminates on read if the IO object is closed" do
    reader = subject.ask!(:reader)
    writer = subject.ask!(:writer)

    sockets[0].close
    subject << :read
    sleep 0.5

    expect(subject.ask! :terminated?).to be_truthy
    expect(reader.ask! :terminated?).to be_truthy
    expect(writer.ask! :terminated?).to be_truthy
  end

  it "terminates on select if the IO object is already closed" do
    sockets[1].close
    subject.ask! IOActors::SelectMessage.new(IOActors.selector)
    sleep 0.5
    expect(subject.ask! :terminated?).to be_truthy
  end

  it "terminates if the IO object is closed during a select" do
    # First check that the select loop is working
    listener = []
    subject << IOActors::InformMessage.new(listener)
    subject.ask! IOActors::SelectMessage.new(IOActors.selector)
    sockets[1] << "test"
    true while listener.empty?
    expect(listener.map{ |i| i.bytes }.join).to eq("test")

    # Now close the IO object and wait a moment
    sockets[1].close
    sleep 1
    expect(subject.ask! :terminated?).to be_truthy
  end

end
