require_relative "spec_helper"

RSpec.describe "Bid" do
  it("belongs to a bidder") {}
  it("requires a positive amount") {}
  describe "#outbid?" do
    it("is true when a higher bid exists") {}
    it("is false for the highest bid") {}
  end
  describe "#retract" do
    it("is allowed within a minute") {}
    it("is refused afterwards") {}
  end
end
