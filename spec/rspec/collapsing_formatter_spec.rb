# frozen_string_literal: true

RSpec.describe RSpec::CollapsingFormatter do
  context "with non-interactive output" do
    it "prints a successful top-level group in documentation style" do
      output = run_suite do
        RSpec.describe("User") do
          it("is valid") { expect(1).to eq(1) }
          it("can log in") { expect(1).to eq(1) }
        end
      end

      expect(progress_output(output)).to eq(<<~TEXT)

        User
          ✓ is valid
          ✓ can log in

      TEXT
    end

    it "indents nested and sibling groups" do
      output = run_suite do
        RSpec.describe("User") do
          context("when active") do
            it("is valid") { expect(1).to eq(1) }
          end
          context("when suspended") do
            context("by an admin") do
              it("is invalid") { expect(1).to eq(1) }
            end
          end
        end
      end

      expect(progress_output(output)).to eq(<<~TEXT)

        User
          when active
            ✓ is valid
          when suspended
            by an admin
              ✓ is invalid

      TEXT
    end

    it "separates top-level groups with a blank line" do
      output = run_suite do
        RSpec.describe("User") { it("is valid") { expect(1).to eq(1) } }
        RSpec.describe("Auction") { it("accepts bids") { expect(1).to eq(1) } }
      end

      expect(progress_output(output)).to eq(<<~TEXT)

        User
          ✓ is valid

        Auction
          ✓ accepts bids

      TEXT
    end

    it "marks failed examples with their failure number and keeps RSpec's failure details" do
      output = run_suite do
        RSpec.describe("User") do
          it("is valid") { expect(1).to eq(1) }
          it("cannot log in") { expect(:logged_in).to eq(:rejected) }
          it("cannot post") { expect(:posted).to eq(:rejected) }
        end
      end

      expect(progress_output(output)).to eq(<<~TEXT)

        User
          ✓ is valid
          ✗ cannot log in (FAILED - 1)
          ✗ cannot post (FAILED - 2)

      TEXT
      expect(output).to include("1) User cannot log in", "expected: :rejected", "got: :logged_in")
      expect(output).to include("3 examples, 2 failures")
      expect(output).to include("Failed examples:")
    end

    it "marks pending examples with their reason and keeps RSpec's pending summary" do
      output = run_suite do
        RSpec.describe("User") do
          it("is valid") { expect(1).to eq(1) }
          it "sends a notice"
          it("bans spammers") { pending("not built"); expect(1).to eq(2) }
          it("is skipped", skip: "flaky") { expect(1).to eq(1) }
        end
      end

      expect(progress_output(output)).to eq(<<~TEXT)

        User
          ✓ is valid
          • sends a notice (PENDING: Not yet implemented)
          • bans spammers (PENDING: not built)
          • is skipped (PENDING: flaky)

      TEXT
      expect(output).to include("4 examples, 0 failures, 3 pending")
    end

    it "emits no escape sequences when color is disabled" do
      output = run_suite do
        RSpec.describe("User") do
          it("passes") { expect(1).to eq(1) }
          it("fails") { expect(1).to eq(2) }
          it "is pending"
        end
      end

      expect(output).not_to include("\e")
    end

    it "emits only color sequences, never cursor control, when color is forced" do
      output = run_suite(color: true) do
        RSpec.describe("User") do
          it("passes") { expect(1).to eq(1) }
          it("fails") { expect(1).to eq(2) }
        end
      end

      escape_sequences = output.scan(/\e\[[0-9;]*[A-Za-z]/)
      expect(escape_sequences).not_to be_empty
      expect(escape_sequences).to all(match(/\A\e\[[0-9;]*m\z/))
    end

    it "falls back to ASCII glyphs when the output is not UTF-8" do
      output = run_suite(output: StringIO.new(String.new(encoding: Encoding::US_ASCII))) do
        RSpec.describe("User") do
          it("passes") { expect(1).to eq(1) }
          it("fails") { expect(1).to eq(2) }
          it "is pending"
        end
      end

      expect(progress_output(output)).to eq(<<~TEXT)

        User
          + passes
          x fails (FAILED - 1)
          * is pending (PENDING: Not yet implemented)

      TEXT
    end
  end
end
