# frozen_string_literal: true

require "stringio"
require "rspec/core/sandbox"

module FormatterHelpers
  # Runs the example groups defined in the block in an isolated RSpec world, with
  # only the collapsing formatter attached, and returns everything it wrote.
  def run_suite(color: false, output: StringIO.new, &definition)
    RSpec::Core::Sandbox.sandboxed do |config|
      config.color_mode = color ? :on : :off
      config.add_formatter(RSpec::CollapsingFormatter, output)
      definition.call
      options = RSpec::Core::ConfigurationOptions.new([])
      RSpec::Core::Runner.new(options, config, RSpec.world).run_specs(RSpec.world.ordered_example_groups)
    end
    output.string
  end

  # The live part of the output: everything before RSpec's pending/failure/summary dump.
  def progress_output(output)
    output.split(/^(?:Pending:|Failures:|Finished in)/).first
  end
end

RSpec.configure do |config|
  config.include FormatterHelpers
end
