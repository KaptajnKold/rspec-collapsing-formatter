# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Number of finished examples by outcome.
    Counts = Struct.new(:passed, :failed, :pending) do
      def self.zero
        new(0, 0, 0)
      end

      def +(other)
        Counts.new(passed + other.passed, failed + other.failed, pending + other.pending)
      end

      def total
        passed + failed + pending
      end
    end

    # An example in the tree. Its status is :running until it finishes as
    # :passed, :failed or :pending; `detail` holds e.g. "FAILED - 1".
    class ExampleNode
      attr_reader :description, :status, :detail

      def initialize(description)
        @description = description
        @status = :running
        @detail = nil
      end

      def finish(status, detail = nil, description: @description)
        @description = description
        @status = status
        @detail = detail
      end

      def finished?
        @status != :running
      end

      def counts
        Counts.new(status == :passed ? 1 : 0, status == :failed ? 1 : 0, status == :pending ? 1 : 0)
      end
    end

    # An example group in the tree, with its child groups and examples in run order.
    class GroupNode
      attr_reader :description, :children

      def initialize(description)
        @description = description
        @children = []
        @finished = false
      end

      def finish
        @finished = true
      end

      def finished?
        @finished
      end

      # Counts of finished examples in this group and all nested groups.
      def counts
        children.map(&:counts).reduce(Counts.zero, :+)
      end

      # :running until finished; then :failed, :pending or :passed by the worst
      # outcome among its examples, or :empty if no examples ran in it.
      def status
        return :running unless finished?

        counts = self.counts
        if counts.total.zero? then :empty
        elsif counts.failed.positive? then :failed
        elsif counts.pending.positive? then :pending
        else :passed
        end
      end
    end

    # The hierarchy of groups and examples seen so far, built from RSpec events.
    #
    # RSpec runs examples one at a time, so the tree tracks the currently open groups
    # as a stack and the currently running example.
    class Tree
      attr_reader :groups

      def initialize
        @groups = []
        @open_groups = []
        @current_example = nil
      end

      # Nesting depth of the innermost open group (0 when no group is open).
      def depth
        @open_groups.size
      end

      def group_started(description)
        group = GroupNode.new(description)
        (@open_groups.last&.children || @groups) << group
        @open_groups.push(group)
        group
      end

      def group_finished
        @open_groups.pop.tap(&:finish)
      end

      def example_started(description)
        @current_example = ExampleNode.new(description)
        @open_groups.last.children << @current_example
        @current_example
      end

      def example_finished(description, status, detail = nil)
        example = @current_example || example_started(description)
        @current_example = nil
        example.finish(status, detail, description: description)
        example
      end
    end
  end
end
