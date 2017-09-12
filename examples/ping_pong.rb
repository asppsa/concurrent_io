#!/bin/env ruby

cur, max = Process.getrlimit(Process::RLIMIT_NOFILE)

if cur < max
  puts "Rlimit is less than max: #{cur} < #{max}; increasing to max"
  Process.setrlimit(Process::RLIMIT_NOFILE, max)
end

if max < 2000
  puts "Rlimit is very low: #{max}"
end

require 'rubygems'
require 'bundler/setup'
require 'concurrent_io'
require 'socket'

require_relative 'ping_ponger.rb'
require 'concurrent/timer_task'

case ARGV[0]
when 'ffi-libevent'
  require 'ffi/libevent'
  puts 'Using FFI-Libevent'
  ConcurrentIO.use_ffi_libevent!
when 'nio4r'
  require 'nio'
  puts 'Using NIO4R'
  ConcurrentIO.use_nio4r!
when 'eventmachine'
  puts 'Using EventMachine'
  require 'eventmachine'
  ConcurrentIO.use_eventmachine!
else
  puts 'Using IO::select'
  ConcurrentIO.use_select!
end

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

port = 9000
server = TCPServer.new 'localhost', port
launch_pairs = proc do
  puts "* LAUNCHING ROUND #{v} *"

  socket_pairs = num.times.map do
    client = TCPSocket.new('localhost', port)
    peer = server.accept
    [client, peer]
  end

  pingers = num.times.map{ |i| PingPonger.new(:pinger, v, i, socket_pairs[i][0]) }
  pongers = num.times.map{ |i| PingPonger.new(:ponger, v, i, socket_pairs[i][1]) }

  pingers.each(&:start!)
end

# Initial start of the pairs
launch_pairs.call

# Every <interval> seconds, kill and restart everything
Concurrent::TimerTask.execute(execution_interval: interval, timeout_interval: interval) do
  puts "* KILLING #{pingers.length} PINGERS ... *"

  # The pongers should die by themselves
  while pinger = pingers.shift
    pinger.die!
  end

  sleep 1

  v += 1
  begin
    launch_pairs.call
  rescue => e
    p e
  end
end

# Every five seconds check on the number of objects in memory
start_time = Time.now
loop do
  begin
    now = Time.now.to_s
    puts now
    puts("=" * now.length)
    puts

    seconds = Time.now - start_time
    puts %{
PINGS: #{ PingPongStats.pings } (#{PingPongStats.pings / seconds}/s)
PONGS: #{ PingPongStats.pongs } (#{PingPongStats.pongs / seconds}/s)
}
    puts

    puts %{
DEFAULT SELECTOR LENGTH: #{ConcurrentIO.default_selector.length}
}

  rescue => e
    puts e.to_s
  ensure
    sleep 5
  end
end