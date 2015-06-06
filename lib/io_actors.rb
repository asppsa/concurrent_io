require 'concurrent'

module IOActors
  InputMessage = Struct.new(:bytes)
  OutputMessage = Struct.new(:bytes)
  WriteMessage = Struct.new(:io, :bytes)
  AddMessage = Struct.new(:io, :actor)
  RemoveMessage = Struct.new(:io)
  CloseMessage = Struct.new(:io)
  InformMessage = Struct.new(:listener)
  EnableReadMessage = Struct.new(:io)
  EnableWriteMessage = Struct.new(:io)

  @default_selector_name = 'default_selector'
  @default_selector = Concurrent::IVar.new

  class << self

    ##
    # This is not thread-safe, and in general shouldn't be used.  It
    # exists to make testing of various selectors easier
    def reset_default_selector!
      selector = nil
      if @default_selector.fulfilled?
        selector = @default_selector.value
        selector.ask! :stop
      end
      @default_selector = Concurrent::IVar.new
      selector
    end

    def default_selector
      # Only attempt to set when it looks unfulfilled.
      unless @default_selector.fulfilled?
        begin
          @default_selector.
            set spawn_selector(@default_selector_name)
        rescue Concurrent::MultipleAssignmentError
        end
      end

      @default_selector.value
    end

    def default_selector= selector
      @default_selector.set selector
    end

    def spawn_selector name
      try_ffi_libevent(name) ||
        try_nio4r(name) ||
        spawn_select_selector(name)
    end

    def use_ffi_libevent!
      self.default_selector = spawn_ffi_libevent_selector(@default_selector_name)
    end

    def spawn_ffi_libevent_selector name
      require_relative 'io_actors/selector/ffi_libevent'
      FFILibeventSelector.spawn(name)
    end

    def use_nio4r!
      self.default_selector = spawn_nio4r_selector(@default_selector_name)
    end

    def spawn_nio4r_selector name
      require_relative 'io_actors/selector/nio4r'
      NIO4RSelector.spawn(name)
    end

    def use_select!
      self.default_selector = spawn_select_selector(@default_selector_name)
    end

    def spawn_select_selector name
      Selector.spawn(name)
    end

    private

    def try_nio4r name
      spawn_nio4r name
    rescue
      nil
    end

    def try_ffi_libevent name
      spawn_ffi_libevent_selector name
    rescue
      nil
    end
  end
end

require "io_actors/version"
require "io_actors/controller"
require "io_actors/selector"
require "io_actors/reader"
require "io_actors/writer"

if ENV['IOACTORS_DEBUG']
  l = Logger.new(STDOUT)
  limit = eval("Logger::#{ENV['IOACTORS_DEBUG']}")
  l.level = limit

  Concurrent.configure do |c|
    c.logger = l.method(:add)
  end

  if Kernel.const_defined? 'FFI::Libevent'
    FFI::Libevent.logger = l
  end
end
