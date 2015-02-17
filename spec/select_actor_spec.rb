describe IOActors::SelectActor do

  let(:sockets){ UNIXSocket.pair }
  subject{ described_class.spawn('my_selector') }

  after(:each) { subject.ask! :stop }

  it "passes :read messages to listeners" do
    arr = []
    subject << IOActors::RegisterMessage.new(sockets[0], arr)
    sockets[1].send("test", 0)
    sleep 0.5
    sockets[0].recv(4)
    expect(arr.length).to be > 0
    expect(arr).to all( eq :read )
  end

  it "doesn't pass :read unless there is something there" do
    arr = []
    subject << IOActors::RegisterMessage.new(sockets[0], arr)

    # Check that we're not immediately inundated with :read messages
    sleep 0.5
    expect(arr.length).to eq 0

    # Now do the write and read with a lag in-between
    sockets[1].send("test", 0)
    sleep 0.5
    sockets[0].recv(4)
    sleep 0.5
    arr.clear

    # Check again that no more read messages are written subsequently
    sleep 0.5
    expect(arr.length).to eq 0
  end
  
  it "doesn't pass :read once a listener is deregistered" do
    arr = []
    subject << IOActors::RegisterMessage.new(sockets[0], arr)

    # Do a write and read with a lag in-between
    sockets[1].send("test", 0)
    sleep 0.5
    sockets[0].recv(4)
    expect(arr.length).to be > 0
    arr.clear

    subject << IOActors::DeregisterMessage.new(sockets[0])
    sleep 0.5

    # Now send another message and make sure that nothing happens as a
    # result
    sockets[1].send("test", 0)
    sleep 0.5
    expect(arr.length).to eq 0
  end

  it "passes :read if a socket gets closed" do
    arr = []
    subject << IOActors::RegisterMessage.new(sockets[0], arr)

    # Do a write and read with a lag in-between
    sockets[1].send("test", 0)
    sleep 0.5
    sockets[0].recv(10)
    expect(arr.length).to be > 0

    # Wait a moment to ensure that no more :read messages are coming
    # through
    sleep 0.5
    arr.clear
    sleep 0.5
    expect(arr).to be_empty

    # Close the socket and check to see that the :read messages resume
    sockets[1].close
    sleep 0.5
    expect(arr.length).to be > 0
    expect(arr).to all( eq :read )
  end

end
