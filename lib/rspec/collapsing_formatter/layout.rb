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
      # `node` is the group or example the line shows (nil for a blank separator).
      Line = Struct.new(:indent, :text, :style, :node) do
        def to_s
          indent + text
        end
      end

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

          lines << Line.new("", "", nil, nil) if previous && (expanded?(previous) || expanded?(group))
          lines.concat(group_lines)
          previous = group
        end
      end

      # The lines from `node` to the end of its top-level group, as they appear in
      # `lines`, without laying out anything before `node`: the node's own lines, then
      # its following siblings, then those of each ancestor. Groups after the top-level
      # group are not included.
      def lines_from(node)
        depth = node.depth
        lines = node_lines(node, depth)
        while (parent = node.parent)
          parent.children[(node.index + 1)..].each { |sibling| lines.concat(node_lines(sibling, depth)) }
          node = parent
          depth -= 1
        end
        lines
      end

      # Lines for several running top-level groups (one per worker) in at most `height`
      # lines, as detailed as fits:
      # 1. everything, as `lines` would show it;
      # 2. for each group, the path to where it is now: its open groups and its latest
      #    example or finished subgroup;
      # 3. one line per group, e.g. "User › when suspended › ▸ cannot log in";
      # 4. as many of those as fit, and a line counting the rest.
      def fitted_lines(groups, height, previous: nil)
        full = lines(groups, previous: previous)
        return full if full.size <= height

        paths = groups.flat_map { |group| path_lines(group) }
        return paths if paths.size <= height

        summaries = groups.map { |group| one_line(group) }
        return summaries if summaries.size <= height
        return [] unless height.positive?

        hidden = summaries.size - (height - 1)
        [*summaries.first(height - 1), line(0, "#{@symbols.ellipsis} #{hidden} more", @symbols.style(:running), nil)]
      end

      # Whether a finished group is shown as a single summary line, or not at all.
      def hides_children?(group)
        %i[passed pending empty].include?(group.status)
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
        return line(depth, group.description, nil, group) if status == :running

        text = "#{@symbols.glyph(status)} #{group.description} (#{summary(group.counts)})"
        line(depth, text, @symbols.style(status), group)
      end

      def example_line(example, depth)
        text = "#{@symbols.glyph(example.status)} #{example.description}"
        text += " (#{example.detail})" if example.detail
        line(depth, text, @symbols.style(example.status), example)
      end

      private

      def children_lines(group, depth)
        group.children.flat_map { |child| node_lines(child, depth) }
      end

      def node_lines(node, depth)
        node.is_a?(GroupNode) ? group_lines(node, depth) : [example_line(node, depth)]
      end

      # The group's chain of open (running) groups, outermost first, and the last child
      # of the innermost one: the running example, or whatever finished last.
      def open_path(group)
        chain = [group]
        while (last = chain.last.children.last).is_a?(GroupNode) && !last.finished?
          chain << last
        end
        [chain, chain.last.children.last]
      end

      def path_lines(group)
        chain, latest = open_path(group)
        headers = chain.each_with_index.map { |node, depth| header_line(node, depth) }
        return headers unless latest

        depth = chain.size
        latest_line = latest.is_a?(GroupNode) ? header_line(latest, depth) : example_line(latest, depth)
        latest.is_a?(GroupNode) && latest.status == :empty ? headers : [*headers, latest_line]
      end

      def one_line(group)
        chain, latest = open_path(group)
        parts = chain.map(&:description)
        if latest.is_a?(ExampleNode) && !latest.finished?
          parts << "#{@symbols.glyph(:running)} #{latest.description}"
        end
        line(0, parts.join(" #{@symbols.path_separator} "), nil, group)
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

      def line(depth, text, style, node)
        indent = INDENT * depth
        if @width
          max_width = [@width - 1, 0].max
          indent = indent[0, max_width]
          text = truncate(text, max_width - indent.length)
        end
        Line.new(indent, text, style, node)
      end

      def truncate(text, max_width)
        # No character is wider than its UTF-8 encoding is long, so this skips measuring
        # the common short line.
        return text if text.bytesize <= max_width || Unicode::DisplayWidth.of(text) <= max_width

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
