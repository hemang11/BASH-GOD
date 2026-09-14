# BASH_GOD Terminal Runtime Architecture

**Status:** Current implementation contract for interactive reviewed execution.

## Context / Problem

The original shell-only picker had to parse terminal escape sequences, redraw partial screens, hand
off to a command editor, preserve signals, and return control to a running native child. That is a
high-risk boundary: a visually correct picker can still leave a terminal stuck, leak key bytes, or
lose Ctrl-C.

BASH_GOD uses a small compiled terminal helper for browse-mode interaction while retaining shell
ownership of commands, values, editing, and child execution. This keeps the terminal layer focused
and prevents it from becoming a second operational runtime.

## Goals

- Keep browse mode inline in the caller's existing terminal buffer.
- Make rapid and split navigation keys, Escape, Ctrl-C, and resize handling predictable.
- Show the selected, wrapped resolved command without exposing execution templates to the UI helper.
- Return to normal command-line editing when the operator asks to edit.
- Preserve native child stdout, stderr, exit status, and signals.
- Fall back safely to static results when interactive capability is unavailable.

## Non-goals

- Run catalog commands from Go or from the picker.
- Replace the operator's normal shell editor.
- Use a full-screen alternate terminal UI.
- Turn the helper into a dependency for static catalog browsing.
- Claim universal parity across every terminal emulator, SSH configuration, or future platform.

## Architecture Overview

```text
Bash interaction coordinator
          │ prepared display rows + lazy detail requests
          ▼
src/ui/tui.sh  ── BGTUI/1 protocol ──► cmd/god-tui / internal/tui
          │                                  │
          │ RUN | EDIT | CANCEL              │ owns terminal only while browsing
          ▼                                  ▼
  restore terminal and caller traps      inline list + wrapped detail panel
          │
   ┌──────┴────────────┐
   ▼                   ▼
normal editor      reviewed native child
src/ui/input.sh    src/execute.sh
```

## Key Components

| Component | Responsibility |
|---|---|
| `src/interaction.sh` | Builds stable eligible picker rows, prepares the highlighted model lazily, and rechecks it before handoff. |
| `src/ui/tui.sh` | Locates a compatible helper, manages protocol pipes, validates result data, and saves/restores terminal and trap state. |
| `cmd/god-tui`, `internal/tui` | Inline Bubble Tea picker, key normalization, width-aware rendering, lazy detail display, and bounded protocol codec. |
| `src/ui/input.sh` | Opens the terminal only after helper exit and seeds normal readline editing with the selected command. |
| `src/resolve.sh` | Supplies the reviewed model, placeholders, Target substitutions, and display command as tagged data. |
| `src/execute.sh` | Validates the final model and gives its child the controlling terminal. |
| `packaging/` | Builds, installs, verifies, and locates the matching native helper for supported release artifacts. |

## Flow / Behavior

### Browse lifecycle

The helper receives display-only rows through the versioned `BGTUI/1` bridge. Records are bounded,
UTF-8-safe fields encoded for unambiguous transport. The initial selected row includes a prepared
detail panel; later highlights can request lazy detail by immutable row index. The helper never
receives executable templates or positional values.

It returns exactly one bounded action: `RUN`, `EDIT`, or `CANCEL`, plus a selected row index. The
shell validates the action and index against its own current row set. A helper failure, invalid
protocol record, unsupported capability, non-TTY output, or terminal too narrow for stable rendering
causes static search output rather than an implicit selection.

### Terminal ownership

While browsing, the helper is the only process reading and painting the controlling TTY. Before it
starts, the adapter snapshots terminal state and caller traps. Every normal, failed, cancelled, or
signalled exit closes protocol pipes, reaps the helper, restores the terminal snapshot, and restores
the caller's trap state.

Only after that restoration may BASH_GOD open a native editor or start a native child. `e` returns to
normal command-line editing with the displayed command prefilled; it does not implement a custom
editor. Any edited command that retains an unresolved placeholder is refused before child launch.
The adapter keeps the picker result in caller-owned shell state rather than passing it through a
command-substitution subshell, so the native editor and child retain the original controlling TTY.
Descriptor cleanup suppresses only its own close errors; native stdout and stderr remain visible.

### Execution lifecycle

Enter reuses the exact reviewed model shown for the selected row. The coordinator rechecks dynamic
eligibility, resolves remaining placeholders in the same terminal flow, validates the model, then
launches the native child. Child stdin, stdout, and stderr share the controlling terminal, so native
output streams directly and Ctrl-C reaches the child as it would from the operator's shell.

### Presentation and fallback

The picker does not enter an alternate screen. It keeps the BASH_GOD search header, lists concise
titles, highlights one row, and renders a wrapped `$ command` panel for that row. Normal modes stay
quiet; safety and known compatibility status remain visible.

Static `MATCHING OPERATIONS` is the intended fallback for unsupported terminals, unresolved clients,
no eligible rows, redirects, missing helpers, and protocol failure. It is a safe way to browse and
copy command knowledge without claiming executable capability.

## Extensibility / How to change it

- Keep protocol changes versioned and bounded. Update both the Go codec and shell adapter together.
- Keep Go presentation-only. New command semantics, values, discovery facts, and eligibility rules
  belong in shared shell modules and catalog metadata.
- Add synthetic PTY coverage before changing keyboard, signal, editing, or child ownership behavior.
- Package helper artifacts with their launcher and test the installed launcher, not only a source
  checkout.

## Verification

- Go unit tests and vet cover the picker model and protocol codec.
- Adapter smoke tests cover malformed results, lazy detail, unsupported helpers, and static fallback.
- PTY smoke tests use synthetic rows and children to exercise split escape sequences, repeated keys,
  Escape, Ctrl-C, resize, terminal restoration, normal editor handoff, placeholder prompts, stderr,
  and child signal propagation.
- `docs/demo/capture-interactive-picker.sh` drives the real helper through the public fixture flow:
  navigate, edit, resolve a placeholder, and receive fake child stdout and stderr without contacting
  a service. The README SVG uses the same fixture vocabulary.
- Package/install tests prove the staged launcher can locate a compatible helper without a Go
  toolchain.
- The release workflow runs the terminal and installed-artifact suites on every supported target;
  passing target evidence is required before claiming platform parity.

## Limitations / Risks

- Terminal behavior still depends on the terminal emulator, multiplexers, SSH transport, and shell
  configuration. The suite can cover supported environments, not every combination.
- A static fallback has no interactive selection by design; the operator copies or runs the shown
  native command directly.
- The helper is deliberately bounded to a concise result set and display payload so a malformed or
  unexpectedly large catalog cannot consume the terminal protocol unboundedly.
- Native child behavior remains owned by the underlying tool. BASH_GOD preserves its terminal and
  status semantics but cannot make a long-running or misconfigured command succeed.
