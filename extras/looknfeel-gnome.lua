-- Optional: GNOME-style edge-to-edge tiling for Omarchy 4's Hyprland config,
-- toggled together with the rest of GNOME mode (`omarchy-gnomarchy mode
-- on|off|toggle`, or SUPER+SPACE > Trigger > Toggle > GNOME Mode once you've
-- added that menu entry - see the main README).
--
-- This is NOT applied automatically by the plugin - a plugin has no
-- business silently editing a file you own. Paste this whole file's content
-- into your own ~/.config/hypr/looknfeel.lua (or `require` this file from
-- it) if you want the look. Once pasted, `omarchy-gnomarchy mode` fully
-- controls it from then on - no further manual editing needed.
--
-- Zero gaps, no colored borders (GNOME relies on shadow/focus state, not a
-- border color) - dwindle already fills a lone window to the whole
-- workspace, so that's most of what makes GNOME's single-window-per-
-- workspace feel work, for free. Applied only while GNOME mode is on: state
-- lives in a marker file (not baked in unconditionally), so a real Hyprland
-- config reload respects whatever mode was last set instead of always
-- reapplying these values regardless of the toggle.
local gnomarchy_mode_marker = os.getenv("HOME") .. "/.config/omarchy/plugins/emanuel.gnomarchy/.gnome-mode-on"
local gnomarchy_mode_file = io.open(gnomarchy_mode_marker, "r")
if gnomarchy_mode_file then
  gnomarchy_mode_file:close()

  hl.config({
    general = {
      gaps_in = 0,
      gaps_out = 0,
      border_size = 0,
    },
  })

  -- Adwaita-style rounded window corners.
  hl.config({
    decoration = {
      rounding = 12,
    },
  })
end
