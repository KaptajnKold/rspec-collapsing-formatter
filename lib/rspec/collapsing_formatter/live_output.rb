# frozen_string_literal: true

require "io/console"

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Output for interactive terminals: redraws the tree in place as it changes.
    #
    # The screen is split into committed lines, which are never touched again, and a
    # live region below them. Finished top-level groups are committed; the running one
    # is the live region. After every event the live region is laid out again and
    # compared with what is on screen: the cursor moves up to the first line that
    # differs, clears to the end of the screen and writes the rest, in one write call.
    #
    # The cursor is always parked at the start of the line below the live region.
    # Lines are truncated to the terminal width so that each occupies one row, which
    # keeps the cursor-up counts correct.
    #
    # The live region is never taller than the terminal, since the cursor cannot move
    # into rows that have scrolled off the top. Lines above that limit are committed as
    # they are, and the live region then starts at the node shown on its first line.
    # Only that part is laid out on each render, so the cost of a render does not grow
    # with the size of the running group.
    #
    # Committed lines can go stale: a group header keeps its running text if the group
    # later fails, and if a group whose lines were committed collapses, its summary and
    # everything after it is written below what is already on screen.
    #
    # While running, $stdout and $stderr (when they are terminals) are replaced by
    # StrayOutput proxies. Complete lines written to them, and RSpec messages, are
    # printed above the live region: it is cleared, the text is written through the
    # original stream, and the live region is drawn again below it. Partial lines wait
    # for their newline or the next event, whichever comes first.
    class LiveOutput
      DEFAULT_WIDTH = 80
      DEFAULT_HEIGHT = 24
      CURSOR_UP = "\e[%dA"
      CLEAR_TO_END_OF_SCREEN = "\e[J"

      def self.supported?(output, env = ENV)
        output.respond_to?(:tty?) && output.tty? && env["TERM"] != "dumb"
      end

      def initialize(output, symbols, tree, env: ENV)
        @output = output
        @symbols = symbols
        @tree = tree
        @env = env
        @frame = []            # live region lines currently on screen, as written
        @frame_nodes = []      # the tree node each of those lines shows
        @start = nil           # node on the first live line, once lines were committed for lack of room
        @committed_groups = 0  # number of top-level groups above the live region
        @last_committed = nil  # last committed group that was displayed
        @started = false
        @proxies = []          # StrayOutput proxies currently installed
        @pending = {}          # proxy => partial line not yet printed (bytes)
        @deferred = []         # [proxy, text] written from signal handlers, printed at the next event
        # Specs may write from other threads. Not reentrant, and need not be: drawing
        # writes to the original streams, never through the proxies.
        @lock = Mutex.new
      end

      # Starts capturing output written to $stdout and $stderr.
      def start
        @lock.synchronize do
          $stdout = capture($stdout)
          $stderr = capture($stderr)
        end
      end

      def group_started(_group, _depth)
        @lock.synchronize { render }
      end

      def group_finished(_group, depth)
        @lock.synchronize do
          render
          commit if depth.zero?
        end
      end

      def example_started(_example, _depth)
        @lock.synchronize { render }
      end

      def example_finished(_example, _depth)
        @lock.synchronize { render }
      end

      # An RSpec message notification.
      def message(text)
        @lock.synchronize { print_above("#{text}\n", @output) }
      end

      # Called by StrayOutput with everything written to it.
      def stray_output(proxy, text)
        @lock.synchronize do
          buffer = (@pending[proxy] ||= String.new) << text.b
          newline = buffer.rindex("\n")
          print_above(buffer.slice!(0..newline), proxy.io) if newline
        end
      rescue ThreadError => e
        # Signal handlers cannot take locks (RSpec writes its "shutting down" message from
        # its SIGINT handler), and may have interrupted a render, so drawing now is unsafe.
        raise unless e.message.include?("trap context")

        @deferred << [proxy, text.b] # Array#<< needs no lock
      end

      # Final redraw before RSpec prints its failure, pending and summary output;
      # everything shown so far becomes permanent, and $stdout and $stderr are restored.
      def finish
        @lock.synchronize do
          release
          render
          commit
        end
      end

      private

      def capture(io)
        return io if io.is_a?(StrayOutput) || !(io.respond_to?(:tty?) && io.tty?)

        StrayOutput.new(io, self).tap { |proxy| @proxies << proxy }
      end

      # Restores the original streams, unless something else has replaced them since.
      def release
        flush_pending
        $stdout = $stdout.io if @proxies.include?($stdout)
        $stderr = $stderr.io if @proxies.include?($stderr)
        @proxies = []
      end

      # Prints deferred output and partial lines, ending the latter so that the live
      # region starts on a new line.
      def flush_pending
        while (proxy, text = @deferred.shift)
          (@pending[proxy] ||= String.new) << text
        end
        @pending.each do |proxy, buffer|
          print_above(buffer.end_with?("\n") ? buffer : "#{buffer}\n", proxy.io) unless buffer.empty?
          buffer.clear
        end
      end

      # Clears the live region, writes `text` (complete lines) through `io` and draws
      # the live region again below it.
      def print_above(text, io)
        clear = @frame.empty? ? "" : "\r#{format(CURSOR_UP, @frame.size)}#{CLEAR_TO_END_OF_SCREEN}"
        redraw = @frame.map { |line| "#{line}\n" }.join
        if io.equal?(@output)
          @output.write([clear, text, redraw].map(&:b).join) # text may hold any bytes
        else
          @output.write(clear)
          @output.flush if @output.respond_to?(:flush)
          io.write(text)
          io.flush if io.respond_to?(:flush)
          @output.write(redraw)
        end
        @output.flush if @output.respond_to?(:flush)
      end

      def render
        flush_pending
        columns, rows = terminal_size
        layout = Layout.new(@symbols, width: columns)
        lines =
          if @start
            @start = topmost_hidden_ancestor(layout, @start) || @start
            layout.lines_from(@start)
          else
            layout.lines(@tree.groups.drop(@committed_groups), previous: @last_committed)
          end
        frame = lines.map { |line| @symbols.paint(line) }

        data = redraw(frame)
        unless @started
          data = "\n#{data}" # matches the blank line StreamOutput writes before a group
          @started = true
        end
        @output.write(data) unless data.empty?
        @output.flush if @output.respond_to?(:flush)
        @frame = frame
        @frame_nodes = lines.map(&:node)
        commit_overflow(rows - 1) # one row is left for the cursor
      end

      # The outermost group above `node` that now collapsed or turned out empty, which
      # means `node`'s line is gone and the live region has to start at that group.
      def topmost_hidden_ancestor(layout, node)
        hidden = nil
        while (node = node.parent)
          hidden = node if node.finished? && layout.hides_children?(node)
        end
        hidden
      end

      def commit_overflow(max_lines)
        excess = @frame.size - max_lines
        return unless excess.positive?

        @frame.shift(excess)
        @frame_nodes.shift(excess)
        # Never a separator: those only come first in the top-level group's lines.
        @start = @frame_nodes.first
      end

      # The bytes that turn the current live region into `frame`.
      def redraw(frame)
        first_change = @frame.each_index.find { |index| @frame[index] != frame[index] } || @frame.size
        lines_up = @frame.size - first_change

        data = +""
        # Never emit a zero count: terminals treat ESC[0A as ESC[1A.
        data << "\r" << format(CURSOR_UP, lines_up) << CLEAR_TO_END_OF_SCREEN if lines_up.positive?
        frame.drop(first_change).each { |line| data << line << "\n" }
        data
      end

      def commit
        groups = @tree.groups.drop(@committed_groups)
        @last_committed = groups.reverse.find { |group| group.status != :empty } || @last_committed
        @committed_groups = @tree.groups.size
        @frame = []
        @frame_nodes = []
        @start = nil
      end

      # [columns, rows], read on every render: from the terminal, else $COLUMNS and
      # $LINES, else 80x24. At least two rows: one line of live region plus the cursor.
      def terminal_size
        rows, columns = winsize
        columns = [columns, env_size("COLUMNS"), DEFAULT_WIDTH].find { |size| size&.positive? }
        rows = [rows, env_size("LINES"), DEFAULT_HEIGHT].find { |size| size&.positive? }
        [columns, [rows, 2].max]
      end

      def winsize
        @output.winsize if @output.respond_to?(:winsize)
      rescue SystemCallError, IOError
        nil
      end

      def env_size(name)
        Integer(@env.fetch(name, ""), exception: false)
      end
    end
  end
end
