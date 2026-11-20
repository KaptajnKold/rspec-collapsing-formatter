require_relative "spec_helper"

RSpec.describe "User" do
  context "when active" do
    it("is valid") {}
    it("can log in") {}
    it("receives notifications") {}
  end
  context "when suspended" do
    it("is invalid") {}
    it("cannot log in") {}
    it("sees a suspension notice") {}
  end
  describe "#full_name" do
    it("joins first and last name") {}
    it("ignores a missing middle name") {}
  end
end
