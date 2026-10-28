# frozen_string_literal: true

# Fixture run by spec/end_to_end_spec.rb in a separate process.
# Deliberately not named *_spec.rb so the main suite does not load it.

RSpec.describe "User" do
  context "when active" do
    it("is valid") { expect(1).to eq(1) }
    it("can log in") { expect(true).to be(true) }
  end

  context "when suspended" do
    it("is invalid") { expect(1).to eq(1) }
    it("cannot log in") { expect(:logged_in).to eq(:rejected) }
    it "sends a notice"
  end
end
