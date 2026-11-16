# frozen_string_literal: true

# Read the version without loading Ruby code: defining RSpec::CollapsingFormatter here
# (e.g. while Bundler evaluates this gemspec) would stop RSpec from autoloading and
# registering the formatter when it is given as `--format RSpec::CollapsingFormatter`.
version = File.read(File.join(__dir__, "lib/rspec/collapsing_formatter.rb"))[/VERSION = "([^"]+)"/, 1]

Gem::Specification.new do |spec|
  spec.name = "rspec-collapsing-formatter"
  spec.version = version
  spec.authors = ["Adam Lett"]
  spec.email = ["adamlett@gmail.com"]

  spec.summary = "An RSpec documentation-style formatter that collapses finished example groups."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", "~> 3.10"
  spec.add_dependency "unicode-display_width", ">= 2.4", "< 4"
end
