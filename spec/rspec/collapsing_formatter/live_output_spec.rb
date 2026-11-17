# frozen_string_literal: true

RSpec.describe RSpec::CollapsingFormatter::LiveOutput do
  let(:tty) { FakeTTY.new(rows: 20, columns: 60) }
  let(:tree) { RSpec::CollapsingFormatter::Tree.new }
  let(:symbols) { RSpec::CollapsingFormatter::Symbols.new(RSpec::CollapsingFormatter::Symbols::UNICODE) }
  let(:env) { { "TERM" => "xterm-256color" } }
  let(:live) { described_class.new(tty, symbols, tree, env: env) }

  # Drive the tree and the output together, the way the formatter does.
  def start_group(description)
    group = tree.group_started(description)
    live.group_started(group, tree.depth - 1)
  end

  def finish_group
    group = tree.group_finished
    live.group_finished(group, tree.depth)
  end

  def start_example(description)
    live.example_started(tree.example_started(description), tree.depth)
  end

  def finish_example(description, status = :passed, detail = nil)
    live.example_finished(tree.example_finished(description, status, detail), tree.depth)
  end

  def run_example(description, status = :passed, detail = nil)
    start_example(description)
    finish_example(description, status, detail)
  end

  def screen
    tty.terminal.lines
  end

  describe ".supported?" do
    it "is true for a terminal" do
      expect(described_class.supported?(tty, env)).to be(true)
    end

    it "is false when the output is not a terminal" do
      expect(described_class.supported?(StringIO.new, env)).to be(false)
    end

    it "is false for a dumb terminal" do
      expect(described_class.supported?(tty, { "TERM" => "dumb" })).to be(false)
    end
  end

  it "shows a running example and replaces it with its result" do
    start_group("User")
    run_example("is valid")
    start_example("can log in")

    expect(screen).to eq(["", "User", "  ✓ is valid", "  ▸ can log in"])

    finish_example("can log in")

    expect(screen).to eq(["", "User", "  ✓ is valid", "  ✓ can log in"])
  end

  it "rewrites only the line that changed when an example finishes" do
    start_group("User")
    run_example("is valid")
    start_example("can log in")
    tty.writes.clear

    finish_example("can log in")

    expect(tty.writes).to eq(["\r\e[1A\e[J  ✓ can log in\n"])
  end

  it "only appends when a line is added" do
    start_group("User")
    run_example("is valid")
    tty.writes.clear

    start_example("can log in")

    expect(tty.writes).to eq(["  ▸ can log in\n"])
  end

  it "collapses a nested group when it finishes, while its parent keeps running" do
    start_group("User")
    start_group("when active")
    run_example("is valid")
    run_example("can log in")

    expect(screen).to eq(["", "User", "  when active", "    ✓ is valid", "    ✓ can log in"])

    finish_group
    start_group("when suspended")
    start_example("is invalid")

    expect(screen).to eq(["", "User", "  ✓ when active (2 examples)", "  when suspended", "    ▸ is invalid"])
  end

  it "collapses a successful top-level group to one line" do
    start_group("User")
    run_example("is valid")
    run_example("can log in")
    finish_group

    expect(screen).to eq(["", "✓ User (2 examples)"])
    expect(tty.terminal.cursor).to eq([2, 0])
  end

  it "keeps a group with a failure expanded" do
    start_group("User")
    start_group("when active")
    run_example("is valid")
    finish_group
    start_group("when suspended")
    run_example("cannot log in", :failed, "FAILED - 1")
    finish_group
    finish_group

    expect(screen).to eq([
                           "",
                           "✗ User (1 passed, 1 failed)",
                           "  ✓ when active (1 example)",
                           "  ✗ when suspended (1 failed)",
                           "    ✗ cannot log in (FAILED - 1)"
                         ])
  end

  it "stacks collapsed top-level groups, with a blank line only while the next one is expanded" do
    start_group("User")
    run_example("is valid")
    finish_group
    start_group("Auction")
    start_example("accepts bids")

    expect(screen).to eq(["", "✓ User (1 example)", "", "Auction", "  ▸ accepts bids"])

    finish_example("accepts bids")
    finish_group

    expect(screen).to eq(["", "✓ User (1 example)", "✓ Auction (1 example)"])
  end

  it "never redraws above a committed top-level group" do
    start_group("User")
    run_example("is valid", :failed, "FAILED - 1")
    finish_group
    tty.writes.clear

    start_group("Auction")
    run_example("accepts bids")
    run_example("rejects low bids")
    finish_group

    # Auction's live region is at most 4 lines: blank, header and two examples.
    moves = tty.writes.join.scan(/\e\[(\d+)A/).flatten.map(&:to_i)
    expect(moves.max).to be <= 4
    expect(screen).to eq(["", "✗ User (1 failed)", "  ✗ is valid (FAILED - 1)", "", "✓ Auction (2 examples)"])
  end

  it "removes a group in which no examples ran" do
    start_group("User")
    run_example("is valid")
    finish_group
    start_group("Filtered")

    expect(screen).to eq(["", "✓ User (1 example)", "", "Filtered"])

    finish_group

    expect(screen).to eq(["", "✓ User (1 example)"])
  end

  it "truncates lines to the terminal width so they never wrap" do
    tty = FakeTTY.new(rows: 10, columns: 20)
    live = described_class.new(tty, symbols, tree, env: env)
    group = tree.group_started("A group with a long description")
    live.group_started(group, 0)
    live.example_started(tree.example_started("an example with a long description"), 1)

    # 19 columns: one less than the width, so the cursor never sits in the last column.
    expect(tty.terminal.lines).to eq(["", "A group with a lon…", "  ▸ an example wit…"])
  end

  describe "width" do
    def render_with(output, env)
      live = described_class.new(output, symbols, tree, env: env)
      live.group_started(tree.group_started("x" * 200), 0)
      output.string.lines.last.chomp
    end

    it "falls back to $COLUMNS when the terminal size is unknown" do
      output = StringIO.new(+"")

      expect(render_with(output, { "COLUMNS" => "30" }).length).to eq(29)
    end

    it "falls back to 80 columns" do
      output = StringIO.new(+"")

      expect(render_with(output, {}).length).to eq(79)
    end
  end

  describe "a live region taller than the terminal" do
    let(:tty) { FakeTTY.new(rows: 6, columns: 40) }

    def max_cursor_up
      tty.writes.join.scan(/\e\[(\d+)A/).flatten.map(&:to_i).max
    end

    it "commits lines that do not fit, never moving the cursor above the screen" do
      start_group("User")
      8.times { |index| run_example("example #{index}") }
      start_example("example 8")

      expect(max_cursor_up).to be <= 5
      expect(tty.terminal.transcript).to eq(["", "User", *(0..7).map { |index| "  ✓ example #{index}" }, "  ▸ example 8"])
    end

    it "appends a group's summary when some of its lines were already committed" do
      start_group("User")
      start_group("when active")
      8.times { |index| run_example("example #{index}") }
      finish_group
      start_group("when suspended")
      start_example("is invalid")

      expect(tty.terminal.transcript).to eq([
                                              "", "User", "  when active",
                                              "    ✓ example 0", "    ✓ example 1", "    ✓ example 2",
                                              "  ✓ when active (8 examples)", "  when suspended", "    ▸ is invalid"
                                            ])

      finish_example("is invalid")
      finish_group
      finish_group

      expect(tty.terminal.transcript.last(2)).to eq(["    ✓ example 2", "✓ User (9 examples)"])
      expect(max_cursor_up).to be <= 5
    end

    it "leaves a committed header unchanged when its group fails" do
      start_group("User")
      7.times { |index| run_example("example #{index}") }
      run_example("breaks", :failed, "FAILED - 1")
      finish_group

      expect(tty.terminal.transcript).to eq(["", "User", *(0..6).map { |index| "  ✓ example #{index}" },
                                             "  ✗ breaks (FAILED - 1)"])
    end

    it "removes the live lines of nested groups that turn out empty" do
      start_group("User")
      8.times { |index| start_group("context #{index}") }

      expect(screen.last).to eq("                context 7")

      9.times { finish_group }

      # The headers that had scrolled out of reach stay; the rest are erased.
      expect(tty.terminal.transcript).to eq(["", "User", "  context 0", "    context 1", "      context 2"])
      expect(max_cursor_up).to be <= 5
    end

    it "lays out only the live region, however many lines were committed" do
      start_group("User")
      300.times { |index| run_example("example #{index}") }

      calls = 0
      allow_any_instance_of(RSpec::CollapsingFormatter::Layout).to receive(:example_line)
        .and_wrap_original { |original, *args| calls += 1; original.call(*args) }
      run_example("example 300")

      # Two renders (example started and finished), each at most one screenful.
      expect(calls).to be <= 2 * tty.terminal.rows
    end

    it "falls back to $LINES when the terminal size is unknown" do
      output = StringIO.new(+"")
      live = described_class.new(output, symbols, tree, env: { "LINES" => "4" })
      live.group_started(tree.group_started("User"), 0)
      6.times do |index|
        live.example_started(tree.example_started("example #{index}"), 1)
        live.example_finished(tree.example_finished("example #{index}", :passed), 1)
      end

      expect(output.string.scan(/\e\[(\d+)A/).flatten.map(&:to_i).max).to be <= 3
    end
  end

  describe "output from specs" do
    let(:proxy) { RSpec::CollapsingFormatter::StrayOutput.new(tty, live) }

    before do
      start_group("User")
      run_example("is valid")
      start_example("can log in")
    end

    it "prints complete lines above the live region" do
      proxy.puts "connecting..."
      proxy.puts "connected"

      expect(screen).to eq(["", "connecting...", "connected", "User", "  ✓ is valid", "  ▸ can log in"])

      finish_example("can log in")
      finish_group

      expect(screen).to eq(["", "connecting...", "connected", "✓ User (2 examples)"])
    end

    it "waits for the rest of a partial line until the next event" do
      proxy.print "loading"
      proxy.print "..."

      expect(screen).to eq(["", "User", "  ✓ is valid", "  ▸ can log in"])

      finish_example("can log in")

      expect(screen).to eq(["", "loading...", "User", "  ✓ is valid", "  ✓ can log in"])
    end

    it "prints a partial line as soon as its newline arrives" do
      proxy.print "loading"
      proxy.print "...done\nnext"

      expect(screen).to eq(["", "loading...done", "User", "  ✓ is valid", "  ▸ can log in"])
    end

    it "prints output written from a signal handler at the next event, without adding a newline" do
      handled = false
      stderr = proxy # memoized `let` takes a lock, which a signal handler cannot
      previous_handler = trap("USR1") do
        stderr.puts "RSpec is shutting down"
        handled = true
      end
      begin
        Process.kill("USR1", Process.pid)
        sleep 0.01 until handled
      ensure
        trap("USR1", previous_handler)
      end

      expect(screen).to eq(["", "User", "  ✓ is valid", "  ▸ can log in"])

      finish_example("can log in")

      expect(screen).to eq(["", "RSpec is shutting down", "User", "  ✓ is valid", "  ✓ can log in"])
    end

    it "writes the text through the stream it was written to" do
      other = FakeTTY.new
      RSpec::CollapsingFormatter::StrayOutput.new(other, live).puts "on stderr"

      expect(other.string).to eq("on stderr\n")
      expect(tty.writes.last(2)).to eq(["\r\e[3A\e[J", "User\n  ✓ is valid\n  ▸ can log in\n"])
    end

    it "passes through bytes that are not valid UTF-8" do
      proxy.write("caf\xE9\n".b)

      expect(tty.string.b).to include("caf\xE9\n".b)
      expect(screen.last).to eq("  ▸ can log in")
    end

    it "prints RSpec messages above the live region" do
      live.message("Run options: include {:focus=>true}")

      expect(screen).to eq(["", "Run options: include {:focus=>true}", "User", "  ✓ is valid", "  ▸ can log in"])
    end
  end

  describe "capturing $stdout and $stderr" do
    it "replaces terminal streams while running and restores them on finish" do
      with_standard_streams(tty) do
        live.start

        expect($stdout).to be_a(RSpec::CollapsingFormatter::StrayOutput)
        expect($stderr).to be_a(RSpec::CollapsingFormatter::StrayOutput)
        start_group("User")
        start_example("is valid")
        puts "from puts"
        warn "from warn"
        $stdout.print "partial"
        live.finish

        expect($stdout).to be(tty)
        expect($stderr).to be(tty)
      end
      expect(screen).to eq(["", "from puts", "from warn", "partial", "User", "  ▸ is valid"])
    end

    it "leaves streams that are not terminals alone" do
      with_standard_streams(StringIO.new) do
        live.start

        expect($stdout).to be_a(StringIO)
        live.finish
      end
    end

    it "does not restore a stream that something else replaced in the meantime" do
      replacement = StringIO.new
      with_standard_streams(tty) do
        live.start
        $stdout = replacement
        live.finish

        expect($stdout).to be(replacement)
        expect($stderr).to be(tty)
      end
    end
  end

  it "writes nothing when finished twice" do
    start_group("User")
    run_example("is valid")
    live.finish
    tty.writes.clear

    live.finish

    expect(tty.writes).to be_empty
  end

  it "leaves the screen as it is on finish, with the cursor on a fresh line" do
    start_group("User")
    start_example("is valid") # e.g. interrupted
    live.finish

    expect(screen).to eq(["", "User", "  ▸ is valid"])
    expect(tty.terminal.cursor).to eq([3, 0])
  end
end
