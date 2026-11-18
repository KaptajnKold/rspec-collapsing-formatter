# Implementation Plan: RSpec Collapsing Documentation Formatter

See `REQUIREMENTS.md` for the requirements. This document describes how we meet them.

## 1. Project shape

A small gem, `rspec-collapsing-formatter`.

```
lib/rspec/collapsing_formatter.rb                # RSpec-facing formatter (events → tree → output)
lib/rspec/collapsing_formatter/tree.rb           # GroupNode / ExampleNode, status + counts
lib/rspec/collapsing_formatter/layout.rb         # pure: tree → [Line] (text + style), given width
lib/rspec/collapsing_formatter/live_output.rb    # TTY: diffs frames, rewrites screen with ANSI
lib/rspec/collapsing_formatter/stream_output.rb  # non-TTY: append-only output
spec/support/virtual_terminal.rb                 # tiny ANSI interpreter for tests
spec/fixtures/*.rb                               # sample suites for end-to-end runs
```

Usage:

```text
rspec --require rspec/collapsing_formatter --format RSpec::CollapsingFormatter
```

or the same two lines in `.rspec`.

Data flow: **events → tree → layout → output**. Only the output classes know about
terminals; only `LiveOutput` emits cursor-control sequences.

### Dependencies

The formatter is loaded into other projects' test processes, so every runtime dependency
is a potential version conflict with their Gemfile. Keep the list minimal:

| Dependency | Why |
|---|---|
| `rspec-core ~> 3.x` | The formatter API. |
| `unicode-display_width` | Correct column widths (CJK, emoji, combining chars) when truncating lines. A wrong width causes an unexpected wrap, which breaks every subsequent cursor-up count. Already ubiquitous (RuboCop, Reline, tty-*). |
| `io/console` (stdlib) | `IO#winsize`, `tty?`. |

Deliberately **not** used:

- `tty-cursor`: we need about five escape sequences, so we define them as constants.
- `tty-screen`: `io/console`, then `$COLUMNS`, then 80 is enough.
- `pastel`, `rainbow`, etc.: RSpec's `ConsoleCodes` already respects the color configuration.
- `tty-progressbar`, `tty-spinner`: wrong model (fixed bars, not a collapsing tree).
- `curses` and TUI frameworks: excluded by the README (no full-screen TUI).

Prior art worth reading (not depending on): Fuubar, `rspec-instafail`, `nyan-cat-formatter`.

## 2. RSpec integration

- Subclass `RSpec::Core::Formatters::BaseTextFormatter` (public API). It provides the
  standard `dump_failures`, `dump_pending`, `dump_summary`, `seed`, `message`, `close`.
- Register only: `start`, `example_group_started`, `example_group_finished`,
  `example_started`, `example_passed`, `example_failed`, `example_pending`, `message`,
  `start_dump`, `close`.
- Event handlers only mutate the tree and call `output.render(tree)`. No ANSI here.
- `start_dump`: finalize the live region (final redraw, park cursor below it), then let the
  inherited dump methods print RSpec's normal failure/pending/summary output.
- `close` (plus `ensure`/interrupt handling): always leave the cursor on a fresh line and
  restore cursor visibility if it was changed.
- Failure numbers are tracked so failed lines can show `(FAILED - n)`, matching the dump.

## 3. Tree model (`tree.rb`)

- `GroupNode`: description, ordered children (groups and examples), state
  (`running`/`finished`), recursive counts (`passed`, `failed`, `pending`).
- `ExampleNode`: description, status (`running`/`passed`/`failed`/`pending`),
  failure number, pending message.
- The formatter keeps a stack of open groups. Nested and shared-example groups need no
  special handling.
- Groups that finish with zero examples (e.g. everything filtered) are dropped.

## 4. Display rules (`layout.rb`, pure)

| Situation | Display |
|---|---|
| Running group | Header plus indented children, as in the documentation formatter |
| Running example | `▸ description` in the `:detail` color (RSpec's ConsoleCodes has no "dim"), replaced by its result |
| Finished, all passed | `✓ name (3 examples)` / `(1 example)` |
| Finished, pending but no failures | `• name (6 passed, 1 pending)` in yellow; never looks fully green |
| Finished with any failure | Stays expanded: `✗ name (1 passed, 1 failed)`. Passed subgroups collapse, failed ones expand recursively. Examples show `✓`, `✗ … (FAILED - n)`, `• … (PENDING: reason)` |
| Finished top-level group | Same rules, then committed (see §5) |
| Between top-level groups | A blank line when either neighbor is expanded; collapsed summaries stack directly |

- Colors come from `RSpec::Core::Formatters::ConsoleCodes`, so `--color`, `--no-color`
  and `--force-color` are respected.
- In live mode, lines are truncated to `width - 1` **display columns** (via
  `unicode-display_width`) with an ellipsis, so one logical line is always one physical
  line. Truncation happens on plain text, before color is applied. Full descriptions still
  appear in RSpec's failure output.
- Glyphs fall back to ASCII (`+`, `x`, `*`, `>`, `...`) when the output encoding is not UTF-8.
- Example descriptions are re-read when an example finishes, because RSpec generates
  descriptions such as "is expected to eq 1" only after the example has run.
- Emoji widths vary between `unicode-display_width` 2.x and 3.x (and between terminals).
  2.x over-estimates some sequences, which only cuts lines shorter, so the gem accepts
  `>= 2.4, < 4` to avoid conflicts with apps locked to 2.x. *(Documented simplification.)*

## 5. Live terminal output (`live_output.rb`)

The screen is split into **committed lines** (never touched again) and a **live region**
at the bottom.

- **Diff-based redraw.** Keep the previous frame as an array of lines. For a new frame,
  find the first differing line, move up to it (`CR` + `ESC[nA`), clear to end of screen
  (`ESC[J`), and write the rest. A typical example completion is a one-line rewrite plus
  one appended line. Each frame is written with a single `write` call and never uses a
  full-screen clear, so it does not flicker. Optionally wrap frames in synchronized-output
  mode (DEC 2026).
- **No early commit of failed subtrees.** The original idea was to commit everything up to
  the end of a finished failed subtree. But the headers above it still change when their
  groups finish (`User` becomes `✗ User (3 passed, 1 failed)`), so only finished
  top-level groups are committed, plus whatever does not fit on the screen (below).
- **Live region taller than the terminal.** The live region is limited to `rows - 1` lines,
  since the cursor cannot reach rows that scrolled off the top. Lines above that are
  committed as-is, and the live region then starts at the tree node on its first line.
  If a group whose lines were committed collapses, its summary (and everything after it)
  is appended below; a committed header keeps its running text if its group later fails.
  *(Documented simplification.)*
- **Cost per event.** Only the live region is laid out (from its first node: following
  siblings, then ancestors' following siblings), so a render costs about one screenful
  regardless of group size. Finished groups cache their counts.
- **Size** is re-read on every render (`IO#winsize`, then `$COLUMNS`/`$LINES`, then
  80×24). Already-drawn lines are not reflowed after a resize, and shrinking the window
  below the live region's height can garble it. *(Documented simplification.)*
- **Interrupts.** On the first Ctrl-C, RSpec finishes the current example and dumps as
  usual, so the tree is finalized normally; RSpec's "shutting down" message on `$stderr`
  needs the output proxy below. A second Ctrl-C calls `exit!`; since the cursor is always
  on a fresh line and never hidden, the terminal is left usable. `close` also finishes the
  live region in case `start_dump` is never reached.
- **Output from specs while they run.** In live mode only, `$stdout` and `$stderr` are
  wrapped in a thin proxy during the run. On write, it clears the live region, passes the
  text through, then redraws the live region below it, so stray output appears above the
  tree. Partial lines are buffered until a newline arrives or the next event fires. The
  proxy delegates everything else (`tty?`, `sync`, …). RSpec `message` notifications use
  the same path. Output that subprocesses write directly to the file descriptor (or code
  writes through the `STDOUT`/`STDERR` constants) cannot be intercepted. *(Documented
  simplification.)*
  - Only streams that are terminals are proxied; they are restored at `start_dump`/`close`
    unless something else replaced them in the meantime.
  - Writes and renders share a mutex, since specs may write from other threads.
  - Signal handlers cannot take locks, and may interrupt a render. Text written from one
    (RSpec's "shutting down" message on Ctrl-C) is queued and printed at the next event.

## 6. Non-interactive output (`stream_output.rb`)

- Live mode is used only when `output.tty?` is true and `TERM` is not `dumb`.
- Otherwise output is append-only: group headers when groups start and example lines when
  examples finish (documentation style, with ✓/✗/•). No cursor-control sequences are ever
  emitted, and color follows RSpec's configuration. A hung CI job therefore still shows
  where it stopped.

## 7. Tests

1. **Layout unit tests.** Hand-built trees compared against exact expected lines: pass,
   nested, siblings, fail, pending, mixed, singular/plural, truncation (including wide
   characters), empty groups.
2. **Virtual terminal** (`spec/support/virtual_terminal.rb`). Interprets the sequences
   `LiveOutput` emits (`CR`, `LF`, `ESC[nA`, `ESC[K`, `ESC[J`) into a fixed-size screen
   buffer. Tests assert on what is actually visible after each event.
3. **Formatter integration.** Sandboxed example groups run against a fake-TTY `StringIO`,
   with screen snapshots asserted at each step (while running, after a context collapses,
   after the top-level group collapses).
4. **Non-TTY.** The same suites against a plain `StringIO`: no `\e[` with color disabled,
   and no cursor sequences even with color forced.
5. **End-to-end smoke tests.** `rspec --format …` on fixture specs in a subprocess, once
   redirected to a file and once under Ruby's `PTY`. Assert exit status, final summary and
   failure details.

## 8. Milestones

1. Skeleton: gemspec, `.rspec`, formatter registered, append-only mode working end to end.
2. Tree and layout, with collapse rules and counts, plus unit tests.
3. Live output: diff redraw, virtual terminal, collapse on group finish.
4. Robustness: regions taller than the screen, cost per event, truncation, Ctrl-C and
   `--fail-fast` cleanup.
5. Stray-output proxy and `message` handling.
6. README: usage, screenshots, documented simplifications.
7. Event/display core: a refactor that leaves behavior unchanged and prepares for parallel
   runners (see §10). The existing specs must pass unchanged.
8. parallel_tests adapter, with the event transport.
9. turbo_tests adapter (needs the worker id passed to formatters; upstream change or shim).
10. flatware adapter (needs group events; upstream change).

## 9. Open decisions

- Gem and class name: `rspec-collapsing-formatter` / `RSpec::CollapsingFormatter`.
- Pending glyph and color: `•`, yellow.
- Non-TTY style: documentation style, not summaries only.
- `$stdout`/`$stderr` proxy (the one invasive piece). The alternative is to accept that
  stray output can corrupt the live region.

## 10. Parallel runners

Goal: one live tree for a suite split across several processes, for every popular parallel
runner, starting with parallel_tests. A throwaway prototype showed that
parallel_tests works if one worker draws on stderr, the others send it their events over a
Unix socket, and no worker writes to stdout until the display is finished.

### Layers and the direction of dependencies

Each layer depends only on the layers below it. Nothing below the adapters knows that
parallel runners exist, and nothing below the formatter knows about RSpec notifications.

```
formatter          RSpec notifications → events; picks a role via the runner registry
  │
runners/*          one adapter per runner: detection, roles, runner-specific protocol
  │
transport          events ⇄ JSON lines over a Unix socket (runner-neutral)
  │
display            consumes events for one or more workers → tree → output
  │
tree, layout,      as today, except the tree tracks a position per worker
live/stream output
```

- **Events** are plain value objects: `GroupStarted(description)`, `GroupFinished`,
  `ExampleStarted(description)`, `ExampleFinished(description, status, detail)`,
  `Output(text)` and `WorkerFinished`, each tagged with a worker id. They are the only
  thing the layers exchange. The single-process formatter sends them straight to a
  display in the same process, with worker id 1.
- **Display** owns the tree and the output and applies events to them. It doesn't know
  where events come from: the formatter in the same process, a socket, or a runner's
  parent process.
- **Tree** keeps a separate stack of open groups and a running example for each worker,
  and a single list of top-level groups. With one worker it behaves as it does today.
- **Layout and the outputs** gain support for several running top-level groups, the
  budget that divides the screen between them, and the compact one-line-per-worker
  mode. They never see worker ids or runner names.
- **Transport** turns events into JSON lines over a socket, plus the control messages
  `go` and `done` for holding back each worker's dump. Any runner whose workers can't
  hand events to a parent process can reuse it.
- **Runner adapters** live in `lib/rspec/collapsing_formatter/runners/`, one file each.
  An adapter answers `detect(env)` and returns the role for this process: `:solo`,
  `:coordinator` or `:worker`. It also supplies the runner-specific details: where the
  socket lives, how many workers to expect, and which process coordinates.
  - parallel_tests: coordinator and workers, connected by the transport.
  - turbo_tests and flatware: the display runs in the runner's parent process, so no
    transport is needed, only a mapping from the runner's reporter calls to events.
- **Registry** is the only place that lists the adapters and is the only code the
  formatter calls about runners. Adapters are loaded only when needed.

### Rules

- **No runtime dependency on any runner.** Adapters detect their runner from environment
  variables (e.g. `TEST_ENV_NUMBER`, `PARALLEL_TEST_GROUPS`, `PARALLEL_PID_FILE`) and
  never `require` the runner's gem. Runners appear only in the Gemfile's test group, for
  the end-to-end tests.
- **One format name.** Users keep `--format RSpec::CollapsingFormatter`, and the
  registry chooses the role. Runners that configure formatters in their parent process
  (turbo_tests) are the exception, and get whatever entry point they require.
- **Fall back, never fail.** If detection is ambiguous, the coordinator is unreachable, or
  the output is not a terminal, the formatter uses the single-process behavior (or the
  append-only output), as today.
- **Tests per layer.** Display tests feed events from several workers to a virtual
  terminal, with no processes. Transport tests use a socket pair. Every adapter passes a
  shared contract spec, plus an end-to-end run of the real runner under a pseudo-terminal.

### Open questions

- Failure numbers: per worker (`FAILED - 1, worker 3`, matching each worker's own failure
  list), or renumbered by the coordinator, which would then no longer match the dumps.
- `parallel_rspec | tee log`: stderr is still the terminal, so the live tree would appear
  on screen while the dumps go to the log. Keep that, or fall back to append-only output?
- Timeout for a worker that never connects, and a fallback if the coordinator dies.
