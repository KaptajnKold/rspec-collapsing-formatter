# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Append-only output for pipes, files and CI logs.
    #
    # Writes documentation-style lines as events arrive: a header when a group starts,
    # one line per example when it finishes. Never emits cursor-control sequences;
    # color is applied only through RSpec's ConsoleCodes, which honours --color settings.
    class StreamOutput
      def initialize(output, symbols)
        @output = output
        @symbols = symbols
        @layout = Layout.new(symbols)
      end

      def group_started(group, depth)
        @output.puts if depth.zero?
        write(@layout.header_line(group, depth))
      end

      def example_finished(example, depth)
        write(@layout.example_line(example, depth))
      end

      def message(text)
        @output.puts(text)
      end

      # Nothing is shown for these events: lines are only ever appended.
      def start; end
      def group_finished(_group, _depth); end
      def example_started(_example, _depth); end
      def finish; end

      private

      def write(line)
        @output.puts(@symbols.paint(line))
      end
    end
  end
end
