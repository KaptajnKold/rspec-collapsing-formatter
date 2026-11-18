# frozen_string_literal: true

require "timeout"
require "tmpdir"

RSpec.describe RSpec::CollapsingFormatter::Parallel do
  events = RSpec::CollapsingFormatter::Events

  around do |example|
    Dir.mktmpdir("rcf") do |dir|
      @address = File.join(dir, "run.sock")
      Timeout.timeout(10) { example.run }
    end
  end

  let(:tty) { FakeTTY.new(rows: 20, columns: 60) }
  let(:env) { { "TERM" => "xterm-256color" } }
  let(:running_processes) { nil }

  def run_context(worker)
    RSpec::CollapsingFormatter::Runners::Context.new(worker: worker, coordinator: worker == 1, address: @address,
                                                     running_processes: -> { running_processes })
  end

  def coordinator(connect_timeout: 5)
    stub_const("ENV", ENV.to_h.merge(env))
    described_class::Coordinator.start(run_context(1), tty, connect_timeout: connect_timeout)
  end

  def worker(number, timeout: 2)
    described_class::Worker.start(run_context(number), timeout: timeout)
  end

  # Waits until the coordinator's screen shows `text`.
  def wait_for_screen(text)
    sleep 0.01 until tty.terminal.lines.any? { |line| line.include?(text) }
  end

  it "shows the workers' events on the coordinator's display" do
    coordinating = coordinator
    remote = worker(2)
    coordinating.call(events::GroupStarted.new(description: "User", worker: 1))
    remote.call(events::GroupStarted.new(description: "Auction", worker: 2))
    remote.call(events::ExampleStarted.new(description: "accepts bids", worker: 2))
    wait_for_screen("accepts bids")

    expect(tty.terminal.lines).to eq(["", "User", "", "Auction", "  ▸ accepts bids"])
  end

  it "waits for every worker, then prints the coordinator's results, then each worker's" do
    printed = Queue.new
    coordinating = coordinator
    remote = worker(2)
    remote.call(events::GroupStarted.new(description: "Auction", worker: 2))
    coordinating.call(events::Finished.new(worker: 1))
    closing = Thread.new { coordinating.close { printed << :coordinator } }

    expect(closing.join(0.3)).to be_nil
    expect(printed).to be_empty

    remote.call(events::GroupFinished.new(worker: 2))
    remote.call(events::Finished.new(worker: 2))
    remote.close { printed << :worker }
    closing.join

    expect([printed.pop, printed.pop]).to eq(%i[coordinator worker])
  end

  it "does not wait for a worker that disconnected" do
    coordinating = coordinator
    remote = worker(2)
    remote.call(events::GroupStarted.new(description: "Auction", worker: 2))
    remote.instance_variable_get(:@client).close # as if the process died

    expect { coordinating.close {} }.not_to raise_error
  end

  context "when the pid file shows a process that has not connected" do
    let(:running_processes) { 2 }

    it "waits for it until it can no longer connect" do
      coordinating = coordinator(connect_timeout: 0.2)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      coordinating.close {}

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(1.0, 3.0)
    end

    it "stops waiting once it has connected and finished" do
      coordinating = coordinator
      closing = Thread.new { coordinating.close {} }
      remote = worker(2)
      remote.call(events::Finished.new(worker: 2))
      remote.close {}

      expect(closing.join(2)).to eq(closing)
    end
  end

  describe "RSpec's interrupt notice" do
    let(:notice) { "\nRSpec is shutting down and will print the summary report... Interrupt again to force quit.\n" }

    # Prints the notice in a worker, followed by a group, and waits until the group
    # has arrived, so the notice would have too.
    def print_notice(number, group)
      remote = worker(number)
      remote.stray_output(nil, notice)
      remote.call(RSpec::CollapsingFormatter::Events::GroupStarted.new(description: group, worker: number))
      wait_for_screen(group)
    end

    it "is shown once when several workers print it" do
      coordinator
      print_notice(2, "Auction")
      print_notice(3, "Bid")

      expect(tty.terminal.lines.grep(/shutting down/).size).to eq(1)
    end

    it "is not shown for workers when the coordinator was interrupted too, as it prints its own" do
      allow(RSpec.world).to receive(:wants_to_quit).and_return(true)
      coordinator
      print_notice(2, "Auction")

      expect(tty.terminal.lines.grep(/shutting down/)).to be_empty
    end
  end

  it "gives up connecting when there is no coordinator" do
    expect(worker(2, timeout: 0.1)).to be_nil
  end
end
