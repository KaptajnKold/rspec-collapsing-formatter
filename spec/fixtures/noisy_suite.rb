# frozen_string_literal: true

# Fixture run by spec/end_to_end_spec.rb in a separate process: examples that write
# to $stdout and $stderr, and one slow enough to interrupt.
# Deliberately not named *_spec.rb so the main suite does not load it.

RSpec.describe "Importer" do
  context "with a valid file" do
    it("reads the rows") { puts "reading users.csv" }
    it("skips bad rows") do
      warn "row 3: missing email"
      $stderr.print "skipped 1 row"
    end
  end

  # A context, because RSpec runs a group's own examples before its nested groups.
  context "with a large file" do
    it("takes a while") { sleep Float(ENV.fetch("SLOW_EXAMPLE_SECONDS", "0")) }
    it("is never reached when interrupted") { expect(1).to eq(1) }
  end
end
