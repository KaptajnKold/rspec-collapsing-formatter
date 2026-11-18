# frozen_string_literal: true

require "json"
require "socket"

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Carries events from worker processes to the process that displays them, over a
    # Unix socket, as one JSON object per line. Knows nothing about any particular
    # test runner.
    #
    # A worker connects, says which worker it is and sends its events. When it has
    # finished it waits to be released: the server sends "go", the worker prints its
    # failure and summary output, then disconnects. That keeps each worker's output in
    # one piece, after the display is complete.
    module Transport
      RELEASE = "go"

      def self.encode(event)
        "#{JSON.generate({ "type" => event.class.name.split("::").last, **event.to_h.transform_keys(&:to_s) })}\n"
      end

      # The event in `line`, or nil if it isn't one.
      def self.decode(line)
        fields = JSON.parse(line)
        type = fields.delete("type")
        return unless fields.is_a?(Hash) && Events.constants.include?(type&.to_sym)

        event_class = Events.const_get(type)
        fields = fields.slice(*event_class.members.map(&:to_s)).transform_keys(&:to_sym)
        fields[:status] = fields[:status].to_sym if fields[:status].is_a?(String)
        event_class.new(**fields)
      rescue JSON::ParserError, TypeError
        nil
      end

      # Accepts workers' connections and hands their events to the block, from one
      # thread per connection: `block.call(worker, event)`, and `block.call(worker, nil)`
      # when the worker disconnects.
      class Server
        def initialize(path, &on_event)
          File.delete(path) if File.socket?(path) # left over from a run that crashed
          @path = path
          @server = UNIXServer.new(path)
          @on_event = on_event
          @connections = {}
          @lock = Mutex.new
          @acceptor = Thread.new { accept_connections }
        end

        # Tells the worker it may print its output. False if it isn't connected.
        def release(worker)
          socket = @lock.synchronize { @connections[worker] }
          return false unless socket

          socket.write("#{RELEASE}\n")
          true
        rescue IOError, SystemCallError
          false
        end

        # Stops accepting workers and disconnects those still connected, which stops
        # them waiting to be released.
        def close
          @server.close
          @acceptor.join(1)
          @lock.synchronize { @connections.values }.each { |socket| socket.close unless socket.closed? }
          File.delete(@path) if File.socket?(@path)
        rescue IOError, SystemCallError
          nil
        end

        private

        def accept_connections
          loop do
            socket = @server.accept
            Thread.new { serve(socket) }
          end
        rescue IOError, SystemCallError
          nil # closed
        end

        def serve(socket)
          worker = JSON.parse(socket.gets || "{}")["worker"]
          return socket.close unless worker

          @lock.synchronize { @connections[worker] = socket }
          while (line = socket.gets)
            event = Transport.decode(line)
            @on_event.call(worker, event) if event
          end
        rescue IOError, SystemCallError, JSON::ParserError
          nil
        ensure
          if worker
            @lock.synchronize { @connections.delete(worker) }
            @on_event.call(worker, nil)
          end
          socket.close unless socket.closed?
        end
      end

      # A worker's connection to the server.
      class Client
        # Connects, retrying until `timeout` seconds have passed (the server's process
        # may start later). Nil if it never succeeds.
        def self.connect(path, worker:, timeout:)
          deadline = monotonic_now + timeout
          begin
            socket = UNIXSocket.new(path)
          rescue Errno::ENOENT, Errno::ECONNREFUSED
            return nil if monotonic_now > deadline

            sleep 0.05
            retry
          end
          socket.write("#{JSON.generate({ "worker" => worker })}\n")
          new(socket)
        rescue IOError, SystemCallError
          nil
        end

        def self.monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def initialize(socket)
          @socket = socket
          @lock = Mutex.new
          @deferred = [] # events sent from signal handlers, which cannot take the lock
          @connected = true
        end

        def connected?
          @connected
        end

        def send_event(event)
          line = Transport.encode(event)
          @lock.synchronize do
            write(@deferred.shift) until @deferred.empty?
            write(line)
          end
        rescue ThreadError => e
          raise unless e.message.include?("trap context")

          @deferred << line # Array#<< needs no lock; sent with the next event
        end

        # Blocks until the server releases this worker, or goes away.
        def wait_for_release
          @lock.synchronize { write(@deferred.shift) until @deferred.empty? }
          while (line = @socket.gets)
            return if line.chomp == RELEASE
          end
        rescue IOError, SystemCallError
          nil
        end

        def close
          @connected = false
          @socket.close unless @socket.closed?
        end

        private

        def write(line)
          @socket.write(line) if @connected
        rescue IOError, SystemCallError
          @connected = false # the server is gone; carry on without it
        end
      end
    end
  end
end
