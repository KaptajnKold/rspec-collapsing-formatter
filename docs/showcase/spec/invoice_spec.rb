require_relative "spec_helper"

RSpec.describe "Invoice" do
  it("totals the line items") {}
  it("adds VAT") {}
  it("sends a reminder") { pending("mailer not wired up"); raise "no mailer" }
  context "when paid" do
    it("is marked as settled") {}
    it("cannot be edited") {}
  end
end
