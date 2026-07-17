# Bundled ConPTY

Newer Windows ConPTY host binaries (`conpty.dll` + `OpenConsole.exe`) bundled so
that herdr does not depend on the (sometimes outdated and buggy) in-box system
ConPTY exposed by `kernel32.dll`.

## Why

Some in-box ConPTY versions tear down the pseudoconsole when a TUI application
switches to the alternate screen buffer — e.g. an editor launched from Claude
Code (`Ctrl-G`). The pane's shell then dies. Windows Terminal avoids this by
bundling its own newer ConPTY; WezTerm hit and fixed the same class of bug
(wezterm/wezterm#7774). herdr's vendored `portable-pty` loads this bundled pair
from the executable's own directory (see local patch
`vendor/patches/portable-pty/0001-prefer-bundled-conpty.patch`, herdr #761) and
falls back to the system ConPTY when the pair is absent.

`build.rs` copies `vendor/conpty/<target>/{conpty.dll,OpenConsole.exe}` next to
the built executable so `cargo build` produces a working layout.

## Source and version

- Package: `Microsoft.Windows.Console.ConPTY` (NuGet)
- Version: `1.24.260710001`
- Upstream: https://github.com/microsoft/terminal
- License: MIT (see `LICENSE` in this directory)

`conpty.dll` and `OpenConsole.exe` are a matched pair and must be updated
together. To update, download the NuGet package and copy the arch-specific
`runtimes/win-<arch>/native/conpty.dll` and
`build/native/runtimes/<arch>/OpenConsole.exe` into
`vendor/conpty/<rust-target-triple>/`.

## Contents

- `x86_64-pc-windows-msvc/conpty.dll`
- `x86_64-pc-windows-msvc/OpenConsole.exe`
