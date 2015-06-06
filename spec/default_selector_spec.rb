describe 'IOActors.default_selector' do

  after(:each) do
    selector = IOActors.reset_default_selector!
    expect(selector.ask! :terminated?).to be true
  end
  
  shared_examples :returns do
    it "returns an actor" do
      expect(IOActors.default_selector).to be_a Concurrent::Actor::Reference
    end
  end

  context "without any previous call" do
    include_examples :returns
  end

  context "using IO.select" do
    before do
      IOActors.use_select!
    end
    
    include_examples :returns
  
    it "returns a Selector" do
      expect(IOActors.default_selector.actor_class).to be IOActors::Selector
    end    
  end

  context "using FFI::Libevent" do
    before do
      IOActors.use_ffi_libevent!
    end

    include_examples :returns
  
    it "returns a Selector" do
      expect(IOActors.default_selector.actor_class).to be IOActors::FFILibeventSelector
    end
  end

  context "using NIO4R" do
    before do
      IOActors.use_nio4r!
    end

    include_examples :returns
  
    it "returns a Selector" do
      expect(IOActors.default_selector.actor_class).to be IOActors::NIO4RSelector
    end
  end
end
