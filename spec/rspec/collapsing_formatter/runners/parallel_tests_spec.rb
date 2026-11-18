# frozen_string_literal: true

require "tempfile"
require "rspec/collapsing_formatter/runners/parallel_tests" # loaded on demand by the registry

RSpec.describe RSpec::CollapsingFormatter::Runners::ParallelTests do
  let(:pid_file) { Tempfile.new("parallel_tests-pidfile") }
  let(:env) { { "PARALLEL_PID_FILE" => pid_file.path, "PARALLEL_TEST_GROUPS" => "4", "TEST_ENV_NUMBER" => "" } }

  after { pid_file.close! }

  it "makes the first process, numbered \"\" or \"1\", worker 1 and the coordinator" do
    ["", "1"].each do |number|
      context = described_class.detect(env.merge("TEST_ENV_NUMBER" => number))

      expect([context.worker, context.coordinator]).to eq([1, true])
    end
  end

  it "makes the other processes workers" do
    context = described_class.detect(env.merge("TEST_ENV_NUMBER" => "3"))

    expect([context.worker, context.coordinator]).to eq([3, false])
  end

  it "gives every process of a run the same socket, and other runs another" do
    other_run = Tempfile.new("parallel_tests-pidfile")
    addresses = ["", "2"].map { |number| described_class.detect(env.merge("TEST_ENV_NUMBER" => number)).address }

    expect(addresses.uniq.size).to eq(1)
    expect(addresses.first.bytesize).to be < 104
    expect(described_class.detect(env.merge("PARALLEL_PID_FILE" => other_run.path)).address).not_to eq(addresses.first)
  ensure
    other_run.close!
  end

  it "counts the processes still running from the pid file" do
    running = described_class.detect(env).running_processes
    File.write(pid_file.path, "[101,102,103]")

    expect(running.call).to eq(3)
    File.write(pid_file.path, "")

    expect(running.call).to be_nil
    pid_file.unlink

    expect(running.call).to be_nil
  end

  {
    "outside parallel_tests" => {},
    "when a single process was requested" => { "PARALLEL_TEST_GROUPS" => "1" },
    "without a pid file" => { "PARALLEL_PID_FILE" => nil },
    "with a non-numeric process number" => { "TEST_ENV_NUMBER" => "a" },
    "without a process number" => { "TEST_ENV_NUMBER" => nil }
  }.each do |situation, changes|
    it "detects nothing #{situation}" do
      environment = changes.empty? ? {} : env.merge(changes).compact

      expect(described_class.detect(environment)).to be_nil
    end
  end

  it "is found by the registry" do
    expect(RSpec::CollapsingFormatter::Runners.detect(env)&.worker).to eq(1)
    expect(RSpec::CollapsingFormatter::Runners.detect({})).to be_nil
  end
end
