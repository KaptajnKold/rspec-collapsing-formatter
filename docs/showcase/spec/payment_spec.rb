require_relative "spec_helper"

RSpec.describe "Payment" do
  context "with a card" do
    it("charges the amount") {}
    it("handles a declined card") {}
    it("refunds in full") {}
  end
  context "with a bank transfer" do
    it("waits for confirmation") {}
    it("matches the reference") {}
  end
end
