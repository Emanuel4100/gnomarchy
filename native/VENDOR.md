# Vendored source: hyprbars

`gnomarchy-bars/vendor/` is the official **hyprbars** plugin from
[`hyprwm/hyprland-plugins`](https://github.com/hyprwm/hyprland-plugins), copied verbatim except for
one tiny, clearly-marked hook in `main.cpp` (see below). License: BSD-3-Clause, copied verbatim to
`native/LICENSE-hyprbars`.

## Pinned commit

- Repo: `https://github.com/hyprwm/hyprland-plugins`
- Commit: `81516add9b432b6ffc9f0906b92c9302c479c236` ("csgo-vk-fix,hyprbars: chase hyprland (#689)",
  2026-07-26)
- Pinned on: 2026-09-14, against Hyprland `0.56.2` (`efb50993780079460b0cbed1363e2166a2de1d9f`,
  built 2026-08-05)

**This is deliberately not upstream's `main` HEAD.** hyprbars' `main` branch chases Hyprland's own
unstable internal header layout day-to-day, and its internal include paths drift between commits even
within a single Hyprland point release. At implementation time, upstream `main`
(`722f15a77768eab13f01f5e5dce024bd2f61f270`, 2026-09-05) expected
`hyprland/src/desktop/view/window/Window.hpp` (nested) and a newer-still `keybinds/Manager.hpp`
layout, neither of which exist in this machine's installed Hyprland 0.56.2 headers (which use the
flatter `desktop/view/Window.hpp` and `managers/KeybindManager.hpp`). Commit `81516add` was the most
recent hyprbars commit whose full include list matches exactly what's installed under
`/usr/include/hyprland` on this machine — verified by checking every header it includes exists there
before building. It compiled cleanly with zero further source changes needed.

## The one intentional deviation from "byte-for-byte unmodified"

`vendor/main.cpp` has two small, clearly-marked additions (search for `gnomarchy: phase 2 snap hook`):
1. `#include "../patch/snap.hpp"` near the top, alongside the existing local includes.
2. One call each to `gnomarchySnapInit()` (end of `PLUGIN_INIT`, after `HyprlandAPI::reloadConfig()`)
   and `gnomarchySnapExit()` (start of `PLUGIN_EXIT`).

Everything else in `vendor/` — `barDeco.hpp/.cpp`, `BarPassElement.hpp/.cpp`, `globals.hpp`, and the
rest of `main.cpp` — is untouched upstream source. `patch/snap.{hpp,cpp}` are new files, entirely
ours, and never touch hyprbars' internals: they only use Hyprland core's own public drag-state API
(`g_layoutManager->dragController()`), which is independent of anything hyprbars itself does.

## Re-syncing to a newer upstream commit later

1. Pick a commit from `hyprwm/hyprland-plugins`' history whose full include list actually matches
   the Hyprland version you're building against (don't assume `main` HEAD works — check each header
   path exists under `/usr/include/hyprland` first, the way this pin was chosen).
2. Copy `main.cpp`, `barDeco.{hpp,cpp}`, `BarPassElement.{hpp,cpp}`, `globals.hpp` from that commit
   into `vendor/`, overwriting the old ones.
3. Reapply the two-line hook described above (`grep` the old `main.cpp` for
   `gnomarchy: phase 2 snap hook` to see exactly what to reapply).
4. `make -C gnomarchy-bars clean && make -C gnomarchy-bars TARGET=<path>` and fix any new compile
   errors the newer commit introduces.
5. Update this file's pinned commit SHA/date.
