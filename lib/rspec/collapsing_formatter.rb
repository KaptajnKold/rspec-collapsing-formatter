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
require "rspec/collapsing_formatter/transport"
require "rspec/collapsing_formatter/runners"
require "rspec/collapsing_formatter/parallel"

module RSpec
  # A documentation-style formatter that collapses finished example groups.
  #
  # Failure, pending and summary output is inherited unchanged from RSpec's
  # BaseTextFormatter. This class only translates RSpec notifications into events and
  # hands them to a Display, which owns the tree and everything about how lines reach
  # the terminal.
  #
  # In a parallel run (see Runners) the events go to a Parallel::Coordinator or
  # Parallel::Worker instead, and RSpec's failure and summary output is held back
  # until they let this process print it.
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    VERSION = "0.2.0"

    Core::Formatters.register self,
                              :start, :message,
                              :example_group_started, :example_group_finished,
                              :example_started, :example_passed, :example_failed, :example_pending,
                              :start_dump

    def initialize(output)
      super
      @failure_count = 0
      @worker = nil
      context = parallel_context
      @sink = context && parallel_role(context)
      if @sink
        @worker = context.worker
        @held_output = output
        @output = StringIO.new(+"") # the inherited dump methods write here until released
      else
        @sink = Display.for(output)
      end
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
      detail = "FAILED - #{@failure_count}"
      detail += ", worker #{@worker}" if @worker # numbered as in this worker's failure list
      example_finished(notification.example, :failed, detail)
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
      return unless @held_output

      @sink.close do
        @held_output.write(output.string)
        @held_output.flush
      end
    end

    private

    # Descriptions are read again on finish: RSpec generates descriptions for
    # examples like `it { is_expected.to be_valid }` only after they have run.
    def example_finished(example, status, detail = nil)
      emit(Events::ExampleFinished, description: example.description.strip, status: status, detail: detail)
    end

    def emit(type, **fields)
      @sink.call(type.new(worker: @worker, **fields))
    end

    # This process's place in a parallel run, if it is one whose progress can be shown
    # live: the display goes to stderr, which runners leave connected to the terminal.
    def parallel_context
      context = Runners.detect(ENV)
      context if context && LiveOutput.supported?(STDERR)
    end

    # The coordinator or worker for this process; nil (so it works on its own) if the
    # coordinator cannot listen, or a worker cannot reach it.
    def parallel_role(context)
      context.coordinator ? Parallel::Coordinator.start(context, STDERR) : Parallel::Worker.start(context)
    end
  end
end
