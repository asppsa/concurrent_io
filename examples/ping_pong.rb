#!/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'ffi/libevent'
require 'nio'
require 'io_actors'

require_relative 'ping_ponger.rb'
require 'concurrent/timer_task'

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

  pingers = num.times.map{ |i| PingPonger.new(:pinger, v, i, socket_pairs[i][0]) }
  pongers = num.times.map{ |i| PingPonger.new(:ponger, v, i, socket_pairs[i][1]) }

  pingers.each(&:start!)
end

# Every 2 seconds kill and restart everything
Concurrent::TimerTask.execute(execution_interval: interval, timeout_interval: interval, now: true) do
  puts %{


***********
* KILLING *
***********



}


  while p = pingers.shift
    p.die!
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

    puts %{
PINGS: #{ PingPongStats.pings }
PONGS: #{ PingPongStats.pongs }
}
    puts

    ObjectSpace.each_object(Concurrent::ThreadPoolExecutor) do |exec|
      puts "QUEUE LENGTH: #{exec.queue_length} / #{exec.max_queue}"
      puts "POOL SIZE: #{exec.length}"
    end

    stats = {:failed => 0,
             :alive => 0}

    ObjectSpace.each_object(Concurrent::Agent) do |a|
      k = if a.failed?
            :failed
          else
            :alive
          end

      stats[k] += 1
    end

    puts %{
FAILED AGENTS: #{stats[:failed]}
ALIVE AGENTS: #{stats[:alive]}
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
  rescue => e
    puts e.to_s
  ensure
    sleep 5
  end
end
