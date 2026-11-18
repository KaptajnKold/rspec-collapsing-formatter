# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Glyphs and color roles shared by every output mode.
    #
    # Colors are named by RSpec's configurable roles (:success, :failure, ...), so they
    # follow the user's RSpec color configuration when wrapped with ConsoleCodes.
    class Symbols
      UNICODE = {
        passed: "✓", failed: "✗", pending: "•", running: "▸", ellipsis: "…", path_separator: "›"
      }.freeze
      ASCII = {
        passed: "+", failed: "x", pending: "*", running: ">", ellipsis: "...", path_separator: ">"
      }.freeze
      STYLES = { passed: :success, failed: :failure, pending: :pending, running: :detail }.freeze

      def self.for(output)
        encoding = (output.external_encoding if output.respond_to?(:external_encoding)) || Encoding.default_external
        new(encoding == Encoding::UTF_8 ? UNICODE : ASCII, io: output)
      end

      # `io` is the stream the lines are written to; whether to color them depends on it
      # when RSpec's color mode is automatic. Without it, RSpec's output stream decides.
      def initialize(glyphs, io: nil)
        @glyphs = glyphs
        @io = io
      end

      def glyph(status)
        @glyphs.fetch(status)
      end

      def ellipsis
        @glyphs.fetch(:ellipsis)
      end

      # Between the descriptions in a one-line path, e.g. "User › when active".
      def path_separator
        @glyphs.fetch(:path_separator)
      end

      def style(status)
        STYLES.fetch(status)
      end

      # The line as it is written to the terminal, colored according to RSpec's
      # color configuration.
      def paint(line)
        return line.indent + line.text unless line.style && color?

        "#{line.indent}\e[#{Core::Formatters::ConsoleCodes.console_code_for(line.style)}m#{line.text}\e[0m"
      end

      private

      def color?
        @io ? RSpec.configuration.color_enabled?(@io) : RSpec.configuration.color_enabled?
      end
    end
  end
end
