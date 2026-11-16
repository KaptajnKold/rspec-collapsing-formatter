# frozen_string_literal: true

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Glyphs and color roles shared by every output mode.
    #
    # Colors are named by RSpec's configurable roles (:success, :failure, ...), so they
    # follow the user's RSpec color configuration when wrapped with ConsoleCodes.
    class Symbols
      UNICODE = { passed: "✓", failed: "✗", pending: "•", running: "▸", ellipsis: "…" }.freeze
      ASCII = { passed: "+", failed: "x", pending: "*", running: ">", ellipsis: "..." }.freeze
      STYLES = { passed: :success, failed: :failure, pending: :pending, running: :detail }.freeze

      def self.for(output)
        encoding = (output.external_encoding if output.respond_to?(:external_encoding)) || Encoding.default_external
        new(encoding == Encoding::UTF_8 ? UNICODE : ASCII)
      end

      def initialize(glyphs)
        @glyphs = glyphs
      end

      def glyph(status)
        @glyphs.fetch(status)
      end

      def ellipsis
        @glyphs.fetch(:ellipsis)
      end

      def style(status)
        STYLES.fetch(status)
      end
    end
  end
end
