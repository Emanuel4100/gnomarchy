#pragma once

// Gnomarchy's own drag-to-edge/corner/top window-snap module (Windows-11 /
// GNOME-style Aero Snap for floating windows). This is a wholly separate
// listener on Hyprland core's own public drag-state API
// (g_layoutManager->dragController()) - it does not touch or depend on any
// of hyprbars' internals in vendor/, only on the fact that hyprbars starts
// window drags via Hyprland's own g_layoutManager->beginDragTarget(), same
// as a plain SUPER+drag would.
//
// Phase 1 (this file): stub hooks only, wired into vendor/main.cpp's
// PLUGIN_INIT/PLUGIN_EXIT so the build is complete and the insertion point
// is ready. Phase 2 fills in the actual snap-on-release logic.

void gnomarchySnapInit();
void gnomarchySnapExit();
