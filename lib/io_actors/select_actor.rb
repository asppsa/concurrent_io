module IOActors

  if Module.const_defined?('FFI') &&
     FFI.const_defined?('Libevent')
    require_relative 'select_actor/ffi_libevent'
    class SelectActor < FFILibeventSelectActor; end
  elsif Module.const_defined?('NIO')
    require_relative 'select_actor/nio4r'
    class SelectActor < NIO4RSelectActor; end
  else
    require_relative 'select_actor/fallback'
    class SelectActor < FallbackSelectActor; end
  end

end
