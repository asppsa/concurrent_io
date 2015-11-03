require 'socket'
require 'io_actors/controller'

describe IOActors::Controller do
  let(:sockets){ UNIXSocket.pair }

  shared_examples :controller do
    subject!{ described_class.spawn('my_controller', sockets[0], selector) }

    after(:each) do
      subject.ask!(:close) rescue nil
      selector.stop!
    end

    it "can read bytes" do
      @read = false
      c = Class.new(Concurrent::Actor::Context) do
        def on_message message
          case message
          when IOActors::ReadMessage
            @read = message.bytes == 'test'
          when :read
            @read
          end
        end
      end
      actor = c.spawn 'test'
      subject.ask! IOActors::InformMessage.new(actor)
      sockets[1] << 'test'
      sleep 0.5
      expect(actor.ask! :read).to be true
    end

    it "can write bytes" do
      subject << IOActors::OutputMessage.new("test1")
      expect(sockets[1].recv(5)).to eq("test1")

      subject << "test2"
      expect(sockets[1].recv(5)).to eq("test2")
    end

    it "closes its IO object and kills its children on termination" do
      expect(subject.ask!(:terminated?)).to be_falsey
      subject.ask! :close
      sleep 0.2
      expect(subject.ask!(:terminated?)).to be_truthy
      expect(sockets[0].closed?).to be_truthy
    end

    it "terminates when the socket is closed at the other end" do
      sockets[1].close
      sleep 0.5
      expect(subject.ask! :terminated?).to be_truthy
    end
  end

  context "using basic selector" do
    let(:selector) { IOActors::Selector.new }
    include_examples :controller
  end

  context "using ffi-libevent selector" do
    before(:context) do
      require 'io_actors/selector/ffi_libevent'
    end

    let(:selector) { IOActors::FFILibeventSelector.new }
    include_examples :controller
  end

  context "using nio4r selector" do
    before(:context) do
      require 'io_actors/selector/nio4r'
    end

    let(:selector) { IOActors::NIO4RSelector.new }
    include_examples :controller
  end

  context "using eventmachine selector" do
    before(:context) do
      require 'io_actors/selector/eventmachine'
    end

    let(:selector) { IOActors::EventMachineSelector.new }
    include_examples :controller
  end
end
