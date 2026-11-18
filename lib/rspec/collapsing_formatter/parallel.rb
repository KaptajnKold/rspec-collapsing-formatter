# frozen_string_literal: true

require "monitor"

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # The two roles of a process in a parallel run, whatever the runner: one
    # Coordinator displays the progress of every worker, and the other processes are
    # Workers that send it their events. Both use the Runners::Context an adapter
    # provides, and the Transport.
    #
    # Neither writes to the process's stdout during the run, since runners such as
    # parallel_tests relay it to the terminal whenever it arrives. Output from specs is
    # sent to the coordinator, and RSpec's failure and summary output is held back
    # until the display is complete; then each process prints it in turn.
    module Parallel
      # How long a worker keeps trying to reach the coordinator, which may still be
      # starting, before it falls back to working on its own.
      CONNECT_TIMEOUT = 30

      # The notice RSpec prints on stderr when it is interrupted. Ctrl-C interrupts
      # every process, so each would print it.
      INTERRUPT_NOTICE = /\A\n?RSpec is shutting down/

      # Replaces $stdout and/or $stderr by StrayOutput proxies for the duration of the
      # run, handing what is written to them to #stray_output.
      module StreamCapture
        private

        def capture_streams(stdout: true, stderr: true)
          @captured = []
          if stdout
            @captured << [:stdout, $stdout]
            $stdout = StrayOutput.new($stdout, self)
          end
          if stderr
            @captured << [:stderr, $stderr]
            $stderr = StrayOutput.new($stderr, self)
          end
        end

        # Restores the streams, unless something else has replaced them since.
        def release_streams
          (@captured || []).each do |name, original|
            current = name == :stdout ? $stdout : $stderr
            next unless current.is_a?(StrayOutput) && current.io.equal?(original)

            name == :stdout ? $stdout = original : $stderr = original
          end
          @captured = []
        end

        def text_of(data)
          data.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        end
      end

      # A process that sends its events to the coordinator.
      class Worker
        include StreamCapture

        # The worker, or nil if the coordinator cannot be reached.
        def self.start(context, timeout: CONNECT_TIMEOUT)
          client = Transport::Client.connect(context.address, worker: context.worker, timeout: timeout)
          client && new(client, context.worker)
        end

        def initialize(client, worker)
          @client = client
          @worker = worker
        end

        def call(event)
          capture_streams if event.is_a?(Events::Started) # stderr too: it is the terminal
          release_streams if event.is_a?(Events::Finished)
          @client.send_event(event)
        end

        # Called by StrayOutput.
        def stray_output(_proxy, data)
          @client.send_event(Events::Output.new(text: text_of(data), worker: @worker))
        end

        # Waits until the coordinator lets this worker print its failure and summary
        # output, which the block does.
        def close
          release_streams
          @client.wait_for_release
          yield
        ensure
          @client.close
        end
      end

      # The process that displays the progress of every worker, its own included.
      class Coordinator
        include StreamCapture

        # The coordinator, or nil if it cannot listen for workers.
        def self.start(context, io, connect_timeout: CONNECT_TIMEOUT)
          new(context, io, connect_timeout: connect_timeout)
        rescue IOError, SystemCallError
          nil
        end

        def initialize(context, io, connect_timeout:)
          @context = context
          @worker = context.worker
          @display = Display.for(io, parallel: true)
          @states = {} # worker => :running, :finished or :gone (disconnected)
          @lock = Monitor.new
          @changed = @lock.new_cond
          @deferred = [] # own output written from signal handlers, which cannot take locks
          @interrupt_notice_shown = false
          # Workers that have not connected by then have given up and work on their own.
          @newcomer_deadline = now + connect_timeout + 1
          @server = Transport::Server.new(context.address) { |worker, event| received(worker, event) }
        end

        # An event of this process.
        def call(event)
          # Only stdout: stderr is the display's terminal, which the live output captures.
          capture_streams(stderr: false) if event.is_a?(Events::Started)
          flush_deferred
          @display.call(event)
        end

        # Called by StrayOutput for this process's stdout.
        def stray_output(_proxy, data)
          event = Events::Output.new(text: text_of(data), worker: @worker)
          begin
            flush_deferred
            @display.call(event)
          rescue ThreadError => e
            raise unless e.message.include?("trap context")

            @deferred << event # Array#<< needs no lock
          end
        end

        # Waits for every worker, completes the display, then lets this process (the
        # block) and each worker in turn print its failure and summary output.
        def close
          release_streams
          flush_deferred
          wait_for_workers
          @display.finish
          yield
          release_workers
        ensure
          @server.close
        end

        private

        def received(worker, event)
          @lock.synchronize do
            @states[worker] =
              if event.nil? then :gone
              elsif event.is_a?(Events::Finished) then :finished
              else @states[worker] || :running
              end
            @changed.broadcast
          end
          return unless event && show?(event)

          event.worker = worker # trust the connection, not the message
          @display.call(event)
        end

        # Shows RSpec's interrupt notice only once: not at all if this process was
        # interrupted too, since it prints its own.
        def show?(event)
          return true unless event.is_a?(Events::Output) && event.text.match?(INTERRUPT_NOTICE)

          @lock.synchronize do
            shown = @interrupt_notice_shown || RSpec.world.wants_to_quit
            @interrupt_notice_shown = true
            !shown
          end
        end

        def wait_for_workers
          @lock.synchronize { @changed.wait(0.1) until workers_done? }
        end

        # Every connected worker has finished, and no other worker process is running,
        # or none can still connect.
        def workers_done?
          return false if @states.value?(:running)

          running = @context.running_processes&.call
          return true if running.nil? || now > @newcomer_deadline

          running - 1 - @states.count { |_worker, state| state != :gone } <= 0
        end

        def release_workers
          @states.keys.sort.each do |worker|
            next unless @states[worker] == :finished && @server.release(worker)

            @lock.synchronize { @changed.wait(0.1) until @states[worker] == :gone }
          end
        end

        def flush_deferred
          @display.call(@deferred.shift) until @deferred.empty?
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
