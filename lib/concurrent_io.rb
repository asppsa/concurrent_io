require 'concurrent'

module ConcurrentIO
  @default_selector = Concurrent::AtomicReference.new(nil)

  class << self
    def default_selector
      @default_selector.value || @default_selector.update do |old_selector|
        old_selector || new_selector
      end
    end

    ##
    # Using a block here ensures that the previous default selector
    # has been stopped before the new one is started
    def replace_default_selector! &block
      @default_selector.update do |old_selector|
        old_selector.stop! if
          old_selector && old_selector.respond_to?(:stop!)

        block.call
      end
    end

    def reset_default_selector!
      replace_default_selector!{ nil }
    end

    def new_selector
      try_ffi_libevent ||
        try_nio4r ||
        try_eventmachine ||
        new_select_selector
    end

    def use_ffi_libevent!
      replace_default_selector!{ new_ffi_libevent_selector }
    end

    def new_ffi_libevent_selector
      require_relative 'concurrent_io/selector/ffi_libevent'
      FFILibeventSelector.new
    end

    def use_nio4r!
      replace_default_selector!{ new_nio4r_selector }
    end

    def new_nio4r_selector
      require_relative 'concurrent_io/selector/nio4r'
      NIO4RSelector.new
    end

    def use_select!
      replace_default_selector!{ new_select_selector }
    end

    def new_select_selector
      Selector.new
    end

    def use_eventmachine!
      replace_default_selector!{ new_eventmachine_selector }
    end

    def new_eventmachine_selector
      require_relative 'concurrent_io/selector/eventmachine'
      EventMachineSelector.new
    end

    private

    def try_nio4r
      new_nio4r
    rescue
      nil
    end

    def try_ffi_libevent
      new_ffi_libevent_selector
    rescue
      nil
    end

    def try_eventmachine
      new_eventmachine_selector
    rescue
      nil
    end
  end
end

require "concurrent_io/version"
require "concurrent_io/listener"
require "concurrent_io/selector/basic"
require "concurrent_io/selector"
require "concurrent_io/reader"
require "concurrent_io/writer"

if ENV['CONCURRENTIO_DEBUG']
  l = Logger.new(STDOUT)
  limit = eval("Logger::#{ENV['CONCURRENTIO_DEBUG']}")
  l.level = limit

  Concurrent.global_logger = lambda do |loglevel, progname, message = nil, &block|
    l.add loglevel, message, progname, &block
  end

  if Kernel.const_defined?(:FFI) && FFI.const_defined?(:Libevent)
    FFI::Libevent.logger = l
  end
end
