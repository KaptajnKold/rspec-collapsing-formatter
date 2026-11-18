# frozen_string_literal: true

RSpec.describe RSpec::CollapsingFormatter::Layout do
  let(:symbols) { RSpec::CollapsingFormatter::Symbols.new(RSpec::CollapsingFormatter::Symbols::UNICODE) }
  let(:tree) { RSpec::CollapsingFormatter::Tree.new }

  def render(width: nil)
    described_class.new(symbols, width: width).lines(tree.groups).map(&:to_s)
  end

  # Builds the tree from a nested hash: a group maps to a hash of children; an
  # example maps to a status, or to nil while it is still running. Groups listed
  # in `running` are left open.
  def build(spec, running: [])
    spec.each do |description, content|
      case content
      when Hash
        tree.group_started(description)
        build(content, running: running)
        tree.group_finished unless running.include?(description)
      when nil
        tree.example_started(description)
      else
        tree.example_started(description)
        detail = { failed: "FAILED - 1", pending: "PENDING: Not yet implemented" }[content]
        tree.example_finished(description, content, detail)
      end
    end
  end

  it "expands a running group, marking finished and running examples" do
    build({ "User" => { "is valid" => :passed, "can log in" => nil } }, running: ["User"])

    expect(render).to eq(["User", "  ✓ is valid", "  ▸ can log in"])
  end

  it "collapses a successful top-level group" do
    build({ "User" => { "is valid" => :passed, "can log in" => :passed } })

    expect(render).to eq(["✓ User (2 examples)"])
  end

  it "uses singular grammar for one example" do
    build({ "User" => { "is valid" => :passed } })

    expect(render).to eq(["✓ User (1 example)"])
  end

  it "collapses finished nested groups while their parent runs" do
    build(
      {
        "User" => {
          "when active" => { "is valid" => :passed, "can log in" => :passed, "is notified" => :passed },
          "when suspended" => { "is invalid" => :passed, "cannot log in" => nil }
        }
      },
      running: ["User", "when suspended"]
    )

    expect(render).to eq([
      "User",
      "  ✓ when active (3 examples)",
      "  when suspended",
      "    ✓ is invalid",
      "    ▸ cannot log in"
    ])
  end

  it "collapses sibling contexts independently" do
    build(
      { "User" => { "when active" => { "a" => :passed }, "when suspended" => { "b" => :passed, "c" => :passed } } },
      running: ["User"]
    )

    expect(render).to eq(["User", "  ✓ when active (1 example)", "  ✓ when suspended (2 examples)"])
  end

  it "counts nested examples in a collapsed top-level group" do
    build({ "User" => { "when active" => { "a" => :passed, "b" => :passed }, "c" => :passed } })

    expect(render).to eq(["✓ User (3 examples)"])
  end

  it "keeps a group with a failure expanded, collapsing its successful parts" do
    build({
      "User" => {
        "when active" => { "a" => :passed, "b" => :passed },
        "when suspended" => { "is invalid" => :passed, "cannot log in" => :failed }
      }
    })

    expect(render).to eq([
      "✗ User (3 passed, 1 failed)",
      "  ✓ when active (2 examples)",
      "  ✗ when suspended (1 passed, 1 failed)",
      "    ✓ is invalid",
      "    ✗ cannot log in (FAILED - 1)"
    ])
  end

  it "collapses a group with pending examples into a breakdown" do
    build({ "validations" => { "a" => :passed, "b" => :passed, "c" => :pending } })

    expect(render).to eq(["• validations (2 passed, 1 pending)"])
  end

  it "shows pending examples inside a failed group" do
    build({ "User" => { "a" => :pending, "b" => :failed } })

    expect(render).to eq([
      "✗ User (1 failed, 1 pending)",
      "  • a (PENDING: Not yet implemented)",
      "  ✗ b (FAILED - 1)"
    ])
  end

  it "omits finished groups in which no examples ran" do
    build({ "User" => { "filtered" => {}, "a" => :passed }, "Empty" => {} })

    expect(render).to eq(["✓ User (1 example)"])
  end

  it "stacks collapsed top-level groups and separates expanded ones with a blank line" do
    build(
      { "User" => { "a" => :passed }, "Bid" => { "b" => :passed }, "Auction" => { "c" => :failed },
        "Lot" => { "d" => :passed }, "Item" => { "e" => nil } },
      running: ["Item"]
    )

    expect(render).to eq([
      "✓ User (1 example)",
      "✓ Bid (1 example)",
      "",
      "✗ Auction (1 failed)",
      "  ✗ c (FAILED - 1)",
      "",
      "✓ Lot (1 example)",
      "",
      "Item",
      "  ▸ e"
    ])
  end

  it "attaches the color role to each line, leaving running headers plain" do
    build({ "User" => { "a" => :passed, "b" => :failed, "c" => :pending, "d" => nil } }, running: ["User"])

    lines = described_class.new(symbols).lines(tree.groups)
    expect(lines.map(&:style)).to eq([nil, :success, :failure, :pending, :detail])
  end

  describe "truncation" do
    it "leaves lines that fit untouched" do
      build({ "User" => { "is valid" => :passed } })

      expect(render(width: 20)).to eq(["✓ User (1 example)"])
    end

    it "truncates long lines to one column less than the width, including the indent" do
      build({ "User" => { "is valid for a very long time" => :passed } }, running: ["User"])

      expect(render(width: 20)).to eq(["User", "  ✓ is valid for a…"])
      expect(render(width: 20).map { |line| Unicode::DisplayWidth.of(line) }).to all(be <= 19)
    end

    it "measures wide characters by display columns" do
      build({ "ユーザー" => { "有効なユーザーであること" => :passed } }, running: ["ユーザー"])

      lines = render(width: 16)
      expect(lines).to eq(["ユーザー", "  ✓ 有効なユー…"])
      expect(lines.map { |line| Unicode::DisplayWidth.of(line) }).to all(be <= 15)
    end

    it "does not split emoji grapheme clusters" do
      build({ "User" => { "👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽" => :passed } }, running: ["User"])

      # Emoji widths differ between unicode-display_width versions (and terminals), so
      # assert the invariants rather than an exact cut point.
      line = render(width: 13).last
      expect(Unicode::DisplayWidth.of(line)).to be <= 12
      expect(line).to match(/\A  ✓ (👍🏽)+…\z/)
    end
  end

  it "never writes past the width, even when the indent alone is too wide" do
    build({ "a" => { "b" => { "c" => { "d" => { "is valid" => nil } } } } }, running: %w[a b c d])

    expect(render(width: 6)).to eq(["a", "  b", "    c", "     ", "     "])
  end

  describe "#lines_from" do
    it "lays out from a node to the end of its top-level group, as in the full layout" do
      build({ "User" => {
              "when active" => { "is valid" => :passed, "can log in" => :failed },
              "has a name" => :passed,
              "when suspended" => { "is invalid" => nil }
            } }, running: ["User", "when suspended"])
      layout = described_class.new(symbols)
      all = layout.lines(tree.groups)
      user = tree.groups.first

      [user, user.children[0], user.children[0].children[1], user.children[1], user.children[2].children[0]]
        .each do |node|
          from = layout.lines_from(node)
          expect(from.map(&:to_s)).to eq(all.drop(all.index { |line| line.node.equal?(node) }).map(&:to_s))
        end
    end
  end

  context "with ASCII symbols" do
    let(:symbols) { RSpec::CollapsingFormatter::Symbols.new(RSpec::CollapsingFormatter::Symbols::ASCII) }

    it "uses ASCII glyphs and ellipsis" do
      build({ "User" => { "is valid for a very long time" => :passed, "b" => nil } }, running: ["User"])

      expect(render(width: 20)).to eq(["User", "  + is valid for...", "  > b"])
    end
  end

  describe "#fitted_lines" do
    # Two workers, each in the middle of a top-level group.
    before do
      tree.group_started("User", worker: 1)
      tree.example_started("is valid", worker: 1)
      tree.example_finished("is valid", :passed, worker: 1)
      tree.group_started("when suspended", worker: 1)
      tree.example_started("is invalid", worker: 1)
      tree.example_finished("is invalid", :passed, worker: 1)
      tree.example_started("cannot log in", worker: 1)

      tree.group_started("Auction", worker: 2)
      tree.group_started("when open", worker: 2)
      tree.example_started("accepts bids", worker: 2)
      tree.example_finished("accepts bids", :passed, worker: 2)
      tree.group_finished(worker: 2)
      tree.example_started("closes", worker: 2)
    end

    def fit(height, width: nil, previous: nil)
      described_class.new(symbols, width: width).fitted_lines(tree.groups, height, previous: previous).map(&:to_s)
    end

    it "shows everything when it fits" do
      expect(fit(10)).to eq(described_class.new(symbols).lines(tree.groups).map(&:to_s))
      expect(fit(10).size).to eq(9)
    end

    it "shows the path to where each group is now when everything does not fit" do
      expect(fit(8)).to eq(
        [
          "User",
          "  when suspended",
          "    ▸ cannot log in",
          "Auction",
          "  ▸ closes"
        ]
      )
    end

    it "shows the latest finished child when no example is running" do
      tree.example_finished("closes", :passed, worker: 2)

      expect(fit(5).last(2)).to eq(["Auction", "  ✓ closes"])
    end

    it "shows one line per group when the paths do not fit" do
      expect(fit(4)).to eq(["User › when suspended › ▸ cannot log in", "Auction › ▸ closes"])
    end

    it "truncates one-line paths to the width" do
      expect(fit(2, width: 20)).to eq(["User › when suspen…", "Auction › ▸ closes"])
    end

    it "counts the groups that do not fit at all" do
      expect(fit(1)).to eq(["… 2 more"])
      tree.group_started("Bid", worker: 3)

      expect(fit(2)).to eq(["User › when suspended › ▸ cannot log in", "… 2 more"])
    end

    it "separates the first group from an expanded group above it only when showing everything" do
      failed = tree.group_started("Search", worker: 4)
      tree.example_finished("finds", :failed, "FAILED - 1", worker: 4)
      tree.group_finished(worker: 4)
      tree.groups.delete(failed)

      expect(fit(10, previous: failed).first).to eq("")
      expect(fit(5, previous: failed).first).to eq("User")
    end
  end
end
