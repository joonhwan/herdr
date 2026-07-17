# portable-pty local patches

This file tracks intentional local changes applied on top of the vendored
`portable-pty` source. Remove a patch only when the upstream crate contains an
equivalent fix or exposes an option that lets Herdr keep the same behavior.

## 0001 prefer bundled ConPTY next to the executable

status: active

patch: `vendor/patches/portable-pty/0001-prefer-bundled-conpty.patch`

herdr issue: https://github.com/ogulcancelik/herdr/issues/761

upstream discussion: none found

upstream pr: none

vendored base: `portable-pty 0.9.0`

local files:

- `vendor/portable-pty/src/win/psuedocon.rs`

reason: `portable-pty` probes a bare `conpty.dll` via the DLL search path after
verifying that `kernel32.dll` exports the ConPTY API. Loading a bare name can
pull in another application's `conpty.dll` from `PATH`/`CWD` (issue #761). Some
in-box system ConPTY versions also tear down the pseudoconsole when a TUI app
enters the alternate screen buffer (for example an editor launched from Claude
Code), which kills the pane's shell. This patch instead loads a `conpty.dll`
bundled next to the herdr executable, resolved from the executable's own
directory (a trusted absolute path, never `PATH`/`CWD`), and falls back to the
system ConPTY (`kernel32`) when the bundled pair is absent. The bundled
`conpty.dll` + `OpenConsole.exe` pair lives under `vendor/conpty/<target>/` and
is copied next to the built binary by `build.rs`.

remove when: upstream `portable-pty` exposes a way to load ConPTY from a
specific trusted path, or Herdr replaces the Windows PTY backend.

verification:

```sh
python3 -m unittest scripts.test_vendor_portable_pty
```

On Windows, also verify that pane creation succeeds and that launching a
full-screen editor from a TUI (e.g. Claude Code `Ctrl-G`) no longer kills the
pane.

## 0002 expose Windows raw command tails

status: active

patch: `vendor/patches/portable-pty/0002-windows-raw-command-tail.patch`

herdr issue: https://github.com/ogulcancelik/herdr/issues/1041

upstream discussion: none

upstream pr: none

vendored base: `portable-pty 0.9.0`

local files:

- `vendor/portable-pty/src/cmdbuilder.rs`

reason: Herdr needs to launch `cmd.exe /d /c` with the user-authored command
tail parsed as shell text. `portable-pty` represents commands as argv and
ArgvQuote escapes embedded quotes, which changes how `cmd.exe` parses the raw
command string.

remove when: upstream `portable-pty` exposes Windows raw command-line tail
support or Herdr replaces this launch path.

verification:

```sh
python3 -m unittest scripts.test_vendor_portable_pty
```

On Windows, also run `cargo test raw_arg_appends_unescaped_windows_command_tail`.
