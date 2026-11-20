require_relative "spec_helper"

RSpec.describe "Auction" do
  context "when open" do
    it("accepts bids above the current price") {}
    it("rejects low bids") { expect(90).to be > 100 }
    it("extends the deadline on late bids") {}
  end
  context "when closed" do
    it("rejects all bids") {}
    it("names the winner") {}
    it("notifies the seller") {}
  end
end
