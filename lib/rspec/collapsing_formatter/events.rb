# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # The events a Display consumes: what happened in a test run, independent of where
    # it happened. They are plain values, so they can come from the formatter in the
    # same process or, later, from other processes.
    #
    # Every event names the worker it came from. A run in a single process has one
    # worker, nil.
    module Events
      def self.define(*fields)
        Struct.new(*fields, :worker, keyword_init: true)
      end

      # The run started. Sent once per worker.
      Started = define

      GroupStarted = define(:description)
      GroupFinished = define

      ExampleStarted = define(:description)
      # `status` is :passed, :failed or :pending; `detail` e.g. "FAILED - 1". The
      # description is sent again because RSpec may generate it only after the example ran.
      ExampleFinished = define(:description, :status, :detail)

      # A message from RSpec, e.g. "Run options: ...", without a trailing newline.
      Message = define(:text)

      # The worker finished running examples; its failure and summary output follows.
      Finished = define
    end
  end
end
