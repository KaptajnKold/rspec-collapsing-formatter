# frozen_string_literal: true

require "open3"
require "pty"
require "io/console"

RSpec.describe "Running parallel_tests with the collapsing formatter" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:suites) { Dir[File.join(root, "spec", "fixtures", "parallel", "*_suite.rb")].sort }

  before do
    skip "parallel_tests is not installed" unless Gem.loaded_specs.key?("parallel_tests")
  end

  # Each worker loads the formatter from this checkout, without this project's .rspec.
  def command(processes: 3)
    rspec_options = "--options /dev/null -I #{File.join(root, "lib")} " \
                    "--format RSpec::CollapsingFormatter --order defined"
    [Gem.ruby, "-S", "bundle", "exec", "parallel_rspec", "-n", processes.to_s, "-o", rspec_options, *suites]
  end

  def environment
    {
      "SPEC_OPTS" => nil,
      "TERM" => "xterm-256color",
      "BUNDLE_GEMFILE" => ENV.fetch("BUNDLE_GEMFILE", File.join(root, "Gemfile")) # the Gemfile this suite runs with
    }
  end

  # Runs parallel_tests attached to a pseudo-terminal. Returns the raw output and the
  # exit status.
  def run_in_terminal(rows: 40, columns: 100)
    output = +"".b
    status = PTY.open do |controller, child_tty|
      child_tty.winsize = [rows, columns]
      pid = Process.spawn(environment, *command, in: child_tty, out: child_tty, err: child_tty, chdir: root)
      child_tty.close
      begin
        loop { output << controller.readpartial(4096) }
      rescue EOFError, Errno::EIO
        # the child closed the terminal
      end
      Process.wait2(pid).last
    end
    [output.force_encoding(Encoding::UTF_8), status]
  end

  # The screens the output went through: one after each redraw. Cut just before each
  # cursor movement, which never splits an escape sequence or a character.
  def screens(output, rows: 40, columns: 100)
    terminal = VirtualTerminal.new(rows: rows, columns: columns)
    output.split(/(?=\r\e\[\d+A)/).map { |piece| terminal.feed(piece).lines }.push(terminal.transcript)
  end

  it "shows every worker's running group at once, then the results of each worker in one piece" do
    output, status = run_in_terminal
    *during, transcript = screens(output)

    expect(status.exitstatus).to eq(1)

    running_at_once = during.map { |screen| screen.count { |line| line.lstrip.start_with?("▸") } }.max
    expect(running_at_once).to be >= 2

    expect(transcript).to include("✓ Alpha (6 examples)", "✓ Gamma (7 examples)", "gamma: indexed 42 records")
    beta = transcript.index("✗ Beta (6 passed, 1 failed)")
    expect(beta).not_to be_nil
    expect(transcript[beta + 1]).to match(/\A  ✗ rejects low bids \(FAILED - 1, worker \d\)\z/)

    # Each group appears once, and every worker's results come after the whole tree.
    %w[Alpha Beta Gamma].each { |name| expect(transcript.grep(/\A[✓✗] #{name} /).size).to eq(1) }
    tree_end = transcript.rindex { |line| line.match?(/\A[✓✗] (Alpha|Beta|Gamma) /) }
    first_result = transcript.index { |line| line.start_with?("Finished in") }
    expect(first_result).to be > tree_end
    expect(transcript.grep(/\AFinished in/).size).to eq(3)
    expect(transcript).to include("  1) Beta rejects low bids")
    expect(transcript).to include("20 examples, 1 failure")
  end

  it "falls back to plain output, without escape sequences, when not attached to a terminal" do
    output, status = Open3.capture2e(environment, *command, chdir: root)

    expect(status.exitstatus).to eq(1)
    expect(output).not_to include("\e")
    expect(output).to include("✗ rejects low bids (FAILED - 1)")
    expect(output).to include("20 examples, 1 failure")
  end
end
