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
      end

      def group_started(_group, _depth)
        render
      end

      def group_finished(_group, depth)
        render
        commit if depth.zero?
      end

      def example_started(_example, _depth)
        render
      end

      def example_finished(_example, _depth)
        render
      end

      # Final redraw before RSpec prints its failure, pending and summary output;
      # everything shown so far becomes permanent.
      def finish
        render
        commit
      end

      private

      def render
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
