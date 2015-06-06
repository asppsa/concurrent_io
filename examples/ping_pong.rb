#!/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'ffi/libevent'
require 'nio'
require 'io_actors'
require_relative 'ping_pong_actor.rb'
require 'concurrent/timer_task'
require 'concurrent/utilities'

# choose a select implementation
IOActors.use_ffi_libevent!
#IOActors.use_nio4r!
#IOActors.use_select!

# create socket pairs
num = 10
interval = 10
socket_pairs = []
pingers = []
pongers = []
v = 0

launch_pairs = proc do
  socket_pairs = num.times.map{ UNIXSocket.pair }

  pingers = num.times.map{ |i| PingPongActor.spawn("pinger_#{v}_#{i}", socket_pairs[i][0]) }
  pongers = num.times.map{ |i| PingPongActor.spawn("ponger_#{v}_#{i}", socket_pairs[i][1]) }

  pingers.map do |pinger|
    pinger << :start
  end
end

# Every 2 seconds kill and restart everything
Concurrent::TimerTask.execute(execution_interval: interval, timeout_interval: interval) do
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

# # # Every five seconds check on the number of objects in memory
# Concurrent::TimerTask.execute(execution_interval: 5, timeout_interval: 5) do
#   stats = {:terminated => {},
#            :alive => {}}

#   ObjectSpace.garbage_collect
#   actors = ObjectSpace.each_object(Concurrent::Actor::Reference) do |a|
#     k = if a.ask!(:terminated?)
#           :terminated
#         else
#           :alive
#         end

#     cl = if a.context_class == IOActors::ControllerActor
#            :controller_actor
#          elsif a.context_class == IOActors::ReaderActor
#            :reader_actor
#          elsif a.context_class == IOActors::WriterActor
#            :writer_actor
#          elsif a.context_class == IOActors::SelectActor
#            :select_actor
#          elsif a.context_class == PingPongActor
#            :ping_pong_actor
#          end

#     stats[k][cl] ||= 0
#     stats[k][cl] += 1
#   end

#   puts %{
# TOTAL: #{stats.map{ |k,v| v.map{ |k,v| v }.inject(0, :+) }.inject(0, :+)}
# TERMINATED: #{ stats[:terminated].map{|k,v| v}.inject(0, :+) }
#  - ControllerActor: #{ stats[:terminated][:controller_actor] }
#  - ReaderActor: #{ stats[:terminated][:reader_actor] }
#  - WriterActor: #{ stats[:terminated][:writer_actor] }
#  - SelectActor: #{ stats[:terminated][:select_actor] }
#  - PingPongActor: #{ stats[:terminated][:ping_pong_actor] }
# ALIVE: #{ stats[:alive].map{ |k,v| v }.inject(0, :+) }
#  - ControllerActor: #{ stats[:alive][:controller_actor] }
#  - ReaderActor: #{ stats[:alive][:reader_actor] }
#  - WriterActor: #{ stats[:alive][:writer_actor] }
#  - SelectActor: #{ stats[:alive][:select_actor] }
#  - PingPongActor: #{ stats[:alive][:ping_pong_actor] }
# }
# end

sleep 1 while true
