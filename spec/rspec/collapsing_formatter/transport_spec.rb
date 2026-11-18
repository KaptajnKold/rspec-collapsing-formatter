# frozen_string_literal: true

require "timeout"
require "tmpdir"

RSpec.describe RSpec::CollapsingFormatter::Transport do
  events = RSpec::CollapsingFormatter::Events

  describe ".encode and .decode" do
    [
      events::Started.new(worker: 2),
      events::GroupStarted.new(description: "User ✓ \"quoted\"", worker: 2),
      events::GroupFinished.new(worker: 3),
      events::ExampleStarted.new(description: "is valid", worker: 1),
      events::ExampleFinished.new(description: "is valid", status: :failed, detail: "FAILED - 1", worker: 1),
      events::Message.new(text: "Run options: include {:focus=>true}", worker: 1),
      events::Output.new(text: "line one\nline t", worker: 4),
      events::Finished.new(worker: 4)
    ].each do |event|
      it "round-trips #{event.class.name.split("::").last}" do
        line = described_class.encode(event)

        expect(line).to end_with("\n")
        expect(line.count("\n")).to eq(1)
        expect(described_class.decode(line)).to eq(event)
      end
    end

    it "ignores lines that are not events" do
      expect(described_class.decode("not json\n")).to be_nil
      expect(described_class.decode("[1]\n")).to be_nil
      expect(described_class.decode(%({"type":"Kernel"}\n))).to be_nil
      expect(described_class.decode(%({"worker":1}\n))).to be_nil
    end

    it "ignores unknown fields" do
      expect(described_class.decode(%({"type":"GroupFinished","worker":1,"color":"red"}\n)))
        .to eq(events::GroupFinished.new(worker: 1))
    end
  end

  describe "Server and Client" do
    around do |example|
      Dir.mktmpdir("rcf") do |dir|
        @path = File.join(dir, "test.sock")
        example.run
      end
    end

    let(:received) { Queue.new }
    let!(:server) { described_class::Server.new(@path) { |worker, event| received << [worker, event] } }

    after { server.close }

    def connect(worker, timeout: 2)
      described_class::Client.connect(@path, worker: worker, timeout: timeout)
    end

    def next_received
      Timeout.timeout(2) { received.pop }
    end

    it "delivers each worker's events, then its disconnection" do
      client = connect(2)
      client.send_event(events::GroupStarted.new(description: "User", worker: 2))
      client.close

      expect(next_received).to eq([2, events::GroupStarted.new(description: "User", worker: 2)])
      expect(next_received).to eq([2, nil])
    end

    it "keeps the worker waiting until it is released" do
      client = connect(2)
      client.send_event(events::Finished.new(worker: 2))
      next_received
      waiter = Thread.new { client.wait_for_release }

      expect(waiter.join(0.2)).to be_nil
      expect(server.release(2)).to be(true)
      expect(waiter.join(2)).to eq(waiter)
      client.close
    end

    it "stops waiting when the server goes away" do
      client = connect(2)
      client.send_event(events::Finished.new(worker: 2))
      next_received
      waiter = Thread.new { client.wait_for_release }
      server.close

      expect(waiter.join(2)).to eq(waiter)
    end

    it "cannot release a worker that is not connected" do
      expect(server.release(5)).to be(false)
    end

    it "retries connecting until the server is listening" do
      server.close
      client = nil
      connecting = Thread.new { client = connect(3, timeout: 3) }
      sleep 0.2
      late = described_class::Server.new(@path) { |worker, event| received << [worker, event] }
      connecting.join(3)
      client.send_event(events::Finished.new(worker: 3))

      expect(next_received).to eq([3, events::Finished.new(worker: 3)])
      client.close
      late.close
    end

    it "gives up connecting after the timeout" do
      server.close

      expect(connect(3, timeout: 0.2)).to be_nil
    end

    it "carries on without error when the server goes away mid-run" do
      client = connect(2)
      server.close
      sleep 0.05

      expect { 3.times { client.send_event(events::GroupFinished.new(worker: 2)) } }.not_to raise_error
    end
  end
end
