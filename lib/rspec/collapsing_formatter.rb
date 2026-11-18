# frozen_string_literal: true

require "rspec/core"
require "rspec/core/formatters/base_text_formatter"
require "rspec/collapsing_formatter/symbols"
require "rspec/collapsing_formatter/tree"
require "rspec/collapsing_formatter/layout"
require "rspec/collapsing_formatter/stream_output"
require "rspec/collapsing_formatter/stray_output"
require "rspec/collapsing_formatter/live_output"
require "rspec/collapsing_formatter/events"
require "rspec/collapsing_formatter/display"

module RSpec
  # A documentation-style formatter that collapses finished example groups.
  #
  # Failure, pending and summary output is inherited unchanged from RSpec's
  # BaseTextFormatter. This class only translates RSpec notifications into events and
  # hands them to a Display, which owns the tree and everything about how lines reach
  # the terminal.
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    VERSION = "0.1.0"

    Core::Formatters.register self,
                              :start, :message,
                              :example_group_started, :example_group_finished,
                              :example_started, :example_passed, :example_failed, :example_pending,
                              :start_dump

    def initialize(output)
      super
      @display = Display.for(output)
      @failure_count = 0
    end

    def start(notification)
      super
      emit(Events::Started)
    end

    # RSpec messages (e.g. "Run options: ...") are printed above the live region.
    def message(notification)
      emit(Events::Message, text: notification.message)
    end

    def example_group_started(notification)
      emit(Events::GroupStarted, description: notification.group.description.strip)
    end

    def example_group_finished(_notification)
      emit(Events::GroupFinished)
    end

    def example_started(notification)
      emit(Events::ExampleStarted, description: notification.example.description.strip)
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
      emit(Events::Finished)
    end

    # Also finishes the output when the run ends without reaching start_dump.
    # Finishing twice is harmless.
    def close(notification)
      emit(Events::Finished)
      super
    end

    private

    # Descriptions are read again on finish: RSpec generates descriptions for
    # examples like `it { is_expected.to be_valid }` only after they have run.
    def example_finished(example, status, detail = nil)
      emit(Events::ExampleFinished, description: example.description.strip, status: status, detail: detail)
    end

    def emit(type, **fields)
      @display.call(type.new(**fields))
    end
  end
end
