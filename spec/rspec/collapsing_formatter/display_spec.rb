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

  describe "in parallel mode" do
    let(:io) { StringIO.new }
    let(:display) do
      described_class.new(RSpec::CollapsingFormatter::Tree.new,
                          RSpec::CollapsingFormatter::StreamOutput.new(io, symbols), parallel: true)
    end

    it "prints each worker's output once its line is complete, without mixing workers" do
      display.call(events::Output.new(text: "loading", worker: 1))
      display.call(events::Output.new(text: "connecting\n", worker: 2))
      display.call(events::Output.new(text: "...done\nindexed", worker: 1))

      expect(io.string).to eq("connecting\nloading...done\n")
    end

    it "ends a worker's partial line when that worker finishes" do
      display.call(events::Output.new(text: "indexed", worker: 1))
      display.call(events::Output.new(text: "loading", worker: 2))
      display.call(events::Finished.new(worker: 1))

      expect(io.string).to eq("indexed\n")
    end

    it "finishes the output only when told to, printing every partial line" do
      output = instance_double(RSpec::CollapsingFormatter::StreamOutput, message: nil, finish: nil)
      display = described_class.new(RSpec::CollapsingFormatter::Tree.new, output, parallel: true)
      display.call(events::Output.new(text: "loading", worker: 2))
      display.call(events::Output.new(text: "indexed", worker: 3))
      display.call(events::Finished.new(worker: 2))

      expect(output).to have_received(:message).with("loading")
      expect(output).not_to have_received(:finish)

      display.finish

      expect(output).to have_received(:message).with("indexed")
      expect(output).to have_received(:finish)
    end

    it "uses parallel live output on a terminal" do
      tty = FakeTTY.new(rows: 10, columns: 40)
      display = described_class.for(tty, parallel: true)
      display.call(events::GroupStarted.new(description: "User", worker: 1))
      display.call(events::GroupStarted.new(description: "Auction", worker: 2))
      display.call(events::GroupFinished.new(worker: 2))

      expect(tty.terminal.lines).to eq(["", "User"])
    end
  end
end
