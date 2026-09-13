-- Optional: GNOME-style edge-to-edge tiling for Omarchy 4's Hyprland config.
--
-- This is NOT applied automatically by the plugin - a plugin has no
-- business silently editing a file you own. Paste the two blocks below into
-- your own ~/.config/hypr/looknfeel.lua (or `require` this file from it) if
-- you want the look.
--
-- Zero gaps, no colored borders (GNOME relies on shadow/focus state, not a
-- border color) - dwindle already fills a lone window to the whole
-- workspace, so that's most of what makes GNOME's single-window-per-
-- workspace feel work, for free.
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
