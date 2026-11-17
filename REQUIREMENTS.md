# RSpec Collapsing Documentation Formatter

Implement an RSpec formatter that behaves like RSpec's built-in `documentation` formatter, but dynamically collapses completed example groups.

## Goal

The formatter should preserve the main benefit of RSpec's documentation formatter: while the suite is running, it should be easy to see **which spec and context RSpec is currently executing**.

Unlike the documentation formatter, completed contexts should not continue occupying one line per example. Once an example group has finished, replace its expanded output with a single summary line.

The result should feel like a live, hierarchical view of the test suite rather than an append-only log.

## Desired behavior

While an example group is running, display its hierarchy and examples similarly to the documentation formatter.

For example:

```text
User
  when active
    is valid
    can log in
    receives notifications
  when suspended
    is invalid
    cannot log in
```

As soon as `when active` has completed successfully, collapse it:

```text
User
  ✓ when active (3 examples)
  when suspended
    is invalid
    cannot log in
```

When `when suspended` completes:

```text
User
  ✓ when active (3 examples)
  ✓ when suspended (2 examples)
```

When the entire top-level group completes:

```text
✓ User (5 examples)
```

The next top-level group can then expand beneath it:

```text
✓ User (5 examples)

Auction
  bidding
    accepts a higher bid
    rejects a lower bid
    ...
```

Completed top-level groups may remain as single summary lines and naturally scroll off the terminal as the suite progresses.

## Failures

Successful groups should collapse aggressively.

Failures should remain visible.

For example:

```text
User
  ✓ when active (3 examples)
  ✗ when suspended
    ✓ is invalid
    ✗ cannot log in
```

The formatter should retain enough information for the developer to immediately see:

- which example failed;
- the hierarchy containing it;
- the normal RSpec failure information.

Do not sacrifice useful RSpec diagnostics merely to keep the display compact.

Use sensible judgment about exactly how failed groups collapse or remain expanded. The important principle is:

> Successful work disappears into compact summaries; failures remain visible and understandable.

## Pending examples

Pending/skipped examples should be distinguishable from both successes and failures.

A group containing pending examples should not misleadingly appear as an entirely successful group.

Choose an appropriate compact representation.

## Live terminal behavior

This is intentionally a dynamic terminal formatter.

Use ANSI terminal capabilities to rewrite output that has already been displayed. When a context completes, remove/redraw its expanded representation and replace it with the collapsed representation.

Avoid clearing the entire terminal on every update if possible. The output should not visibly flicker during a normal test run.

The implementation should correctly account for:

- nested example groups;
- terminals of different widths;
- long example descriptions;
- output written while specs execute;
- RSpec's final summary and failure output.

It is acceptable for the first implementation to make reasonable simplifying assumptions where terminal behavior becomes complicated, provided those assumptions are documented.

## Non-interactive output

Dynamic cursor manipulation is inappropriate when output is redirected to a file, piped to another process, or otherwise not attached to an interactive terminal.

Detect this situation where practical.

In non-interactive mode, fall back to sensible append-only output. ANSI cursor-control sequences must not corrupt redirected output.

Color should likewise respect RSpec's/color/TTY configuration rather than assuming ANSI color support.

## RSpec integration

Implement this using RSpec's formatter API rather than modifying RSpec itself.

Relevant formatter notifications are likely to include events such as:

- `example_group_started`
- `example_group_finished`
- `example_started`
- `example_passed`
- `example_failed`
- `example_pending`
- `start`
- `start_dump`
- `dump_failures`
- `dump_pending`
- `dump_summary`
- `close`

Do not assume this list is exhaustive or that all of these events must be used. Consult the current RSpec formatter API and use the smallest appropriate set.

The formatter will probably need an in-memory representation of the currently executing group hierarchy so that it can redraw portions of the tree when groups finish.

## Example counts

Collapsed groups should show the number of examples they contain:

```text
✓ validations (7 examples)
```

Use singular grammar where appropriate:

```text
✓ some context (1 example)
```

Counts should include nested examples where that makes the hierarchy intuitive.

If pending or failed examples make a single count ambiguous, a compact breakdown is acceptable, for example:

```text
✗ validations (6 passed, 1 failed)
```

The exact presentation can evolve during implementation.

## Compatibility

Target the current RSpec 3.x formatter API.

Avoid depending unnecessarily on RSpec internals. Prefer public formatter APIs so that the formatter has a reasonable chance of continuing to work across RSpec releases.

The formatter should be usable in the normal RSpec way, e.g.:

```text
rspec --format SomeFormatter
```

and via `.rspec`.

## Scope

Start small.

The first useful version needs to:

1. display the currently executing hierarchy;
2. display examples as they execute;
3. collapse successful groups when they finish;
4. preserve failed examples/groups;
5. show RSpec's normal useful failure information and final summary;
6. avoid emitting terminal-control garbage when output is non-interactive.

Do **not** build a full-screen TUI, interactive controls, keyboard handling, configuration framework, or elaborate theming system.

This should remain recognizably an **RSpec formatter**, just one that takes advantage of a modern terminal.

## Tests

Add automated tests for the formatter.

At minimum, cover:

- a successful top-level group;
- nested successful groups;
- multiple sibling contexts;
- failed examples;
- pending examples;
- mixed success/failure within a group;
- singular/plural example counts;
- non-TTY output.

Keep terminal rendering logic sufficiently separated from RSpec event handling that it can be tested without requiring a real interactive terminal for every case.

Where useful, model rendering as transformations from formatter state to terminal output rather than coupling all state changes directly to `$stdout`.

## Design preference

Favor a small design with clear responsibilities.

A likely separation is:

```text
RSpec events
    ↓
formatter/state
    ↓
tree of groups/examples
    ↓
renderer
    ↓
terminal output
```

This is a suggestion rather than a required class structure.

In particular, avoid spreading ANSI cursor bookkeeping throughout the RSpec event-handling code.

## UX principle

The formatter should answer two questions at a glance while a suite is running:

**What has already completed?**

and, more importantly:

**What is RSpec doing right now?**

RSpec's documentation formatter already answers the second question well, but becomes increasingly noisy as the suite progresses. This formatter should retain that contextual information while progressively compressing completed work.
