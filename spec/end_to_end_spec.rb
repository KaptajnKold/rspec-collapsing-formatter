# frozen_string_literal: true

require "open3"
require "pty"
require "io/console"

RSpec.describe "Running rspec with the collapsing formatter" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:fixture) { File.join(root, "spec", "fixtures", "sample_suite.rb") }

  # Runs RSpec in a child process with its output captured through a pipe (not a TTY).
  # `--format RSpec::CollapsingFormatter` without `--require` checks that RSpec can
  # autoload the formatter from its constant name.
  def run_rspec(*args)
    Open3.capture2e({ "SPEC_OPTS" => nil }, *command(*args), chdir: File.join(root, "spec", "fixtures"))
  end

  # Runs RSpec in a child process attached to a pseudo-terminal of the given size and
  # returns everything it wrote, as interpreted by a VirtualTerminal.
  def run_rspec_in_terminal(*args, rows: 40, columns: 100)
    output = +""
    status = PTY.open do |controller, child_tty|
      child_tty.winsize = [rows, columns]
      pid = Process.spawn({ "SPEC_OPTS" => nil, "TERM" => "xterm-256color" }, *command(*args),
                          in: child_tty, out: child_tty, err: child_tty,
                          chdir: File.join(root, "spec", "fixtures"))
      child_tty.close
      begin
        loop { output << controller.readpartial(4096) }
      rescue EOFError, Errno::EIO
        # the child closed the terminal
      end
      Process.wait2(pid).last
    end
    # Fed in one piece: reads can split escape sequences and UTF-8 characters.
    terminal = VirtualTerminal.new(rows: rows, columns: columns)
    terminal.feed(output.force_encoding(Encoding::UTF_8))
    [terminal, status]
  end

  def command(*args)
    [
      Gem.ruby, "-I", File.join(root, "lib"),
      "-e", "require 'rspec/core'; exit RSpec::Core::Runner.run(ARGV)", "--",
      fixture, "--format", "RSpec::CollapsingFormatter", *args
    ]
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

  it "collapses the tree in a terminal and prints failure details and summary below it" do
    terminal, status = run_rspec_in_terminal

    expect(status.exitstatus).to eq(1)
    transcript = terminal.transcript.join("\n")
    expect(transcript).to include(<<~TEXT.chomp)
      ✗ User (3 passed, 1 failed, 1 pending)
        ✓ when active (2 examples)
        ✗ when suspended (1 passed, 1 failed, 1 pending)
          ✓ is invalid
          ✗ cannot log in (FAILED - 1)
          • sends a notice (PENDING: Not yet implemented)
    TEXT
    expect(transcript).not_to include("▸")
    expect(transcript).to include("1) User when suspended cannot log in")
    expect(transcript).to include("5 examples, 1 failure, 1 pending")
  end

  it "stays readable in a terminal shorter than the tree" do
    terminal, status = run_rspec_in_terminal(rows: 5)

    expect(status.exitstatus).to eq(1)
    expect(terminal.transcript.count("    ✗ cannot log in (FAILED - 1)")).to eq(1)
    expect(terminal.transcript.join("\n")).not_to include("▸")
    expect(terminal.transcript).to include("5 examples, 1 failure, 1 pending")
  end
end
