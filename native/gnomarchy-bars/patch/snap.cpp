#include "snap.hpp"

// Phase 2: drag-to-snap logic goes here (listen to Event::bus()'s global
// input.mouse.move/button signals, check g_layoutManager->dragController()
// for an active MBIND_MOVE drag, track cursor proximity to the focused
// monitor's edges/corners/top strip, and on release call
// g_layoutManager->setTargetGeom(...) to commit the half/quarter/maximized
// geometry). No-ops for now so Phase 1 (title bars + build/load lifecycle)
// is complete and independently shippable.

void gnomarchySnapInit() {
}

void gnomarchySnapExit() {
}
