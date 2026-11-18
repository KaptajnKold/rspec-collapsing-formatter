# frozen_string_literal: true

require "monitor"

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Applies events to the tree and tells the output what changed.
    #
    # Knows nothing about RSpec notifications or where events come from; the formatter
    # translates notifications into events, possibly in other processes. Knows nothing
    # about terminals either; that is the output's job.
    #
    # Events may arrive from several threads; they are applied one at a time.
    class Display
      # A display for `io`: live redrawing if it is a terminal, append-only otherwise.
      # In parallel mode, every worker's running group is shown at once.
      def self.for(io, parallel: false)
        tree = Tree.new
        symbols = Symbols.for(io)
        output =
          if LiveOutput.supported?(io)
            LiveOutput.new(io, symbols, tree, parallel: parallel)
          else
            StreamOutput.new(io, symbols)
          end
        new(tree, output, parallel: parallel)
      end

      attr_reader :tree

      # In parallel mode a worker's Finished event only ends its pending output; the
      # display as a whole is finished by calling #finish once every worker is done.
      def initialize(tree, output, parallel: false)
        @tree = tree
        @output = output
        @parallel = parallel
        @partial = Hash.new { |partial, worker| partial[worker] = +"" } # Output not yet ending in a newline
        @lock = Monitor.new
      end

      def call(event)
        @lock.synchronize { apply(event) }
      end

      # Completes the output: prints pending partial lines and the final tree.
      def finish
        @lock.synchronize do
          @partial.each_key { |worker| end_output(worker) }
          @output.finish
        end
      end

      private

      def apply(event)
        worker = event.worker
        case event
        when Events::Started
          @output.start
        when Events::GroupStarted
          group = @tree.group_started(event.description, worker: worker)
          @output.group_started(group, @tree.depth(worker) - 1)
        when Events::GroupFinished
          group = @tree.group_finished(worker: worker)
          @output.group_finished(group, @tree.depth(worker))
        when Events::ExampleStarted
          example = @tree.example_started(event.description, worker: worker)
          @output.example_started(example, @tree.depth(worker))
        when Events::ExampleFinished
          example = @tree.example_finished(event.description, event.status, event.detail, worker: worker)
          @output.example_finished(example, @tree.depth(worker))
        when Events::Message
          @output.message(event.text)
        when Events::Output
          output(worker, event.text)
        when Events::Finished
          @parallel ? end_output(worker) : finish
        else
          raise ArgumentError, "unknown event #{event.inspect}"
        end
      end

      # Prints the worker's complete lines; the rest waits for its newline.
      def output(worker, text)
        buffer = @partial[worker] << text
        newline = buffer.rindex("\n")
        @output.message(buffer.slice!(0..newline).chomp) if newline
      end

      # Prints the worker's partial line, if any, as a line of its own.
      def end_output(worker)
        buffer = @partial[worker]
        @output.message(buffer.dup) unless buffer.empty?
        buffer.clear
      end
    end
  end
end
