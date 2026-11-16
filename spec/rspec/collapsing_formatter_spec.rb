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

    it "uses descriptions that RSpec generates after an example has run" do
      output = run_suite do
        RSpec.describe("User") do
          subject { 1 }
          it { is_expected.to eq(1) }
        end
      end

      expect(progress_output(output)).to include("  ✓ is expected to eq 1\n")
    end

    it "marks every example as failed when a before(:context) hook fails" do
      output = run_suite do
        RSpec.describe("User") do
          before(:context) { raise "database unavailable" }
          it("is valid") { expect(1).to eq(1) }
          it("can log in") { expect(1).to eq(1) }
        end
      end

      expect(progress_output(output)).to eq(<<~TEXT)

        User
          ✗ is valid (FAILED - 1)
          ✗ can log in (FAILED - 2)

      TEXT
      expect(output).to include("database unavailable")
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

  context "with an interactive terminal" do
    let(:tty) { FakeTTY.new(rows: 30, columns: 80) }

    before { stub_const("ENV", ENV.to_h.merge("TERM" => "xterm-256color")) }

    # The tree part of the screen: everything above RSpec's pending/failure/summary dump.
    def tree_on_screen
      tty.terminal.transcript.take_while { |line| !line.match?(/\A(Pending:|Failures:|Finished in)/) }
    end

    it "redraws the tree as examples run and groups finish" do
      snapshots = []
      screen = -> { snapshots << tty.terminal.lines }

      run_suite(output: tty) do
        RSpec.describe("User") do
          context("when active") do
            it("is valid") { screen.call }
            it("can log in") { expect(1).to eq(1) }
          end
          context("when suspended") do
            it("is invalid") { screen.call }
          end
        end
        RSpec.describe("Auction") do
          it("accepts bids") { screen.call }
        end
      end

      expect(snapshots).to eq([
                                ["", "User", "  when active", "    ▸ is valid"],
                                ["", "User", "  ✓ when active (2 examples)", "  when suspended", "    ▸ is invalid"],
                                ["", "✓ User (3 examples)", "", "Auction", "  ▸ accepts bids"]
                              ])
      expect(tree_on_screen).to eq(["", "✓ User (3 examples)", "✓ Auction (1 example)", ""])
    end

    it "keeps failed groups expanded and prints RSpec's failure output below the tree" do
      run_suite(output: tty) do
        RSpec.describe("User") do
          context("when active") do
            it("is valid") { expect(1).to eq(1) }
          end
          context("when suspended") do
            it("cannot log in") { expect(:logged_in).to eq(:rejected) }
            it "sends a notice"
          end
        end
      end

      expect(tree_on_screen).to eq([
                                     "",
                                     "✗ User (1 passed, 1 failed, 1 pending)",
                                     "  ✓ when active (1 example)",
                                     "  ✗ when suspended (1 failed, 1 pending)",
                                     "    ✗ cannot log in (FAILED - 1)",
                                     "    • sends a notice (PENDING: Not yet implemented)",
                                     ""
                                   ])
      expect(tty.terminal.transcript).to include("  1) User when suspended cannot log in")
      expect(tty.terminal.transcript).to include("3 examples, 1 failure, 1 pending")
    end

    it "shows where the run stopped with --fail-fast, hiding groups that never ran" do
      run_suite(output: tty, fail_fast: 1) do
        RSpec.describe("User") do
          it("is valid") { expect(1).to eq(1) }
          it("can log in") { expect(1).to eq(2) }
          it("is never run") { expect(1).to eq(1) }
        end
        RSpec.describe("Auction") { it("is never run") { expect(1).to eq(1) } }
      end

      expect(tree_on_screen).to eq(["", "✗ User (1 passed, 1 failed)", "  ✓ is valid", "  ✗ can log in (FAILED - 1)", ""])
      expect(tty.terminal.transcript).to include("2 examples, 1 failure")
    end

    it "uses append-only output when TERM is dumb" do
      stub_const("ENV", ENV.to_h.merge("TERM" => "dumb"))

      output = run_suite(output: tty) do
        RSpec.describe("User") { it("is valid") { expect(1).to eq(1) } }
      end

      expect(progress_output(output)).to eq("\nUser\n  ✓ is valid\n\n")
    end
  end
end
