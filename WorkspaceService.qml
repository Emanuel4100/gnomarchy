import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Keeps exactly one empty "spare" workspace past whichever numbered
// workspace is currently the highest occupied one - the GNOME dynamic
// workspace feel (there's always one more waiting) adapted to Hyprland's
// numbered-workspace model rather than trying to renumber/reflow workspaces
// like GNOME's own ordinal list.
//
// Hyprland already destroys a non-persistent empty workspace the moment
// it's both empty and unfocused (verified live), so the removal half of
// "dynamic workspaces" is free. This plugin only has to handle creation:
// marking the next workspace `persistent:true` (which eagerly instantiates
// it with no window and no focus change, verified live via
// `hyprctl eval 'hl.workspace_rule({workspace="9", persistent=true})'`) and
// clearing the previous spare's persistent flag so Hyprland's own default
// cleanup can reclaim it if it's still empty.
Item {
  id: root

  // Only workspaces 1-10 have a dedicated SUPER+<key> bind
  // (default/hypr/bindings/tiling.lua), so the spare never goes further out
  // than the last reachable one.
  readonly property int maxWorkspace: 10

  function toplevelCount(ws) {
    return ws && ws.toplevels ? ws.toplevels.values.length : 0
  }

  readonly property int maxOccupied: {
    var vals = Hyprland.workspaces.values
    var m = 0
    for (var i = 0; i < vals.length; i++) {
      var ws = vals[i]
      if (ws.id > 0 && ws.id > m && root.toplevelCount(ws) > 0) m = ws.id
    }
    return m
  }

  readonly property int desiredSpare: Math.min(root.maxWorkspace, root.maxOccupied + 1)

  // 0 means "nothing marked yet" - distinct from any real workspace id.
  property int markedSpare: 0

  onDesiredSpareChanged: root.reconcile()
  Component.onCompleted: root.reconcile()

  function setPersistent(id, persistent) {
    Quickshell.execDetached([
      "hyprctl", "eval",
      "hl.workspace_rule({workspace=\"" + id + "\", persistent=" + (persistent ? "true" : "false") + "})"
    ])
  }

  function reconcile() {
    if (root.desiredSpare === root.markedSpare) return
    var previous = root.markedSpare
    root.markedSpare = root.desiredSpare
    root.setPersistent(root.desiredSpare, true)
    // Clearing the old spare's persistent flag lets Hyprland's own default
    // cleanup reclaim it next time it's both empty and unfocused - this
    // plugin never destroys a workspace itself.
    if (previous > 0 && previous !== root.desiredSpare) root.setPersistent(previous, false)
  }
}
