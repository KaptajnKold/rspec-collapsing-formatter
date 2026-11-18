# rspec-collapsing-formatter

An RSpec formatter that works like the built-in `documentation` formatter, but collapses
each example group into a one-line summary as soon as it finishes. Failures stay expanded.

While the suite runs you can see exactly which group and example RSpec is executing, but
finished work no longer takes up one line per example.

## What it looks like

While a suite is running, the current group is expanded as in the documentation
formatter, and `▸` marks the example that is running:

```text
User
  ✓ when active (3 examples)
  when suspended
    ✓ is invalid
    ▸ cannot log in
```

Finished groups collapse to a summary line. A group with a failure stays expanded, so the
failed example is shown in context; its successful subgroups still collapse:

```text
✗ User (4 passed, 1 failed, 1 pending)
  ✓ when active (3 examples)
  ✗ when suspended (1 passed, 1 failed, 1 pending)
    ✓ is invalid
    ✗ cannot log in (FAILED - 1)
    • sends a notice (PENDING: mailer not wired up)
audit: bid of 90 rejected

✓ Auction (3 examples)
```

(`audit: …` was printed by a spec. See [Output from specs](#output-from-specs).)

RSpec's usual pending, failure and summary output then follows, unchanged:

```text
Failures:

  1) User when suspended cannot log in
     Failure/Error: it("cannot log in") { expect(:logged_in).to eq(:rejected) }

       expected: :rejected
            got: :logged_in
     …

9 examples, 1 failure, 1 pending
```

The `(FAILED - n)` numbers match the numbers in that failure list.

## Installation

Add it to your Gemfile:

```ruby
group :test do
  gem "rspec-collapsing-formatter"
end
```

or install it with `gem install rspec-collapsing-formatter`.

It requires Ruby 3.1 or later and rspec-core 3.10 or later. Its only other dependency is
`unicode-display_width` (2.4 up to 4), to measure line widths. It is tested on Ruby 3.1
and 3.4, with rspec-core 3.10 and 3.13 and `unicode-display_width` 2.x and 3.x.

## Usage

```sh
bundle exec rspec --format RSpec::CollapsingFormatter
```

No `--require` is needed: RSpec loads the formatter from its constant name. To make it the
default, add this to `.rspec`:

```text
--format RSpec::CollapsingFormatter
```

## Display

| Line | Meaning |
|---|---|
| `▸ description` | Example currently running |
| `✓ description` | Passed example |
| `✗ description (FAILED - 1)` | Failed example, numbered as in RSpec's failure list |
| `• description (PENDING: reason)` | Pending or skipped example |
| `✓ group (3 examples)` | Finished group in which everything passed |
| `• group (6 passed, 1 pending)` | Finished group with pending examples but no failures; collapsed, in yellow |
| `✗ group (1 passed, 1 failed)` | Finished group with a failure; stays expanded |

- Counts include examples in nested groups.
- Groups in which no examples ran, e.g. because of filters or `--fail-fast`, are hidden.
- Collapsed top-level groups are listed one after another. A blank line separates a
  top-level group from its neighbors when either of them is expanded.
- If the output encoding is not UTF-8, the symbols fall back to `+`, `x`, `*`, `>` and
  `...`.
- Colors follow RSpec's color settings (`--color`, `--no-color`, `--force-color`) and
  roles (`success_color`, `failure_color`, `pending_color`, `detail_color`).

## Interactive and non-interactive output

When the output is a terminal (and `TERM` is not `dumb`), the formatter redraws the tree in
place. It rewrites only the lines that changed, without clearing the screen, so it does
not flicker. Typically that is one line per example, plus a few when a group collapses.
Lines are cut to the terminal width with `…`, so a long description never wraps; the full
description is still shown in RSpec's failure output.

When the output is redirected to a file, piped, or not a terminal for any other reason,
the formatter falls back to append-only output in the style of the documentation
formatter, and never writes cursor-control sequences:

```text
User
  when active
    ✓ is valid
    ✓ can log in
    ✓ receives notifications
  when suspended
    ✓ is invalid
    ✗ cannot log in (FAILED - 1)
    • sends a notice (PENDING: mailer not wired up)
```

Nothing collapses in this mode, so a log of a hung CI job still shows where it stopped.

## Output from specs

In interactive mode, `$stdout` and `$stderr` are replaced by thin proxies for the duration
of the run. Anything a spec writes there, via `puts`, `warn`, a logger and so on, is printed
above the tree, and the tree is redrawn below it. RSpec's own messages, such as
`Run options: …` or the notice printed on Ctrl-C, take the same path. A line printed
without a newline (`print "."`) waits until the newline arrives or the next example
starts or finishes.

The proxies pass everything else (`tty?`, `sync`, `winsize`, …) through to the real streams.
The real streams are restored before RSpec prints its summary.

## Parallel runs

With [parallel_tests](https://github.com/grosser/parallel_tests), the formatter shows the
progress of every process in one tree. No configuration is needed beyond the usual
`--format RSpec::CollapsingFormatter`:

```sh
bundle exec parallel_rspec -n 4
```

Each process's running group is expanded at the same time, and finished groups collapse
above them in the order they finish:

```text
✓ Bid (12 examples)
✓ Search (13 examples)

Auction
  ✗ rejects low bids (FAILED - 1, worker 3)
  ✓ when active (4 examples)
  when suspended
    ▸ does thing 2

Catalog
  ✓ when active (4 examples)
  when suspended
    ✓ does thing 1
    ▸ does thing 3
```

When the running groups don't fit on the screen, each is reduced to the path to its
running example, and if that doesn't fit either, to one line:

```text
Auction › when active › ▸ does thing 3
Catalog › when suspended › ▸ does thing 2
```

Each process still prints its own failure list and summary, one process after the other,
once the tree is complete; parallel_tests then adds up the totals as usual. Failures are
numbered per process, so `(FAILED - 1, worker 3)` refers to failure 1 in the list printed
by process 3.

How it works: the first process draws the tree on stderr, which parallel_tests leaves
connected to the terminal, and the other processes send it their progress over a Unix
socket. No process writes to stdout until the tree is complete, since parallel_tests
copies each process's stdout to the terminal as it arrives.

Each process falls back to the normal behavior if it can't take part: when stderr is not
a terminal (as in CI, or with `--combine-stderr`), or when it can't reach the first
process within 30 seconds.

Support for other parallel runners (turbo_tests, flatware) is planned.

## Limitations

The first version makes these simplifying assumptions where terminal behavior gets
complicated:

- **Output that bypasses `$stdout`/`$stderr` can corrupt the tree.** That includes output
  from subprocesses that write to the inherited file descriptors, and code that writes to
  the `STDOUT`/`STDERR` constants. The next redraw then overwrites some of that output or
  leaves stale lines behind.
- **Groups taller than the terminal.** The cursor cannot move into rows that have scrolled
  off the top, so those lines are final once they scroll away. If such a group later
  collapses, its summary is printed below the lines that can no longer be changed. If it
  fails, its header keeps its plain running text instead of `✗ … (counts)`.
- **Resizing.** The terminal size is read on every redraw, but lines already drawn are not
  reflowed. Making the window shorter than the expanded part of the tree can garble it
  until the current top-level group finishes.
- **Ctrl-C.** RSpec's first interrupt lets the current example finish, so its "shutting
  down" notice appears after that example, and the tree is completed normally. A second
  Ctrl-C makes RSpec exit immediately, which leaves the tree as it was, with the cursor
  on a fresh line.
- **Wide characters.** Emoji widths differ between versions of `unicode-display_width` and
  between terminals. If they disagree, a line can be cut a little short, or in rare cases
  wrap.
- **Parallel runs:**
  - Output that bypasses `$stdout`/`$stderr` in any process can corrupt the tree, as above.
  - If the first process crashes, the tree stops updating; the other processes still
    print their results when they finish.
  - parallel_tests' `--test-file-limit` option, which runs several RSpec processes one
    after another for each worker, is not supported.
  - With only stdout redirected (`parallel_rspec | tee log`), the tree still appears on the
    terminal, and the log gets each process's results.

## Development

```sh
bundle install
bundle exec rspec
```

The design is described in [PLAN.md](PLAN.md), and the original brief is in
[REQUIREMENTS.md](REQUIREMENTS.md). In short, the formatter turns RSpec notifications into
events (`events.rb`), and a display (`display.rb`) applies them to a tree (`tree.rb`).
`layout.rb` turns the tree into lines without any IO, and `live_output.rb` or
`stream_output.rb` writes them. Only `live_output.rb` knows about cursor movement. For
parallel runs, `runners/` detects the runner, `parallel.rb` holds the coordinator and
worker roles, and `transport.rb` carries events between processes.

Most tests run without a real terminal. `spec/support/virtual_terminal.rb` is a small
terminal emulator that interprets the bytes the formatter writes, so specs can assert on
what would be visible on screen. It raises on any escape sequence it does not know. The
end-to-end tests run RSpec in a subprocess, both through a pipe and under a real
pseudo-terminal.

## License

MIT. See [LICENSE](LICENSE).
