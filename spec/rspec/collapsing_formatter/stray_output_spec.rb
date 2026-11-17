# frozen_string_literal: true

RSpec.describe RSpec::CollapsingFormatter::StrayOutput do
  subject(:proxy) { described_class.new(io, live_output) }

  let(:io) { FakeTTY.new }
  let(:live_output) { double("LiveOutput") }
  let(:written) { [] }

  before { allow(live_output).to receive(:stray_output) { |_proxy, text| written << text } }

  it "hands everything written to the live output, formatted like the original stream" do
    proxy.write("a", 1)
    proxy << "b" << "c"
    proxy.print("d", "e")
    proxy.puts("f", ["g"])
    proxy.puts
    proxy.printf("%03d\n", 7)
    proxy.putc("h")

    expect(written).to eq(["a1", "b", "c", "de", "f\ng\n", "\n", "007\n", "h"])
  end

  it "returns what the IO methods return" do
    expect(proxy.write("abc")).to eq(3)
    expect(proxy.puts("x")).to be_nil
    expect(proxy << "x").to be(proxy)
  end

  it "delegates everything else to the original stream" do
    expect(proxy.tty?).to be(true)
    expect(proxy.winsize).to eq(io.winsize)
    expect(proxy).to respond_to(:sync)
    expect { proxy.no_such_method }.to raise_error(NoMethodError)
  end
end
