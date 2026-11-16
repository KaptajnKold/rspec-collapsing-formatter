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
    class LiveOutput
      DEFAULT_WIDTH = 80
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
        layout = Layout.new(@symbols, width: width)
        groups = @tree.groups.drop(@committed_groups)
        frame = layout.lines(groups, previous: @last_committed).map { |line| @symbols.paint(line) }

        data = redraw(frame)
        unless @started
          data = "\n#{data}" # matches the blank line StreamOutput writes before a group
          @started = true
        end
        @output.write(data) unless data.empty?
        @output.flush if @output.respond_to?(:flush)
        @frame = frame
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
      end

      def width
        [terminal_columns, Integer(@env.fetch("COLUMNS", ""), exception: false), DEFAULT_WIDTH]
          .find { |columns| columns&.positive? }
      end

      def terminal_columns
        @output.winsize[1] if @output.respond_to?(:winsize)
      rescue SystemCallError, IOError
        nil
      end
    end
  end
end
