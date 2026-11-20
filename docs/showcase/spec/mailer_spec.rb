require_relative "spec_helper"

RSpec.describe "Mailer" do
  it("sends a welcome email") {}
  it("sends an outbid alert") {}
  it("sends a winning-bid receipt") {}
  context "when the address bounces" do
    it("retries once") {}
    it("flags the user") {}
  end
end
