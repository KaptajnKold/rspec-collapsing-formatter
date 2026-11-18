# frozen_string_literal: true

# Run in parallel by spec/parallel_tests_spec.rb; not named *_spec.rb, so that this
# project's own suite skips it. Slow enough for the workers' groups to overlap.
RSpec.describe "Alpha" do
  ["when new", "when old"].each do |context_name|
    context context_name do
      3.times do |n|
        it("does thing #{n + 1}") { sleep 0.15 }
      end
    end
  end
end
