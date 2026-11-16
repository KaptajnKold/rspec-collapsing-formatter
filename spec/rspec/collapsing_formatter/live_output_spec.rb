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

  it "leaves the screen as it is on finish, with the cursor on a fresh line" do
    start_group("User")
    start_example("is valid") # e.g. interrupted
    live.finish

    expect(screen).to eq(["", "User", "  ▸ is valid"])
    expect(tty.terminal.cursor).to eq([3, 0])
  end
end
