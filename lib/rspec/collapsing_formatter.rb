# frozen_string_literal: true

require "rspec/core"
require "rspec/core/formatters/base_text_formatter"
require "rspec/collapsing_formatter/stream_output"

module RSpec
  # A documentation-style formatter that collapses finished example groups.
  #
  # Failure, pending and summary output is inherited unchanged from RSpec's
  # BaseTextFormatter. This class only translates RSpec events into calls on an
  # output object, which owns everything about how lines reach the terminal.
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    VERSION = "0.1.0"

    Core::Formatters.register self,
                              :example_group_started, :example_group_finished,
                              :example_passed, :example_failed, :example_pending

    def initialize(output)
      super
      @renderer = StreamOutput.new(output)
      @depth = 0
      @failure_count = 0
    end

    def example_group_started(notification)
      @renderer.group_started(notification.group.description.strip, @depth)
      @depth += 1
    end

    def example_group_finished(_notification)
      @depth -= 1
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

    private

    def example_finished(example, status, detail = nil)
      @renderer.example_finished(example.description.strip, @depth, status, detail)
    end
  end
end
