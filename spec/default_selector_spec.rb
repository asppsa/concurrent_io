describe IOActors do
  describe '.replace_default_selector!' do
    after do
      IOActors.reset_default_selector!
    end

    it "calls the given block" do
      called = false
      IOActors.replace_default_selector!{ called = true }
      expect(called).to be true
    end

    it "replaces the value of default_selector" do
      x = {a: 1}
      IOActors.replace_default_selector!{ x }
      expect(IOActors.default_selector).to be x
    end
  end

  describe '.default_selector' do
    shared_examples :returns do
      after do
        IOActors.reset_default_selector!
      end

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

      after do
        IOActors.reset_default_selector!
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

      after do
        IOActors.reset_default_selector!
      end

      include_examples :returns

      it "returns a FFILibeventSelector" do
        expect(IOActors.default_selector.actor_class).to be IOActors::FFILibeventSelector
      end
    end

    context "using NIO4R" do
      before do
        IOActors.use_nio4r!
      end

      after do
        IOActors.reset_default_selector!
      end
      include_examples :returns

      it "returns a NIO4RSelector" do
        expect(IOActors.default_selector.actor_class).to be IOActors::NIO4RSelector
      end
    end
  end
end
