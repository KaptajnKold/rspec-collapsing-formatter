# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Append-only output for non-interactive destinations (files, pipes, CI logs).
    #
    # Mirrors RSpec's documentation formatter: a group header when a group starts and
    # one line per example when it finishes. Never emits cursor-control sequences;
    # color is applied only through RSpec's ConsoleCodes, which honours --color settings.
    class StreamOutput
      UNICODE_GLYPHS = { passed: "✓", failed: "✗", pending: "•" }.freeze
      ASCII_GLYPHS = { passed: "+", failed: "x", pending: "*" }.freeze
      COLORS = { passed: :success, failed: :failure, pending: :pending }.freeze
      INDENT = "  "

      def initialize(output)
        @output = output
        @glyphs = unicode?(output) ? UNICODE_GLYPHS : ASCII_GLYPHS
      end

      def group_started(description, depth)
        @output.puts if depth.zero?
        @output.puts "#{INDENT * depth}#{description}"
      end

      def example_finished(description, depth, status, detail = nil)
        text = "#{@glyphs.fetch(status)} #{description}"
        text += " (#{detail})" if detail
        @output.puts "#{INDENT * depth}#{Core::Formatters::ConsoleCodes.wrap(text, COLORS.fetch(status))}"
      end

      private

      def unicode?(output)
        encoding = (output.external_encoding if output.respond_to?(:external_encoding)) || Encoding.default_external
        encoding == Encoding::UTF_8
      end
    end
  end
end
