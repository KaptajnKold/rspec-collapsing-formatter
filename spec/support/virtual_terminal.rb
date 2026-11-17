# frozen_string_literal: true

require "strscan"
require "unicode/display_width"

# A tiny terminal emulator for tests: interprets the bytes the formatter writes into
# a fixed-size screen, so specs can assert on what a user would actually see.
#
# Supports printable text (with wide characters and auto-wrap at the right margin),
# CR, LF, cursor up (ESC[nA), erase to end of line (ESC[K) and erase to end of screen
# (ESC[J). Color sequences (ESC[...m) are ignored. Anything else raises, so a spec
# fails if the formatter starts emitting a sequence nobody has checked.
#
# LF also returns the cursor to column 0, like a terminal whose tty driver translates
# "\n" to "\r\n" (ONLCR), which is the default.
class VirtualTerminal
  class UnsupportedSequence < StandardError; end

  BLANK = " "
  WIDE_CHARACTER_TAIL = "" # second cell of a double-width character

  attr_reader :rows, :columns, :scrollback

  def initialize(rows: 24, columns: 80)
    @rows = rows
    @columns = columns
    @screen = Array.new(rows) { blank_row }
    @scrollback = [] # rows scrolled off the top, oldest first
    @row = 0
    @column = 0 # may equal `columns`: the next character wraps
  end

  def feed(data)
    scanner = StringScanner.new(data.to_s.scrub("\uFFFD")) # invalid bytes show as �, as in real terminals
    until scanner.eos?
      if scanner.scan(/\e\[([0-9;]*)([A-Za-z])/) then control(scanner[1], scanner[2])
      elsif scanner.scan(/\e/) then raise UnsupportedSequence, "escape sequence #{scanner.rest[0, 10].inspect}"
      elsif scanner.scan(/\r/) then @column = 0
      elsif scanner.scan(/\n/) then line_feed
      else scanner.scan(/[^\e\r\n]+/).each_grapheme_cluster { |grapheme| put(grapheme) }
      end
    end
    self
  end

  # The visible screen rows, without trailing spaces or trailing empty rows.
  def lines
    texts = @screen.map { |row| row_text(row) }
    texts.pop while texts.last&.empty?
    texts
  end

  # Everything that has been displayed: scrolled-off rows followed by the screen.
  def transcript
    scrollback + lines
  end

  def cursor
    [@row, @column]
  end

  private

  def control(params, command)
    count = params.empty? ? 1 : [params.to_i, 1].max # like real terminals, 0 means 1
    case [command, params]
    in ["m", _] then nil
    in ["A", _] then @row = [@row - count, 0].max
                     @column = [@column, @columns - 1].min
    in ["K", "" | "0"] then clear(@row, @column...@columns)
    in ["J", "" | "0"]
      clear(@row, @column...@columns)
      ((@row + 1)...@rows).each { |row| @screen[row] = blank_row }
    else raise UnsupportedSequence, "ESC[#{params}#{command}"
    end
  end

  def put(grapheme)
    width = Unicode::DisplayWidth.of(grapheme)
    return if width.zero?

    if @column + width > @columns
      line_feed
    end
    @screen[@row][@column] = grapheme
    @screen[@row][@column + 1] = WIDE_CHARACTER_TAIL if width == 2
    @column += width
  end

  def line_feed
    if @row == @rows - 1
      @scrollback << row_text(@screen.shift)
      @screen << blank_row
    else
      @row += 1
    end
    @column = 0
  end

  def clear(row, range)
    range.each { |column| @screen[row][column] = BLANK if column < @columns }
  end

  def blank_row
    Array.new(@columns, BLANK)
  end

  def row_text(row)
    row.join.rstrip
  end
end
