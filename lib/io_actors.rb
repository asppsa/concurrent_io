require 'concurrent'

module IOActors
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
      require_relative 'io_actors/selector/ffi_libevent'
      FFILibeventSelector.new
    end

    def use_nio4r!
      replace_default_selector!{ new_nio4r_selector }
    end

    def new_nio4r_selector
      require_relative 'io_actors/selector/nio4r'
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
      require_relative 'io_actors/selector/eventmachine'
      EventMachineSelector.new
    end

    private

    def try_nio4r name
      new_nio4r name
    rescue
      nil
    end

    def try_ffi_libevent name
      new_ffi_libevent_selector name
    rescue
      nil
    end

    def try_eventmachine name
      new_eventmachine_selector name
    rescue
      nil
    end
  end
end

require "io_actors/version"
#require "io_actors/controller"
require "io_actors/listener"
require "io_actors/selector/basic"
require "io_actors/selector"
require "io_actors/reader"
require "io_actors/writer"

if ENV['IOACTORS_DEBUG']
  l = Logger.new(STDOUT)
  limit = eval("Logger::#{ENV['IOACTORS_DEBUG']}")
  l.level = limit

  Concurrent.global_logger = lambda do |loglevel, progname, message = nil, &block|
    l.add loglevel, message, progname, &block
  end

  if Kernel.const_defined?(:FFI) && FFI.const_defined?(:Libevent)
    FFI::Libevent.logger = l
  end
end
