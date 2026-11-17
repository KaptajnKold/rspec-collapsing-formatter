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
      text = chunk.to_s.dup.force_encoding(Encoding::UTF_8) # like a UTF-8 terminal, whatever the string's encoding
      @writes << text
      terminal.feed(text)
    end
    super
  end
end
