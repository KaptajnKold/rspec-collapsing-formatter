# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Append-only output for non-interactive destinations (files, pipes, CI logs).
    #
    # Mirrors RSpec's documentation formatter: a group header when a group starts and
    # one line per example when it finishes. Never emits cursor-control sequences;
    # color is applied only through RSpec's ConsoleCodes, which honours --color settings.
    class StreamOutput
      def initialize(output, symbols)
        @output = output
        @layout = Layout.new(symbols)
      end

      def group_started(group, depth)
        @output.puts if depth.zero?
        write(@layout.header_line(group, depth))
      end

      def example_finished(example, depth)
        write(@layout.example_line(example, depth))
      end

      private

      def write(line)
        text = line.style ? Core::Formatters::ConsoleCodes.wrap(line.text, line.style) : line.text
        @output.puts(line.indent + text)
      end
    end
  end
end
