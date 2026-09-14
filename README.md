# Gnomarchy

GNOME + Omarchy. A bottom auto-hide dock with pinned + running apps, and a
service that keeps one spare workspace past the highest occupied one — the
two pieces of GNOME's desktop feel that Omarchy doesn't ship on its own,
packaged as one Omarchy 4 (Hyprland + Quickshell) plugin.

![preview](preview.png)

## Install (Omarchy)

```bash
omarchy plugin add https://github.com/Emanuel4100/gnomarchy.git --enable
```

Verify with `omarchy plugin list` — it should show up as
`emanuel.gnomarchy`, enabled.

## The dock

This is the `panel` half of the plugin (not `bar`), so it runs alongside
your existing top bar rather than replacing it.

- **One constant-size layer-shell surface per screen.** It never resizes —
  only the visible pill inside it slides via an animated
  `anchors.bottomMargin`. Resizing the surface itself on every show/hide
  round-trips through the compositor and is what makes a naively-built
  auto-hide dock feel janky.
- **Input region (`mask`) lists each interactive piece** (the hover strip,
  the pill, the context menu) via Quickshell's `Region` API, so the empty
  space around them stays click-through to whatever is underneath.
- **Fully event-driven show/hide, zero polling.** A `HoverHandler` on the
  hairline strip and on the pill itself drives a single-shot hide timer —
  no `hyprctl cursorpos` polling loop.
- **Visibility follows the workspace, GNOME-style**: an empty workspace
  shows the dock automatically (nothing to do but launch something); a
  workspace with windows on it hides the dock after you stop hovering it.
  This comes from `Hyprland.toplevels` (already a live reactive model)
  re-checked only on the Hyprland events that could change the answer, not
  a poll either.

Apps come from two sources, matched by window class:

- **Pinned** apps (`pinnedApps` in settings) always appear, in order,
  resolved to a `.desktop` entry via Quickshell's `DesktopEntries` singleton.
- **Running** apps not already pinned are appended after them, one entry per
  distinct window class, with a small dot indicator. Window ↔ desktop-entry
  matching uses each `Hyprland.toplevels` entry's raw `class`/`initialClass`
  against `DesktopEntries.byId`/`heuristicLookup`.

A trailing **apps button** (grid glyph, after a thin divider) opens
Omarchy's own native apps-grid surface —
`Quickshell.execDetached(["omarchy-menu", "toggle", "apps"])`, the same
thing `SUPER+ALT+SPACE` does — rather than building a second, redundant
app-grid overlay.

Click behavior mirrors GNOME's dash: not running → launch; one window →
focus it, or **minimize/restore** if it's already focused (moved to a
hidden `special:dock_minimize` workspace, since Hyprland has no native
minimize); several windows → cycle to the next one that isn't minimized.
Right-click opens New Window / Add-or-Remove Favorite / Quit. Dragging a
pinned icon horizontally reorders it (unpinned running apps aren't
draggable — pin them first via the context menu, same as GNOME).

## Dynamic workspaces

This is the `service` half of the plugin — headless, no UI, no settings.

Keeps exactly one empty spare workspace past whichever numbered workspace is
currently the highest occupied one — GNOME's "there's always one more
workspace waiting" feel, adapted to Hyprland's numbered-workspace model.

Hyprland already destroys a non-persistent empty workspace the moment it's
both empty and unfocused, so the removal half of "dynamic workspaces" needs
nothing from this plugin. It only handles the creation half: whenever the
highest occupied workspace changes, it marks `(highest occupied) + 1` as
`persistent:true` via `hyprctl eval 'hl.workspace_rule({workspace="N",
persistent=true})'`, which eagerly instantiates that workspace with no
window and no focus change, then clears the previous spare's persistent
flag so Hyprland's own default cleanup can reclaim it if it's still empty.
The spare never goes past workspace 10, since only workspaces 1-10 have a
dedicated `SUPER+<key>` bind in Omarchy's default Hyprland config.

**Known limitation**: global, not per-monitor — the "highest occupied"
count spans every monitor, not each one independently.

## GNOME mode

One switch for everything in this plugin, plus the two GNOME-feel touches
that live outside it (Hyprland tiling, GTK header-bar buttons):

```bash
omarchy-gnomarchy mode on      # enable plugin, GNOME tiling, GTK buttons
omarchy-gnomarchy mode off     # disable plugin, revert tiling + GTK buttons
omarchy-gnomarchy mode toggle
omarchy-gnomarchy mode status  # prints "on" or "off"
```

Each direction touches these together:

1. **The plugin itself** — `omarchy plugin enable`/`disable emanuel.gnomarchy`
   (both the dock panel and the workspace service, together).
2. **Hyprland tiling, floating-by-default, and title-bar exceptions** — zero
   gaps/borders, 12px rounding, every window floating by default, and a
   `hyprbars:no_bar` window rule for apps that already draw their own title
   bar — all applied live via `hyprctl eval` (no `omarchy-restart-shell`
   needed) *and* made reload-safe: presence of a marker file
   (`~/.config/omarchy/plugins/emanuel.gnomarchy/.gnome-mode-on`) is what
   [`extras/looknfeel-gnome.lua`](extras/looknfeel-gnome.lua)'s conditional
   block checks, so a real Hyprland config reload respects whatever mode
   was last set instead of always reapplying GNOME values. **One-time setup
   required**: paste that file's content into your own
   `~/.config/hypr/looknfeel.lua` — a plugin has no business silently
   editing a file it doesn't own, so this one step can't be automated, but
   `mode` fully controls it from then on.
3. **The native title-bar/window-snap plugin** — built once (cached under
   this plugin's own `native/build/`) and loaded/unloaded live via
   `hyprctl plugin load`/`unload`. See
   [Native title bars & window snapping](#native-title-bars--window-snapping)
   below.
4. **GTK header-bar buttons** — `gsettings set
   org.gnome.desktop.wm.preferences button-layout` flips between
   `appmenu:minimize,maximize,close` (on) and `appmenu:close` (off, GTK's
   own factory default). Only affects native GTK/libadwaita apps.

### Also reachable from the Omarchy menu

There's no packaged way for a plugin to install a menu entry for itself —
Omarchy's menu is defined by two JSONC files merged at load,
`default/omarchy/omarchy-menu.jsonc` (shipped) and
`~/.config/omarchy/extensions/omarchy-menu.jsonc` (yours), and nothing
auto-writes to the latter. Paste this into your own extensions file for a
`SUPER+SPACE → Trigger → Toggle → GNOME Mode` entry:

```jsonc
"trigger.toggle.gnome-mode": {"icon":"󰀻","label":"GNOME Mode",
  "action":"omarchy-gnomarchy mode toggle"}
```

GNOME Mode is also reachable, alongside the rest of the dock's appearance/behavior
settings, from the [settings window](#settings-window) below.

No `checked` field, matching every other `trigger.toggle.*` entry's shape —
that category is consistently checkmark-free even for stateful toggles
(nightlight, notifications, top-bar visibility). Verified live end to end:
clicking it flips the plugin, Hyprland tiling, and GTK buttons together,
instantly, no restart needed.

## Native title bars & window snapping

While GNOME mode is on, every window gets a real, draggable compositor title
bar (GNOME/Windows-style) — most apps have none by default on Hyprland, since
Hyprland (like every wlroots compositor) draws no window decoration itself;
only GTK/libadwaita apps draw their own ("client-side decoration"). This is
provided by vendoring the official
[hyprbars](https://github.com/hyprwm/hyprland-plugins/tree/main/hyprbars)
plugin's source (BSD-3-Clause, see `native/LICENSE-hyprbars` and
`native/VENDOR.md` for the exact upstream commit pinned) under
`native/gnomarchy-bars/vendor/`, compiled with a plain, hand-written
`Makefile` — no `cmake`/`hyprpm` needed, just `g++`, `make`, `pkg-config`,
and the Hyprland headers, which Omarchy's own base install already provides.

**Isolation**: the compiled `gnomarchy-bars.so` lives entirely under this
plugin's own `native/build/` directory (git-ignored, rebuilt on demand). It
is loaded and unloaded purely via live `hyprctl plugin load`/`unload` —
never via `hyprpm`'s usual habit of adding a `plugin =` line to
`hyprland.conf`. No system or user Hyprland config file is ever written by
this feature — the one exception, matching everything else in "GNOME mode",
is the same one-time paste into your own `looknfeel.lua` you've already done
for the tiling look, extended to also float-by-default, apply the `no_bar`
exceptions, and reload the native plugin on a real Hyprland restart.

```bash
omarchy-gnomarchy native build   # (re)build the .so, e.g. after a Hyprland update
omarchy-gnomarchy native status  # "built"/"not built" + "loaded"/"not loaded"
```

`mode on` builds it automatically the first time it's needed and caches an
ABI stamp (the running `hyprctl version` string) alongside the `.so`; if a
later `mode on` finds the stamp stale (Hyprland was updated), it rebuilds
once and retries the load automatically.

**Avoiding double title bars**: GTK/libadwaita apps already draw their own
CSD title bar, so a maintained exceptions list turns hyprbars' bar off for
them via a `hyprbars:no_bar` window rule, seeded from Omarchy's own default
GTK apps — Nautilus (Files), Evince, and GNOME Disks. Extend the list by
editing `NO_BAR_CLASSES` in `bin/omarchy-gnomarchy` (and the matching regex
in `extras/looknfeel-gnome.lua`, for reload-survival) if you add other
CSD-drawing apps to your own setup.

**Floating by default**: while GNOME mode is on, every window floats
instead of Hyprland's automatic dwindle tiling — this is what GNOME/Windows
actually are, floating window managers at heart. Drag a window to a screen
edge, corner, or the top to snap it to a half, quarter, or maximized region
(Windows-11/GNOME-style "Aero Snap"), provided by a small module of this
plugin's own (`native/gnomarchy-bars/patch/`) — not a fork of hyprbars
itself, just a separate listener on Hyprland's own public window-drag-state
API, so it stays compatible with upstream hyprbars without any merge risk.

*(Drag-to-snap ships in a later update to this plugin; the title bars,
floating-by-default, and CSD exceptions above are live today.)*

## Settings

Dock settings only — the workspace service has none. All settings live
entirely in this plugin's own `settings.json`
(`~/.config/omarchy/plugins/emanuel.gnomarchy/settings.json`). The plugin's
only entry in the shared `~/.config/omarchy/shell.json` is the bare
`{"id": "emanuel.gnomarchy"}` enable marker every Omarchy plugin needs.

```bash
omarchy-gnomarchy get <key>
omarchy-gnomarchy set <key> <value>
omarchy-gnomarchy toggle <key>          # enabled or pinned only
omarchy-gnomarchy pin <desktop-id>
omarchy-gnomarchy unpin <desktop-id>
omarchy-gnomarchy set-pinned '<json-array-of-ids>'
```

| Key | Values | Meaning |
|---|---|---|
| `enabled` | `true` / `false` | Master on/off |
| `pinned` | `true` / `false` | Force the dock always visible without losing settings |
| `mode` | `always` / `fullscreen` | Auto-hide always, or only when a window is fullscreen |
| `iconSize` | integer 24-96 | Icon size in px |
| `revealPx` | integer 1-16 | Thickness of the hover-reveal strip |
| `hideDelayMs` | integer | Dwell time (after leaving the dock) before hiding |
| `showAppsButton` | `true` / `false` | Show the trailing "show applications" button |
| `pinnedApps` | JSON array of desktop-entry ids | Favorites, in order |

### Settings window

A gear icon at the right end of the dock (after the apps button) opens a small
in-place settings window with toggles/steppers for `showAppsButton`, `pinned`
("Keep dock visible"), `mode` ("Auto-hide only in fullscreen"), `iconSize`,
`revealPx`, `hideDelayMs`, and GNOME Mode. It's a second `PanelWindow` inside
`Dock.qml` itself (the plugin manifest only allows one file per `kind`, so it
can't be a separate `panel` entry point) — clicking outside it or pressing
Escape closes it. Every toggle/stepper writes through the same
`omarchy-gnomarchy set <key> <value>` CLI calls documented above, so the
dock's existing settings.json file-watcher picks the change up live; GNOME
Mode instead calls `omarchy-gnomarchy mode toggle`, since it's backed by a
marker file, not settings.json.

It can also be opened without touching the dock at all:

```bash
omarchy-gnomarchy settings open
omarchy-gnomarchy settings close
omarchy-gnomarchy settings toggle
```

which forwards to the running shell's own IPC (`omarchy-shell shell call
emanuel.gnomarchy <openSettings|closeSettings|toggleSettings> ''`) — the
same mechanism other Omarchy panel plugins use to be summoned/hidden.
`pinnedApps` isn't in the window (already handled by drag-to-reorder and the
right-click Favorite entry), and `enabled` isn't either — it's the plugin's
own master kill-switch, so turning it off from inside the dock would hide
the dock (and the settings window's own gear icon) with no way back in
without a terminal; it stays CLI-only.

Reachable from the Omarchy menu the same way GNOME Mode is (see above) by
adding this to your own `omarchy-menu.jsonc`:

```jsonc
"trigger.toggle.gnomarchy-settings": {"icon":"⚙","label":"Gnomarchy Settings",
  "action":"omarchy-gnomarchy settings toggle"}
```

## Files

- `manifest.json` — plugin manifest (`kinds: ["panel", "service"]`)
- `Dock.qml` — the dock's UI and logic
- `WorkspaceService.qml` — the dynamic-workspaces logic
- `bin/omarchy-gnomarchy` — settings CLI + `mode` (GNOME mode toggle),
  symlinked into `~/.local/bin`
- `extras/looknfeel-gnome.lua` — Hyprland tiling snippet controlled by
  `mode` once pasted into your own `looknfeel.lua` (see "GNOME mode" above)

## Developing this plugin

`keepLoaded: true` (required for the `panel` half to auto-mount at shell
startup at all — without it, panels only load on IPC `summon`) means saving
`Dock.qml` does **not** hot-reload the running instance: the file-watcher
fires (`quickshell log` shows "Local plugin changed, reloading"), but the
already-mounted panel instance is kept and keeps running the old code.
`WorkspaceService.qml` behaves the same way for the same reason
`service`-kind plugins generally do — the already-running instance is
cached across hot-reload regardless of `keepLoaded`. Run
`omarchy-restart-shell` after editing either file to actually see changes.
