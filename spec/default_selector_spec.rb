describe ConcurrentIO do
  describe '.replace_default_selector!' do
    after do
      ConcurrentIO.reset_default_selector!
    end

    it "calls the given block" do
      called = false
      ConcurrentIO.replace_default_selector!{ called = true }
      expect(called).to be true
    end

    it "replaces the value of default_selector" do
      x = {a: 1}
      ConcurrentIO.replace_default_selector!{ x }
      expect(ConcurrentIO.default_selector).to be x
    end
  end

  describe '.default_selector' do
    shared_examples :returns do
      after do
        ConcurrentIO.reset_default_selector!
      end

      it "returns a selector" do
        expect(ConcurrentIO.default_selector).to respond_to :add
        expect(ConcurrentIO.default_selector).to respond_to :add!
        expect(ConcurrentIO.default_selector).to respond_to :remove
        expect(ConcurrentIO.default_selector).to respond_to :write
      end
    end

    context "without any previous call" do
      include_examples :returns
    end

    context "using IO.select" do
      before do
        ConcurrentIO.use_select!
      end

      after do
        ConcurrentIO.reset_default_selector!
      end

      include_examples :returns

      it "returns a Selector" do
        expect(ConcurrentIO.default_selector).to be_a ConcurrentIO::Selector
      end
    end

    context "using FFI::Libevent" do
      before do
        ConcurrentIO.use_ffi_libevent!
      end

      after do
        ConcurrentIO.reset_default_selector!
      end

      include_examples :returns

      it "returns a FFILibeventSelector" do
        expect(ConcurrentIO.default_selector).to be_a ConcurrentIO::FFILibeventSelector
      end
    end

    context "using NIO4R" do
      before do
        ConcurrentIO.use_nio4r!
      end

      after do
        ConcurrentIO.reset_default_selector!
      end
      include_examples :returns

      it "returns a NIO4RSelector" do
        expect(ConcurrentIO.default_selector).to be_a ConcurrentIO::NIO4RSelector
      end
    end

    context "using EventMachine" do
      before do
        ConcurrentIO.use_eventmachine!
      end

      after do
        ConcurrentIO.reset_default_selector!
      end
      include_examples :returns

      it "returns a EventMachineSelector" do
        expect(ConcurrentIO.default_selector).to be_a ConcurrentIO::EventMachineSelector
      end
    end
  end
end
