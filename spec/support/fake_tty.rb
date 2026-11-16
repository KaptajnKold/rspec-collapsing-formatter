# frozen_string_literal: true

require "stringio"

# A StringIO that claims to be a terminal. Everything written to it is also fed to a
# VirtualTerminal of the given size, and each write call is recorded.
class FakeTTY < StringIO
  attr_reader :terminal, :writes

  def initialize(rows: 40, columns: 80)
    super(+"")
    @terminal = VirtualTerminal.new(rows: rows, columns: columns)
    @writes = []
  end

  def tty?
    true
  end
  alias isatty tty?

  def winsize
    [terminal.rows, terminal.columns]
  end

  # StringIO#puts, #print and #<< all go through #write.
  def write(*data)
    data.each do |chunk|
      @writes << chunk.to_s
      terminal.feed(chunk)
    end
    super
  end
end
