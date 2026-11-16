# frozen_string_literal: true

RSpec.describe RSpec::CollapsingFormatter::Tree do
  subject(:tree) { described_class.new }

  it "nests groups and examples in run order" do
    tree.group_started("User")
    tree.group_started("when active")
    tree.example_started("is valid")
    tree.example_finished("is valid", :passed)
    tree.group_finished
    tree.example_started("has a name")
    tree.example_finished("has a name", :passed)
    tree.group_finished

    user = tree.groups.first
    expect(user.description).to eq("User")
    expect(user.children.map(&:description)).to eq(["when active", "has a name"])
    expect(user.children.first.children.map(&:description)).to eq(["is valid"])
  end

  it "tracks depth as groups open and close" do
    expect { tree.group_started("User") }.to change(tree, :depth).from(0).to(1)
    expect { tree.group_started("when active") }.to change(tree, :depth).to(2)
    expect { tree.group_finished }.to change(tree, :depth).to(1)
  end

  it "updates an example's description when it finishes" do
    tree.group_started("User")
    example = tree.example_started("example at ./user_spec.rb:3")
    tree.example_finished("is expected to be valid", :passed)

    expect(example.description).to eq("is expected to be valid")
  end

  it "records examples that finish without having been started" do
    tree.group_started("User")
    example = tree.example_finished("is valid", :failed, "FAILED - 1")

    expect(tree.groups.first.children).to eq([example])
    expect(example).to have_attributes(status: :failed, detail: "FAILED - 1")
  end

  describe "group counts and status" do
    def build_group(*statuses)
      tree.group_started("User")
      statuses.each_with_index do |status, index|
        tree.example_started("example #{index}")
        tree.example_finished("example #{index}", status)
      end
      tree.groups.first
    end

    it "is running until the group finishes" do
      group = build_group(:failed)

      expect(group.status).to eq(:running)
    end

    it "counts examples in nested groups" do
      tree.group_started("User")
      tree.group_started("when active")
      tree.example_started("a")
      tree.example_finished("a", :passed)
      tree.example_started("b")
      tree.example_finished("b", :pending)
      tree.group_finished
      tree.example_started("c")
      tree.example_finished("c", :failed)

      expect(tree.groups.first.counts.to_a).to eq([1, 1, 1])
    end

    it "does not count a running example" do
      tree.group_started("User")
      tree.example_started("a")

      expect(tree.groups.first.counts.total).to eq(0)
    end

    {
      %i[passed passed] => :passed,
      %i[passed pending] => :pending,
      %i[passed pending failed] => :failed,
      [] => :empty
    }.each do |statuses, expected|
      it "is #{expected} when its examples are #{statuses.inspect}" do
        group = build_group(*statuses)
        tree.group_finished

        expect(group.status).to eq(expected)
      end
    end
  end
end
