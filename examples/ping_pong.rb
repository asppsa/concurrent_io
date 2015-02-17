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

# Every 2 seconds kill and restart everything
Concurrent::TimerTask.execute(execution_interval: 2) do
  while p = pingers.shift
    p << :die
  end

  # The pongers should die by themselves
  #while p = pongers.shift
  #  p << :die
  #end

  launch_pairs.call
end

# Every five seconds check on the number of objects in memory
Concurrent::TimerTask.execute(execution_interval: 5) do
  actors = ObjectSpace.each_object(Concurrent::Actor::Reference).to_a
  terminated = actors.select{ |a| a.ask! :terminated? }
  alive = actors - terminated
  
  controller_actor = proc{ |a| a.context_class == IOActors::ControllerActor }
  reader_actor = proc{ |a| a.context_class == IOActors::ReaderActor }
  writer_actor = proc{ |a| a.context_class == IOActors::WriterActor }
  select_actor = proc{ |a| a.context_class == IOActors::SelectActor }
  ping_pong = proc{ |a| a.context_class == PingPongActor }

  classes = alive.map{ |a| a.context_class }.uniq
  
  puts %{
TOTAL: #{actors.count}
TERMINATED: #{terminated.count}
 - ControllerActor: #{terminated.select(&controller_actor).count}
 - ReaderActor: #{terminated.select(&reader_actor).count}
 - WriterActor: #{terminated.select(&writer_actor).count}
 - SelectActor: #{terminated.select(&select_actor).count}
ALIVE: #{alive.count}
 - ControllerActor: #{alive.select(&controller_actor).count}
 - ReaderActor: #{alive.select(&reader_actor).count}
 - WriterActor: #{alive.select(&writer_actor).count}
 - SelectActor: #{alive.select(&select_actor).count}
 - PingPongActor: #{alive.select(&ping_pong).count}
 - Alive classes: #{classes.map(&:to_s).join(", ")}
}
end

sleep 1 while true
