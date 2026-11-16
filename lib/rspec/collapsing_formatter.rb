# frozen_string_literal: true

require "rspec/core"
require "rspec/core/formatters/base_text_formatter"
require "rspec/collapsing_formatter/symbols"
require "rspec/collapsing_formatter/tree"
require "rspec/collapsing_formatter/layout"
require "rspec/collapsing_formatter/stream_output"
require "rspec/collapsing_formatter/live_output"

module RSpec
  # A documentation-style formatter that collapses finished example groups.
  #
  # Failure, pending and summary output is inherited unchanged from RSpec's
  # BaseTextFormatter. This class only translates RSpec events into changes to the
  # tree and calls on an output object, which owns everything about how lines reach
  # the terminal.
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    VERSION = "0.1.0"

    Core::Formatters.register self,
                              :example_group_started, :example_group_finished,
                              :example_started, :example_passed, :example_failed, :example_pending,
                              :start_dump

    def initialize(output)
      super
      @tree = Tree.new
      symbols = Symbols.for(output)
      @renderer =
        if LiveOutput.supported?(output)
          LiveOutput.new(output, symbols, @tree)
        else
          StreamOutput.new(output, symbols)
        end
      @failure_count = 0
    end

    def example_group_started(notification)
      group = @tree.group_started(notification.group.description.strip)
      @renderer.group_started(group, @tree.depth - 1)
    end

    def example_group_finished(_notification)
      group = @tree.group_finished
      @renderer.group_finished(group, @tree.depth)
    end

    def example_started(notification)
      example = @tree.example_started(notification.example.description.strip)
      @renderer.example_started(example, @tree.depth)
    end

    def example_passed(notification)
      example_finished(notification.example, :passed)
    end

    def example_failed(notification)
      @failure_count += 1
      example_finished(notification.example, :failed, "FAILED - #{@failure_count}")
    end

    def example_pending(notification)
      example = notification.example
      example_finished(example, :pending, "PENDING: #{example.execution_result.pending_message}")
    end

    # Called before RSpec's failure, pending and summary output, which is then
    # appended below the tree by the inherited dump methods.
    def start_dump(_notification)
      @renderer.finish
    end

    private

    # Descriptions are read again on finish: RSpec generates descriptions for
    # examples like `it { is_expected.to be_valid }` only after they have run.
    def example_finished(example, status, detail = nil)
      node = @tree.example_finished(example.description.strip, status, detail)
      @renderer.example_finished(node, @tree.depth)
    end
  end
end
