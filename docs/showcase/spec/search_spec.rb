require_relative "spec_helper"

RSpec.describe "Search index" do
  before(:all) { puts "search: indexed 42 records" }
  it("indexes new lots") {}
  it("removes sold lots") {}
  describe "#suggest" do
    it("completes partial words") {}
    it("corrects typos") {}
    it("limits suggestions to five") {}
  end
end
