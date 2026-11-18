# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Recognizes parallel test runners. This is the only place that lists them, and
    # the only runner-related code the formatter calls.
    #
    # Each adapter detects its runner from the environment, without loading the
    # runner's gem, and describes this process's place in the run as a Context.
    module Runners
      # `worker`: this process's worker id, from 1.
      # `coordinator`: whether this process displays the progress of the whole run.
      # `address`: the Unix socket path through which the run's processes meet.
      # `running_processes`: a callable returning how many of the run's worker
      #   processes are still running, this one included, or nil if unknown.
      Context = Struct.new(:worker, :coordinator, :address, :running_processes, keyword_init: true)

      ADAPTERS = {
        "rspec/collapsing_formatter/runners/parallel_tests" => :ParallelTests
      }.freeze

      # The context of this process if it is a worker in a parallel run, else nil.
      def self.detect(env = ENV)
        ADAPTERS.each do |path, name|
          require path
          context = const_get(name).detect(env)
          return context if context
        end
        nil
      end
    end
  end
end
