import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// GNOME Dash-style bottom dock: pinned + running apps, running-app
// indicator dots, right-click context menu, drag-to-reorder pinned apps,
// auto-hide with hover-reveal. Self-contained - only public Quickshell APIs
// (Hyprland IPC, DesktopEntries, Wayland toplevel management) are used, no
// coupling to the host shell's internal qs.Commons/qs.Ui, matching the
// convention already used by emanuel.hide-top-bar.
//
// Architecture follows burninc0de/burninc0de.dock (another Omarchy Quickshell
// dock plugin): one constant-size layer-shell surface per screen with a
// `mask` listing each interactive sub-region (never a resized surface - that
// round-trips through the compositor on every show/hide and is what made an
// earlier revision of this dock feel sluggish), and hover-driven show/hide
// with a single-shot timer instead of a cursor-position poll.
Item {
  id: root

  // Injected by the omarchy-shell host; unused today but kept for parity
  // with other panel plugins in case a future revision needs it.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: "emanuel.gnomarchy"
  readonly property string pluginDir: root.home + "/.config/omarchy/plugins/" + root.pluginId
  readonly property string settingsPath: root.pluginDir + "/settings.json"
  readonly property string binPath: root.pluginDir + "/bin/omarchy-gnomarchy"

  // --------------------------------------------------------------- settings
  property bool settingsEnabled: true
  property bool settingsPinnedOpen: false
  property string settingsMode: "always"
  property int settingsIconSize: 48
  property int settingsRevealPx: 6
  property int settingsHideDelayMs: 500
  property bool settingsShowAppsButton: true
  property var settingsPinnedApps: ["Alacritty", "brave-origin", "org.gnome.Nautilus"]

  function applySettings() {
    var text = configFile.text();
    if (!text || !text.trim())
      return;
    var entry;
    try {
      entry = JSON.parse(text);
    } catch (e) {
      console.warn("gnomarchy: settings.json parse failed:", e);
      return;
    }
    if (!entry || typeof entry !== "object")
      return;
    root.settingsEnabled = entry.enabled !== false;
    root.settingsPinnedOpen = entry.pinned === true;
    root.settingsMode = entry.mode === "fullscreen" ? "fullscreen" : "always";
    root.settingsIconSize = Math.max(24, Math.min(96, Number(entry.iconSize) || 48));
    root.settingsRevealPx = Math.max(1, Math.min(16, Number(entry.revealPx) || 6));
    root.settingsHideDelayMs = Math.max(0, Number(entry.hideDelayMs) || 500);
    root.settingsShowAppsButton = entry.showAppsButton !== false;
    if (Array.isArray(entry.pinnedApps))
      root.settingsPinnedApps = entry.pinnedApps;
  }

  FileView {
    id: configFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applySettings()
    onFileChanged: reload()
  }

  function pinApp(id) { Quickshell.execDetached([root.binPath, "pin", id]); }
  function unpinApp(id) { Quickshell.execDetached([root.binPath, "unpin", id]); }
  function persistOrder(ids) { Quickshell.execDetached([root.binPath, "set-pinned", JSON.stringify(ids)]); }

  // ------------------------------------------------------------------ icons
  // Mirrors AppLibrary.qml's iconSource() without the extra on-disk fallback
  // index - good enough for a dock's own icon set.
  function iconSource(icon) {
    var value = String(icon || "");
    if (value.length === 0)
      return Quickshell.iconPath("application-x-executable", true);
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
      return value;
    if (value.charAt(0) === "/")
      return "file://" + value;
    var themed = Quickshell.iconPath(value, true);
    if (themed.length > 0)
      return themed;
    return Quickshell.iconPath("application-x-executable", true);
  }

  // -------------------------------------------------------------------- apps
  function desktopEntryFor(id) {
    var e = DesktopEntries.byId(id);
    if (!e)
      e = DesktopEntries.heuristicLookup(id);
    return e;
  }

  function toplevelClass(t) {
    var m = t.lastIpcObject;
    return (m && (m["class"] || m["initialClass"])) || "";
  }

  // A window this dock minimized lives on this hidden special workspace -
  // same trick burninc0de.dock uses, since Hyprland has no native minimize.
  readonly property string minimizedWorkspace: "special:dock_minimize"

  function isMinimized(t) {
    return t.workspace && t.workspace.name === root.minimizedWorkspace;
  }

  function runningToplevelsFor(id) {
    var out = [];
    var vals = Hyprland.toplevels.values;
    var lowerId = String(id).toLowerCase();
    for (var i = 0; i < vals.length; i++) {
      var cls = root.toplevelClass(vals[i]);
      if (!cls)
        continue;
      if (cls.toLowerCase() === lowerId) { out.push(vals[i]); continue; }
      var resolved = root.desktopEntryFor(cls);
      if (resolved && resolved.id === id)
        out.push(vals[i]);
    }
    return out;
  }

  // Ordered dock model: pinned apps first (pin order), then any running app
  // that isn't pinned, in first-seen order - the GNOME Dash convention.
  readonly property var dockItems: {
    var items = [];
    var seen = ({});
    for (var i = 0; i < root.settingsPinnedApps.length; i++) {
      var id = root.settingsPinnedApps[i];
      items.push({
        id: id,
        entry: root.desktopEntryFor(id),
        pinned: true,
        toplevels: root.runningToplevelsFor(id)
      });
      seen[id] = true;
    }
    var vals = Hyprland.toplevels.values;
    var extraSeen = ({});
    for (var j = 0; j < vals.length; j++) {
      var cls = root.toplevelClass(vals[j]);
      if (!cls)
        continue;
      var resolved = root.desktopEntryFor(cls);
      var rid = resolved ? resolved.id : cls;
      if (seen[rid] || extraSeen[rid])
        continue;
      extraSeen[rid] = true;
      items.push({ id: rid, entry: resolved, pinned: false, toplevels: root.runningToplevelsFor(rid) });
    }
    return items;
  }

  function launchDesktopId(id) {
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"]);
  }

  // Omarchy already ships a native apps-grid surface (the same one
  // SUPER+ALT+SPACE opens) - reuse it rather than building a second one.
  function openAppsMenu() {
    Quickshell.execDetached(["omarchy-menu", "toggle", "apps"]);
  }

  function toplevelAddress(t) {
    var addr = t.lastIpcObject && t.lastIpcObject.address;
    if (!addr || addr === "0")
      addr = "0x" + t.address;
    return addr;
  }

  function focusToplevel(t) {
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + root.toplevelAddress(t) + '" })');
  }

  function minimizeToplevel(t) {
    Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + root.minimizedWorkspace + '", follow = false, window = "address:' + root.toplevelAddress(t) + '" })');
  }

  function restoreToplevel(t) {
    var ws = Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.id) : "1";
    Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = true, window = "address:' + root.toplevelAddress(t) + '" })');
  }

  // Click behavior mirrors GNOME's dash: not running -> launch; one window
  // -> focus it, or minimize/restore if it's already the focused window;
  // several windows -> cycle to the next non-minimized one (skip past any
  // this dock has minimized until every window for the app is minimized,
  // in which case restore the first).
  function launchOrFocus(item) {
    var wins = item.toplevels;
    if (wins.length === 0) {
      root.launchDesktopId(item.id);
      return;
    }
    if (wins.length === 1) {
      var only = wins[0];
      if (root.isMinimized(only)) root.restoreToplevel(only);
      else if (only.activated) root.minimizeToplevel(only);
      else root.focusToplevel(only);
      return;
    }
    var visible = wins.filter(function(w) { return !root.isMinimized(w); });
    if (visible.length === 0) { root.restoreToplevel(wins[0]); return; }
    var idx = -1;
    for (var i = 0; i < visible.length; i++) if (visible[i].activated) idx = i;
    root.focusToplevel(visible[(idx + 1) % visible.length]);
  }

  function launchNew(item) { root.launchDesktopId(item.id); }

  function quitApp(item) {
    for (var i = 0; i < item.toplevels.length; i++) {
      var w = item.toplevels[i].wayland;
      if (w) w.close();
    }
  }

  // ---------------------------------------------------- workspace-empty state
  // Fully event-driven: Hyprland.toplevels is already a live reactive model,
  // so "does the focused workspace have any windows" needs no polling - only
  // a re-check on the Hyprland events that could change the answer.
  property bool workspaceEmpty: true

  function updateWorkspaceEmpty() {
    var wsId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null;
    if (wsId === null) return;
    var vals = Hyprland.toplevels.values;
    for (var i = 0; i < vals.length; i++) {
      if (vals[i].workspace && vals[i].workspace.id === wsId) { root.workspaceEmpty = false; return; }
    }
    root.workspaceEmpty = true;
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["workspace", "workspacev2", "activewindow", "activewindowv2",
           "createworkspace", "createworkspacev2",
           "destroyworkspace", "destroyworkspacev2", "openwindow", "closewindow"].includes(event.name)) {
        root.updateWorkspaceEmpty();
      }
    }
  }

  Component.onCompleted: {
    root.updateWorkspaceEmpty();
    root.dockVisible = !root.autohideActive || root.workspaceEmpty;
  }

  // -------------------------------------------------------------- auto-hide
  readonly property bool fullscreenActive: Hyprland.focusedWorkspace
    ? Hyprland.focusedWorkspace.hasFullscreen === true : false
  readonly property bool autohideActive: root.settingsEnabled && !root.settingsPinnedOpen
    && (root.settingsMode !== "fullscreen" || root.fullscreenActive)

  property bool dockVisible: true
  property bool mouseOverDockArea: false
  property bool dragging: false

  function showDockBar() { hideTimer.stop(); root.dockVisible = true; }
  function scheduleHide() {
    if (!root.autohideActive || root.workspaceEmpty) return;
    hideTimer.restart();
  }
  function reconsiderVisibility() {
    if (!root.autohideActive || root.workspaceEmpty || root.mouseOverDockArea
        || root.dragging || root.contextMenuVisible) {
      root.showDockBar();
    } else {
      root.scheduleHide();
    }
  }

  onAutohideActiveChanged: root.reconsiderVisibility()
  onWorkspaceEmptyChanged: root.reconsiderVisibility()
  onMouseOverDockAreaChanged: root.reconsiderVisibility()
  onDraggingChanged: root.reconsiderVisibility()
  onContextMenuVisibleChanged: root.reconsiderVisibility()

  Timer {
    id: hideTimer
    interval: root.settingsHideDelayMs
    repeat: false
    onTriggered: {
      if (!root.autohideActive || root.workspaceEmpty || root.mouseOverDockArea
          || root.dragging || root.contextMenuVisible) return;
      root.dockVisible = false;
    }
  }

  readonly property int dockHeight: root.settingsIconSize + 24
  // Tall enough for the pill-shaped dock plus a context-menu popup above it.
  // Constant - never resized - so show/hide only ever moves `card`, never
  // the layer-shell surface itself.
  readonly property int surfaceHeight: root.dockHeight + 150
  readonly property int hiddenMargin: -(root.dockHeight + 16)
  readonly property int shownMargin: 8

  // ---------------------------------------------------------- context menu
  property var contextMenuItem: null
  property real contextMenuX: 0
  property bool contextMenuVisible: false

  function openContextMenu(item, x) {
    root.contextMenuItem = item;
    root.contextMenuX = x;
    root.contextMenuVisible = true;
  }
  function closeContextMenu() {
    root.contextMenuVisible = false;
    root.contextMenuItem = null;
  }

  readonly property var contextMenuEntries: {
    if (!root.contextMenuVisible || !root.contextMenuItem) return [];
    var out = [{ label: "New Window", action: "new" }];
    out.push({ label: root.contextMenuItem.pinned ? "Remove from Favorites" : "Add to Favorites", action: "pin" });
    if (root.contextMenuItem.toplevels.length > 0) out.push({ label: "Quit", action: "quit" });
    return out;
  }

  function runContextAction(action) {
    var item = root.contextMenuItem;
    if (!item) return;
    if (action === "new") root.launchNew(item);
    else if (action === "pin") { if (item.pinned) root.unpinApp(item.id); else root.pinApp(item.id); }
    else if (action === "quit") root.quitApp(item);
    root.closeContextMenu();
  }

  // ------------------------------------------------------------- settings
  property bool settingsWindowOpen: false
  // GNOME Mode lives outside settings.json (a marker file), so it can't ride
  // the FileView watcher below - read it explicitly whenever the window opens.
  property bool gnomeModeOn: false

  function openSettings(arg) {
    root.settingsWindowOpen = true;
    modeStatusProc.running = true;
  }
  function closeSettings(arg) { root.settingsWindowOpen = false; }
  function toggleSettings(arg) {
    if (root.settingsWindowOpen) root.closeSettings("");
    else root.openSettings("");
  }

  Process {
    id: modeStatusProc
    command: [root.binPath, "mode", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.gnomeModeOn = String(text || "").trim() === "on"
    }
  }

  Timer {
    id: modeStatusRecheck
    interval: 250
    onTriggered: modeStatusProc.running = true
  }

  function setSetting(key, value) { Quickshell.execDetached([root.binPath, "set", key, String(value)]); }

  function toggleGnomeMode() {
    Quickshell.execDetached([root.binPath, "mode", "toggle"]);
    root.gnomeModeOn = !root.gnomeModeOn;
    modeStatusRecheck.restart();
  }

  // Small reusable controls for the settings window - no ready-made
  // toggle/slider widgets ship in Quickshell.Widgets, and this file
  // deliberately avoids pulling in QtQuick.Controls, so hand-roll them in
  // the same Rectangle+MouseArea style as iconCell/appsButtonCell.
  component SettingsToggle: Row {
    id: toggleRoot
    property string label: ""
    property bool checked: false
    signal toggled()
    spacing: 8

    Rectangle {
      width: 36
      height: 20
      radius: 10
      anchors.verticalCenter: parent.verticalCenter
      color: toggleRoot.checked ? "#6c8cff" : "#4dffffff"

      Rectangle {
        width: 16
        height: 16
        radius: 8
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: toggleRoot.checked ? parent.width - width - 2 : 2
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      }

      MouseArea { anchors.fill: parent; onClicked: toggleRoot.toggled() }
    }

    Text {
      text: toggleRoot.label
      color: "white"
      font.pixelSize: 12
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component SettingsStepper: Row {
    id: stepperRoot
    property string label: ""
    property int value: 0
    property int minValue: 0
    property int maxValue: 999
    property int stepBy: 1
    signal changed(int newValue)
    spacing: 8

    Text {
      text: stepperRoot.label
      color: "white"
      font.pixelSize: 12
      width: 118
      anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
      width: 20
      height: 20
      radius: 4
      color: "#33ffffff"
      anchors.verticalCenter: parent.verticalCenter
      Text { anchors.centerIn: parent; text: "-"; color: "white"; font.pixelSize: 12 }
      MouseArea {
        anchors.fill: parent
        onClicked: stepperRoot.changed(Math.max(stepperRoot.minValue, stepperRoot.value - stepperRoot.stepBy))
      }
    }

    Text {
      text: stepperRoot.value
      color: "white"
      font.pixelSize: 12
      width: 32
      horizontalAlignment: Text.AlignHCenter
      anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
      width: 20
      height: 20
      radius: 4
      color: "#33ffffff"
      anchors.verticalCenter: parent.verticalCenter
      Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 12 }
      MouseArea {
        anchors.fill: parent
        onClicked: stepperRoot.changed(Math.min(stepperRoot.maxValue, stepperRoot.value + stepperRoot.stepBy))
      }
    }
  }

  // ------------------------------------------------------------ surfaces
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: dockWindow
        required property var modelData
        screen: modelData

        color: "transparent"
        WlrLayershell.namespace: "omarchy-gnomarchy"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true; left: true; right: true }
        implicitHeight: root.surfaceHeight

        mask: Region {
          Region { item: triggerStrip }
          Region { item: card }
          Region { item: contextMenu }
        }

        // Hairline hover-reveal strip, always present at the very bottom
        // edge regardless of whether `card` is currently shown or slid out
        // of view - this is what lets a hidden dock be summoned at all.
        Rectangle {
          id: triggerStrip
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: card.horizontalCenter
          width: card.width + 80
          height: root.settingsRevealPx
          color: "transparent"

          HoverHandler {
            id: triggerHover
            onHoveredChanged: root.mouseOverDockArea = triggerHover.hovered || dockHover.hovered || contextMenuHover.hovered
          }
        }

        Rectangle {
          id: card
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottomMargin: root.hiddenMargin
          width: dockRow.width + 24
          height: root.dockHeight
          color: "#e6202030"
          radius: 14
          border.width: 1
          border.color: "#4dffffff"

          states: State {
            name: "shown"
            when: root.dockVisible
            PropertyChanges { target: card; anchors.bottomMargin: root.shownMargin }
          }
          transitions: Transition {
            NumberAnimation { property: "anchors.bottomMargin"; duration: 200; easing.type: Easing.OutCubic }
          }

          HoverHandler {
            id: dockHover
            onHoveredChanged: root.mouseOverDockArea = triggerHover.hovered || dockHover.hovered || contextMenuHover.hovered
          }

          // A plain Item with hand-computed slot positions, not a Layout:
          // dragging an item inside a RowLayout fights the layout's own
          // positioning every frame, so pinned icons place themselves at
          // `index * step` and a dragged cell temporarily overrides that via
          // its own x, restored (or persisted as a new order) on release.
          Item {
            id: dockRow
            readonly property int step: root.settingsIconSize + 10
            readonly property int appsAreaWidth: Math.max(0, root.dockItems.length * step - 10)
            readonly property int appsExtra: root.settingsShowAppsButton ? (21 + root.settingsIconSize) : 0
            readonly property int gearSize: Math.round(root.settingsIconSize * 0.6)
            readonly property int gearExtra: 16 + gearSize
            anchors.centerIn: parent
            width: appsAreaWidth + appsExtra + gearExtra
            height: root.settingsIconSize

            Repeater {
              model: root.dockItems

              Rectangle {
                id: iconCell
                required property var modelData
                required property int index

                readonly property real restX: iconCell.index * dockRow.step
                x: iconCell.restX
                y: 0
                width: root.settingsIconSize
                height: root.settingsIconSize
                radius: 10
                z: dragHandle.active ? 10 : 0
                color: cellMouse.containsMouse ? "#22ffffff" : "transparent"

                Behavior on x {
                  enabled: !dragHandle.active
                  NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                IconImage {
                  anchors.centerIn: parent
                  implicitSize: root.settingsIconSize - 10
                  source: root.iconSource(iconCell.modelData.entry ? iconCell.modelData.entry.icon : "")
                  opacity: {
                    var wins = iconCell.modelData.toplevels;
                    if (wins.length === 0) return 1;
                    for (var i = 0; i < wins.length; i++) if (!root.isMinimized(wins[i])) return 1;
                    return 0.45;
                  }
                }

                Rectangle {
                  visible: iconCell.modelData.toplevels.length > 0
                  width: 5
                  height: 5
                  radius: 2.5
                  color: "#ffffff"
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: -5
                }

                DragHandler {
                  id: dragHandle
                  enabled: iconCell.modelData.pinned
                  target: iconCell
                  xAxis.enabled: true
                  yAxis.enabled: false
                  onActiveChanged: {
                    root.dragging = active;
                    if (active) return;
                    // Drop: reorder pinned ids by final on-screen x order,
                    // then snap every cell back to its computed slot.
                    var pinnedCells = [];
                    for (var i = 0; i < dockRow.children.length; i++) {
                      var child = dockRow.children[i];
                      if (child && child.modelData && child.modelData.pinned) pinnedCells.push(child);
                    }
                    pinnedCells.sort(function(a, b) { return a.x - b.x; });
                    var ids = [];
                    for (var j = 0; j < pinnedCells.length; j++) ids.push(pinnedCells[j].modelData.id);
                    root.persistOrder(ids);
                  }
                }

                MouseArea {
                  id: cellMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      // iconCell.x is local to dockRow's coordinate space, not
                      // dockWindow's (contextMenu is a direct child of
                      // dockWindow, a sibling of card) - map through to the
                      // window's own coordinates or the menu ends up biased
                      // toward the left edge.
                      var scenePoint = iconCell.mapToItem(dockWindow.contentItem, mouse.x, mouse.y);
                      root.openContextMenu(iconCell.modelData, scenePoint.x);
                    } else {
                      root.launchOrFocus(iconCell.modelData);
                    }
                  }
                }
              }
            }

            Rectangle {
              width: 1
              height: root.settingsIconSize * 0.6
              anchors.verticalCenter: parent.verticalCenter
              x: dockRow.appsAreaWidth + 10
              color: "#33ffffff"
              visible: root.settingsShowAppsButton && root.dockItems.length > 0
            }

            Rectangle {
              id: appsButtonCell
              x: dockRow.appsAreaWidth + 21
              width: root.settingsIconSize
              height: root.settingsIconSize
              radius: 10
              visible: root.settingsShowAppsButton
              color: appsButtonMouse.containsMouse ? "#22ffffff" : "transparent"

              Text {
                anchors.centerIn: parent
                text: "󰀻"
                color: "white"
                font.family: "monospace"
                font.pixelSize: root.settingsIconSize * 0.5
              }

              MouseArea {
                id: appsButtonMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openAppsMenu()
              }
            }

            Rectangle {
              id: gearCell
              x: dockRow.appsAreaWidth + dockRow.appsExtra + 8
              width: dockRow.gearSize
              height: dockRow.gearSize
              radius: 8
              anchors.verticalCenter: parent.verticalCenter
              color: gearMouse.containsMouse ? "#22ffffff" : "transparent"

              Text {
                anchors.centerIn: parent
                text: "⚙"
                color: "white"
                font.pixelSize: dockRow.gearSize * 0.7
              }

              MouseArea {
                id: gearMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.toggleSettings("")
              }
            }
          }
        }

        Rectangle {
          id: contextMenu
          visible: root.contextMenuVisible
          x: Math.max(4, Math.min(root.contextMenuX, dockWindow.width - width - 4))
          y: card.y - height - 6
          width: root.contextMenuVisible ? 170 : 0
          height: root.contextMenuVisible ? menuColumn.implicitHeight + 12 : 0
          radius: 8
          color: "#1e1e2e"
          border.width: 1
          border.color: "#33ffffff"

          HoverHandler {
            id: contextMenuHover
            onHoveredChanged: root.mouseOverDockArea = triggerHover.hovered || dockHover.hovered || contextMenuHover.hovered
          }

          Column {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Repeater {
              model: root.contextMenuEntries

              Rectangle {
                required property var modelData
                width: menuColumn.width
                height: 26
                radius: 4
                color: entryMouse.containsMouse ? "#33ffffff" : "transparent"

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 8
                  text: modelData.label
                  color: "white"
                  font.pixelSize: 12
                }

                MouseArea {
                  id: entryMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.runContextAction(modelData.action)
                }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- settings window
  // A single instance (not per-screen, unlike the dock surface above) since
  // it's a modal-style dialog, not something that needs to live on every
  // monitor at once.
  PanelWindow {
    id: settingsWindow
    visible: root.settingsWindowOpen
    color: "transparent"
    WlrLayershell.namespace: "omarchy-gnomarchy-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)

      MouseArea { anchors.fill: parent; onClicked: root.closeSettings("") }

      Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.closeSettings("")

        Rectangle {
          id: settingsCard
          anchors.centerIn: parent
          width: 280
          height: settingsColumn.implicitHeight + 24
          radius: 8
          color: "#1e1e2e"
          border.width: 1
          border.color: "#33ffffff"

          MouseArea { anchors.fill: parent } // swallow clicks so they don't reach the scrim

          Column {
            id: settingsColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
              text: "Gnomarchy Settings"
              color: "white"
              font.bold: true
              font.pixelSize: 13
            }

            SettingsToggle {
              label: "Show apps button"
              checked: root.settingsShowAppsButton
              onToggled: root.setSetting("showAppsButton", !checked)
            }

            SettingsToggle {
              label: "Keep dock visible"
              checked: root.settingsPinnedOpen
              onToggled: root.setSetting("pinned", !checked)
            }

            SettingsToggle {
              label: "Auto-hide only in fullscreen"
              checked: root.settingsMode === "fullscreen"
              onToggled: root.setSetting("mode", checked ? "always" : "fullscreen")
            }

            SettingsStepper {
              label: "Icon size"
              value: root.settingsIconSize
              minValue: 24
              maxValue: 96
              stepBy: 4
              onChanged: (v) => root.setSetting("iconSize", v)
            }

            SettingsStepper {
              label: "Reveal px"
              value: root.settingsRevealPx
              minValue: 1
              maxValue: 16
              stepBy: 1
              onChanged: (v) => root.setSetting("revealPx", v)
            }

            SettingsStepper {
              label: "Hide delay (ms)"
              value: root.settingsHideDelayMs
              minValue: 0
              maxValue: 3000
              stepBy: 100
              onChanged: (v) => root.setSetting("hideDelayMs", v)
            }

            Rectangle { width: parent.width; height: 1; color: "#33ffffff" }

            SettingsToggle {
              label: "GNOME Mode"
              checked: root.gnomeModeOn
              onToggled: root.toggleGnomeMode()
            }
          }
        }
      }
    }
  }
}
