# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Applies events to the tree and tells the output what changed.
    #
    # Knows nothing about RSpec notifications or where events come from; the formatter
    # translates notifications into events. Knows nothing about terminals either; that
    # is the output's job.
    class Display
      # A display for `io`: live redrawing if it is a terminal, append-only otherwise.
      def self.for(io)
        tree = Tree.new
        symbols = Symbols.for(io)
        output = LiveOutput.supported?(io) ? LiveOutput.new(io, symbols, tree) : StreamOutput.new(io, symbols)
        new(tree, output)
      end

      attr_reader :tree

      def initialize(tree, output)
        @tree = tree
        @output = output
      end

      def call(event)
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
        when Events::Finished
          @output.finish
        else
          raise ArgumentError, "unknown event #{event.inspect}"
        end
      end
    end
  end
end
