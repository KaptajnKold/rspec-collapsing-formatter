# frozen_string_literal: true

require "unicode/display_width"

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Turns the tree into display lines. Pure: no IO and no ANSI codes.
    #
    # Collapse rules:
    # - running groups are expanded;
    # - finished groups that passed, or had pending but no failed examples, collapse
    #   to one summary line;
    # - finished groups with a failure stay expanded, so the failure stays visible
    #   in its hierarchy;
    # - finished groups in which no examples ran are omitted.
    #
    # With a width, every line is truncated to fit in `width - 1` display columns, so
    # that one line always occupies exactly one terminal row.
    class Layout
      # `indent` and `text` are plain strings; `style` is a ConsoleCodes color role or nil.
      Line = Struct.new(:indent, :text, :style) do
        def to_s
          indent + text
        end
      end

      BLANK = Line.new("", "", nil).freeze
      INDENT = "  "

      def initialize(symbols, width: nil)
        @symbols = symbols
        @width = width
      end

      # Lines for a list of top-level groups. A blank line separates adjacent groups
      # when either of them is expanded; collapsed summaries stack directly.
      #
      # `previous` is the top-level group displayed just above these, if any (e.g. one
      # already committed to the terminal), so the first group gets the right separator.
      def lines(groups, previous: nil)
        groups.each_with_object([]) do |group, lines|
          group_lines = group_lines(group)
          next if group_lines.empty?

          lines << BLANK if previous && (expanded?(previous) || expanded?(group))
          lines.concat(group_lines)
          previous = group
        end
      end

      def group_lines(group, depth = 0)
        case group.status
        when :empty then []
        when :passed, :pending then [header_line(group, depth)]
        else [header_line(group, depth), *children_lines(group, depth + 1)]
        end
      end

      def header_line(group, depth)
        status = group.status
        return line(depth, group.description, nil) if status == :running

        text = "#{@symbols.glyph(status)} #{group.description} (#{summary(group.counts)})"
        line(depth, text, @symbols.style(status))
      end

      def example_line(example, depth)
        text = "#{@symbols.glyph(example.status)} #{example.description}"
        text += " (#{example.detail})" if example.detail
        line(depth, text, @symbols.style(example.status))
      end

      private

      def children_lines(group, depth)
        group.children.flat_map do |child|
          child.is_a?(GroupNode) ? group_lines(child, depth) : [example_line(child, depth)]
        end
      end

      def expanded?(group)
        %i[running failed].include?(group.status)
      end

      # "3 examples" when everything passed, otherwise a breakdown such as
      # "6 passed, 1 failed".
      def summary(counts)
        if counts.failed.zero? && counts.pending.zero?
          "#{counts.total} #{counts.total == 1 ? "example" : "examples"}"
        else
          { "passed" => counts.passed, "failed" => counts.failed, "pending" => counts.pending }
            .filter_map { |label, count| "#{count} #{label}" if count.positive? }
            .join(", ")
        end
      end

      def line(depth, text, style)
        indent = INDENT * depth
        text = truncate(text, @width - 1 - indent.length) if @width
        Line.new(indent, text, style)
      end

      def truncate(text, max_width)
        return text if Unicode::DisplayWidth.of(text) <= max_width

        room = max_width - Unicode::DisplayWidth.of(@symbols.ellipsis)
        return "" if room.negative?

        used = 0
        kept = text.each_grapheme_cluster.take_while do |grapheme|
          used += Unicode::DisplayWidth.of(grapheme)
          used <= room
        end
        kept.join + @symbols.ellipsis
      end
    end
  end
end
