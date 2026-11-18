# frozen_string_literal: true

RSpec.describe RSpec::CollapsingFormatter::Display do
  events = RSpec::CollapsingFormatter::Events

  let(:symbols) { RSpec::CollapsingFormatter::Symbols.new(RSpec::CollapsingFormatter::Symbols::UNICODE) }

  describe ".for" do
    it "redraws in place on a terminal" do
      tty = FakeTTY.new(rows: 10, columns: 40)
      display = described_class.for(tty)
      display.call(events::GroupStarted.new(description: "User"))
      display.call(events::ExampleStarted.new(description: "is valid"))

      expect(tty.terminal.lines).to eq(["", "User", "  ▸ is valid"])
    end

    it "appends lines when the output is not a terminal" do
      io = StringIO.new
      display = described_class.for(io)
      display.call(events::GroupStarted.new(description: "User"))
      display.call(events::ExampleStarted.new(description: "is valid"))
      display.call(events::ExampleFinished.new(description: "is valid", status: :passed))

      expect(io.string).to eq("\nUser\n  ✓ is valid\n")
    end
  end

  it "applies events to the tree, per worker" do
    display = described_class.new(RSpec::CollapsingFormatter::Tree.new,
                                  RSpec::CollapsingFormatter::StreamOutput.new(StringIO.new, symbols))
    display.call(events::GroupStarted.new(description: "User", worker: 1))
    display.call(events::GroupStarted.new(description: "Auction", worker: 2))
    display.call(events::ExampleFinished.new(description: "rejects low bids", status: :failed,
                                             detail: "FAILED - 1", worker: 2))
    display.call(events::GroupFinished.new(worker: 2))

    user, auction = display.tree.groups
    expect([user.status, auction.status]).to eq(%i[running failed])
    expect(auction.children.first.detail).to eq("FAILED - 1")
  end

  it "passes messages and the end of the run to the output" do
    io = StringIO.new
    display = described_class.for(io)
    display.call(events::Message.new(text: "Run options: include {:focus=>true}"))
    display.call(events::Finished.new)

    expect(io.string).to eq("Run options: include {:focus=>true}\n")
  end

  it "rejects events it does not know" do
    display = described_class.for(StringIO.new)

    expect { display.call(events.define(:text).new(text: "?")) }.to raise_error(ArgumentError, /unknown event/)
  end
end
