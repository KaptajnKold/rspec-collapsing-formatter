# frozen_string_literal: true

require "open3"

RSpec.describe "Running rspec with the collapsing formatter" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:fixture) { File.join(root, "spec", "fixtures", "sample_suite.rb") }

  # Runs RSpec in a child process with its output captured through a pipe (not a TTY).
  # `--format RSpec::CollapsingFormatter` without `--require` checks that RSpec can
  # autoload the formatter from its constant name.
  def run_rspec(*args)
    command = [
      Gem.ruby, "-I", File.join(root, "lib"),
      "-e", "require 'rspec/core'; exit RSpec::Core::Runner.run(ARGV)", "--",
      fixture, "--format", "RSpec::CollapsingFormatter", *args
    ]
    Open3.capture2e({ "SPEC_OPTS" => nil }, *command, chdir: File.join(root, "spec", "fixtures"))
  end

  it "prints the hierarchy, failure details and summary without escape sequences" do
    output, status = run_rspec

    expect(status.exitstatus).to eq(1)
    expect(output).not_to include("\e")
    expect(output).to include(<<~TEXT)
      User
        when active
          ✓ is valid
          ✓ can log in
        when suspended
          ✓ is invalid
          ✗ cannot log in (FAILED - 1)
          • sends a notice (PENDING: Not yet implemented)
    TEXT
    expect(output).to include("1) User when suspended cannot log in")
    expect(output).to include("5 examples, 1 failure, 1 pending")
  end
end
