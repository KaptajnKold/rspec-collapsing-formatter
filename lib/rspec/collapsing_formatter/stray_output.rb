# frozen_string_literal: true

require "stringio"

module RSpec
  class CollapsingFormatter < Core::Formatters::BaseTextFormatter
    # Stands in for $stdout or $stderr while the live region is on screen, so that
    # output from specs appears above the tree instead of corrupting it.
    #
    # Everything written is handed to LiveOutput#stray_output, which prints complete
    # lines through the original stream above the live region. All other methods
    # (tty?, sync, fileno, winsize, ...) are delegated to the original stream.
    #
    # Output written to the file descriptor directly, e.g. by subprocesses or through
    # the STDOUT constant, bypasses this and can still corrupt the live region.
    class StrayOutput
      attr_reader :io

      def initialize(io, live_output)
        @io = io
        @live_output = live_output
      end

      def write(*objects)
        text = objects.join
        @live_output.stray_output(self, text)
        text.bytesize
      end

      def <<(object)
        write(object)
        self
      end

      # Formatted exactly as the original stream would format them.
      %i[puts print printf putc].each do |method|
        define_method(method) do |*args|
          formatted = StringIO.new(+"")
          formatted.public_send(method, *args)
          write(formatted.string)
          method == :putc ? args.first : nil
        end
      end

      def respond_to_missing?(name, include_private = false)
        @io.respond_to?(name, include_private) || super
      end

      def method_missing(name, ...)
        return super unless @io.respond_to?(name)

        @io.public_send(name, ...)
      end
    end
  end
end
