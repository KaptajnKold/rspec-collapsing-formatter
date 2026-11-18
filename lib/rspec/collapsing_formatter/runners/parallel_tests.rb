# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    module Runners
      # parallel_tests (https://github.com/grosser/parallel_tests) starts one RSpec
      # process per group of spec files and sets, in each:
      #
      # - TEST_ENV_NUMBER: "" or "1" for the first process, then "2", "3", ...
      # - PARALLEL_TEST_GROUPS: the number of processes requested (more may have been
      #   requested than are running, if there were fewer spec files);
      # - PARALLEL_PID_FILE: a file, unique to the run, listing the processes still
      #   running as a JSON array of process ids.
      #
      # The first process is the coordinator. The socket is named after the pid file,
      # so that every process of a run finds it and concurrent runs do not meet.
      module ParallelTests
        def self.detect(env)
          pid_file = env["PARALLEL_PID_FILE"]
          requested = Integer(env.fetch("PARALLEL_TEST_GROUPS", ""), exception: false)
          number = env["TEST_ENV_NUMBER"]
          return unless pid_file && number && requested && requested > 1

          worker = number.empty? ? 1 : Integer(number, exception: false)
          return unless worker&.positive?

          Context.new(
            worker: worker,
            coordinator: worker == 1,
            address: socket_path(pid_file),
            running_processes: -> { running_processes(pid_file) }
          )
        end

        def self.socket_path(pid_file)
          name = "rspec-collapsing-formatter-#{Digest::SHA256.hexdigest(pid_file)[0, 16]}.sock"
          path = File.join(Dir.tmpdir, name)
          path.bytesize < 100 ? path : File.join("/tmp", name) # socket paths are limited to about 104 bytes
        end

        def self.running_processes(pid_file)
          pids = JSON.parse(File.read(pid_file))
          pids.size if pids.is_a?(Array)
        rescue SystemCallError, JSON::ParserError
          nil # missing, or being rewritten
        end
      end
    end
  end
end
