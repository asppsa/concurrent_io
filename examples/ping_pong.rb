#!/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'ffi/libevent'
require 'nio'
require 'io_actors'
require 'io_actors/selector/nio4r'
require 'io_actors/selector/ffi_libevent'

require_relative 'ping_pong_actor.rb'
require 'concurrent/timer_task'
require 'concurrent/utilities'

# choose a select implementation
#IOActors.use_ffi_libevent!
IOActors.use_nio4r!
#IOActors.use_select!
#IOActors.use_eventmachine!

# create socket pairs
num = 100
interval = 10
socket_pairs = []
pingers = []
pongers = []
v = 0

module PingPongStats
  @pings = Concurrent::AtomicFixnum.new
  @pongs = Concurrent::AtomicFixnum.new

  def self.inc_pings
    @pings.increment
  end

  def self.pings
    @pings.value
  end

  def self.inc_pongs
    @pongs.increment
  end

  def self.pongs
    @pongs.value
  end
end

launch_pairs = proc do
  socket_pairs = num.times.map{ UNIXSocket.pair }

  pingers = num.times.map{ |i| PingPongActor.spawn("pinger_#{v}_#{i}", socket_pairs[i][0]) }
  pongers = num.times.map{ |i| PingPongActor.spawn("ponger_#{v}_#{i}", socket_pairs[i][1]) }

  pingers.map do |pinger|
    pinger << :start
  end
end

# Every 2 seconds kill and restart everything
Concurrent::TimerTask.execute(execution_interval: interval, timeout_interval: interval, now: true) do
  while p = pingers.shift
    p << :die
  end

  # The pongers should die by themselves
  #while p = pongers.shift
  #  p << :die
  #end

  sleep 1

  v += 1
  launch_pairs.call
end

# # Every five seconds check on the number of objects in memory
loop do
  begin
    now = Time.now.to_s
    puts now
    puts("=" * now.length)
    puts

    ObjectSpace.each_object(Concurrent::ThreadPoolExecutor) do |exec|
      puts "QUEUE LENGTH: #{exec.queue_length} / #{exec.max_queue}"
      puts "POOL SIZE: #{exec.length}"
    end

    stats = {:terminated => {},
             :alive => {}}

    ObjectSpace.each_object(Concurrent::Actor::Reference) do |a|
      k = if a.ask!(:terminated?)
            :terminated
          else
            :alive
          end

      cl = if a.actor_class == IOActors::Controller
             :controller
           elsif a.actor_class == IOActors::Reader
             :reader
           elsif a.actor_class == IOActors::Writer
             :writer
           elsif [IOActors::Selector, IOActors::NIO4RSelector, IOActors::FFILibeventSelector].any?{ |c| a.actor_class == c }
             :selector
           elsif a.actor_class == PingPongActor
             :ping_pong_actor
           else
             :other
           end

      stats[k][cl] ||= 0
      stats[k][cl] += 1
    end


    puts %{
PINGS: #{ PingPongStats.pings }
PONGS: #{ PingPongStats.pongs }
}

    puts %{
TOTAL: #{stats.map{ |k,v| v.map{ |k,v| v }.inject(0, :+) }.inject(0, :+)}
TERMINATED: #{ stats[:terminated].map{|k,v| v}.inject(0, :+) }
 - Controller: #{ stats[:terminated][:controller] || 0 }
 - Reader: #{ stats[:terminated][:reader] || 0 }
 - Writer: #{ stats[:terminated][:writer] || 0 }
 - Selector: #{ stats[:terminated][:selector] || 0 }
 - PingPongActor: #{ stats[:terminated][:ping_pong_actor] || 0 }
 - Other:  #{ stats[:terminated][:other] || 0 }
ALIVE: #{ stats[:alive].map{ |k,v| v }.inject(0, :+) }
 - Controller: #{ stats[:alive][:controller] || 0 }
 - Reader: #{ stats[:alive][:reader] || 0 }
 - Writer: #{ stats[:alive][:writer] || 0 }
 - Selector: #{ stats[:alive][:selector] || 0 }
 - PingPongActor: #{ stats[:alive][:ping_pong_actor] || 0 }
 - Other:  #{ stats[:alive][:other] || 0 }
}

    bev_count = 0
    read_enabled = 0
    write_enabled = 0
    ObjectSpace.each_object(FFI::Libevent::BufferEvent) do |bev|
      bev_count += 1
      begin
        read_enabled += 1 if bev.enabled? :read
        write_enabled += 1 if bev.enabled? :write
      rescue ArgumentError
      end
    end

    puts %{
bufferevents: #{bev_count}
read enabled: #{read_enabled}
write enabled: #{write_enabled}
}

    io_count = 0
    io_open = 0
    io_closed = 0
    ObjectSpace.each_object(IO) do |io|
      io_count += 1
      if io.closed?
        io_closed += 1
      else
        io_open += 1
      end
    end

    puts %{
IO: #{io_count}
IO open: #{io_open}
IO closed: #{io_closed}

}
  rescue Exception => e
    puts e.to_s
  ensure
    sleep 5
  end
end
