# frozen_string_literal: true

RSpec.describe VirtualTerminal do
  subject(:terminal) { described_class.new(rows: 3, columns: 10) }

  it "writes text and moves to the next row on LF" do
    terminal.feed("one\ntwo\n")

    expect(terminal.lines).to eq(%w[one two])
    expect(terminal.cursor).to eq([2, 0])
  end

  it "overwrites from column 0 after CR" do
    terminal.feed("hello\rJ")

    expect(terminal.lines).to eq(["Jello"])
  end

  it "moves the cursor up and erases to the end of the screen" do
    terminal.feed("one\ntwo\nthree")
    terminal.feed("\r\e[1A\e[Jfour\n")

    expect(terminal.lines).to eq(%w[one four])
  end

  it "treats a zero cursor-up count as one, like real terminals" do
    terminal.feed("one\ntwo\n\e[0A\e[J")

    expect(terminal.lines).to eq(["one"])
  end

  it "erases to the end of the line" do
    terminal.feed("hello\rhe\e[K")

    expect(terminal.lines).to eq(["he"])
  end

  it "ignores color sequences" do
    terminal.feed("\e[32mgreen\e[0m")

    expect(terminal.lines).to eq(["green"])
  end

  it "raises on any other escape sequence" do
    expect { terminal.feed("\e[2J") }.to raise_error(VirtualTerminal::UnsupportedSequence)
    expect { terminal.feed("\e[?25l") }.to raise_error(VirtualTerminal::UnsupportedSequence)
  end

  it "wraps long lines at the right margin" do
    terminal.feed("0123456789ab")

    expect(terminal.lines).to eq(%w[0123456789 ab])
  end

  it "does not wrap a line that exactly fills the row until more text arrives" do
    terminal.feed("0123456789\n")

    expect(terminal.lines).to eq(["0123456789"])
    expect(terminal.cursor).to eq([1, 0])
  end

  it "gives wide characters two columns" do
    terminal.feed("日本語日本語")

    expect(terminal.lines).to eq(%w[日本語日本 語])
  end

  it "scrolls rows off the top into the scrollback" do
    terminal.feed("a\nb\nc\nd\n")

    expect(terminal.scrollback).to eq(%w[a b])
    expect(terminal.lines).to eq(%w[c d])
    expect(terminal.transcript).to eq(%w[a b c d])
  end
end
