# frozen_string_literal: true

# The suite recorded by script/showcase. Examples do no work; each sleeps for a
# duration that is fixed per example, scaled by PACE, so recordings are repeatable.
module Pace
  def self.of(example)
    (0.12 + (example.full_description.sum % 7) * 0.05) * Float(ENV.fetch("PACE", "1"))
  end
end

RSpec.configure { |config| config.before { |example| sleep Pace.of(example) } }
