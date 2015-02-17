#!/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'io_actors'
require_relative 'ping_pong_actor.rb'
require 'concurrent/timer_task'
require 'concurrent/utilities'

# create socket pairs
num = 10
socket_pairs = []
pingers = []
pongers = []

launch_pairs = proc do
  socket_pairs = num.times.map{ UNIXSocket.pair }

  pingers = num.times.map{ |i| PingPongActor.spawn("pinger_#{i}", socket_pairs[i][0]) }
  pongers = num.times.map{ |i| PingPongActor.spawn("ponger_#{i}", socket_pairs[i][1]) }

  pingers.map do |pinger|
    pinger << :start
  end
end

# Every second kill and restart everything
Concurrent::TimerTask.execute(execution_interval: 1) do
  while p = pingers.shift
    p << :die
  end

  launch_pairs.call
end

# Every five seconds check on the number of objects in memory
Concurrent::TimerTask.execute(execution_interval: 5) do
  actors = ObjectSpace.each_object(Concurrent::Actor::Reference).to_a
  total = actors.count
  terminated = actors.select{ |a| a.ask! :terminated? }.count
  alive = total - terminated
  puts "TOTAL: #{total}\nTERMINATED: #{terminated}\nALIVE: #{alive}"
end

sleep 1 while true
