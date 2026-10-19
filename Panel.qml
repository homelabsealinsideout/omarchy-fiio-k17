import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons

// Bar row for the FiiO K17: device icon plus any of input, EQ, and volume
// ("BAL · Jazz · 32"), or a compact "K17", dimmed while not connected.
// Click opens a panel with volume, mute, input, and EQ (with an editor for the
// custom EQs); the gear switches it to the plugin settings, which are stored on
// this widget's shell.json entry and pushed to the shared service.
// Scroll on the bar row steps the volume, right-click mutes.
Panel {
  id: root
  moduleName: "io.github.homelabsealinsideout.fiio-k17"
  ipcTarget: "io.github.homelabsealinsideout.fiio-k17"
  // The service owns the IPC target.
  manageIpc: false

  readonly property var k17: bar && bar.shell ? bar.shell.serviceFor("io.github.homelabsealinsideout.fiio-k17") : null
  readonly property bool online: !!k17 && k17.online
  readonly property bool muted: !!k17 && k17.muted
  readonly property color dim: Qt.darker(root.bar.foreground, 1.4)

  readonly property var defaults: k17 ? k17.defaults : ({})
  function value(key) { return root.setting(key, root.defaults[key]) }

  function save(key, v) {
    if (k17) k17.save(key, v)
  }

  function pushSettings() {
    if (!k17 || !k17.defaultsReady) return
    var s = {}
    for (var k in root.defaults) s[k] = root.value(k)
    k17.configure(s)
  }
  readonly property bool settingsReady: !!k17 && k17.defaultsReady
  onSettingsReadyChanged: pushSettings()
  onK17Changed: pushSettings()
  onSettingsChanged: pushSettings()
  Component.onCompleted: pushSettings()

  // "controls", "settings", or "eq" (custom EQ editor).
  property string view: "controls"
  property int eqBand: -1
  onOpenedChanged: {
    if (k17) { k17.panelOpen = opened; if (opened) k17.refresh() }
    // Land on the settings when asked to or when there is nothing to control yet.
    if (opened) {
      var wanted = k17 ? k17.requestedView : ""
      if (!value("host")) view = "settings"
      else if (wanted === "eq") openEditor()  // disabled until a custom EQ is active
      else view = wanted === "settings" ? "settings" : "controls"
      if (k17) k17.loadBackups()
    }
    if (k17) k17.requestedView = ""
  }

  function openEditor() {
    k17.loadBands()
    k17.loadBackups()
    k17.lastMessage = ""
    eqBand = -1
    view = "eq"
  }

  readonly property string eqLabel: {
    if (!k17) return ""
    for (var i = 0; i < k17.eqs.length; i++)
      if (k17.eqs[i].value === k17.eq) return k17.eqs[i].label
    return "EQ"
  }

  function hzText(hz) {
    return hz >= 1000 ? (Math.round(hz / 100) / 10) + " kHz" : Math.round(hz) + " Hz"
  }
  // The K17 stores frequencies on a log scale: 120 steps per decade from 20 Hz.
  function hzToCode(hz) { return 1 + 120 * Math.log(hz / 20) / Math.LN10 }
  function codeToHz(c) { return 20 * Math.pow(10, (c - 1) / 120) }

  // Shown bands for the graph, left to right by frequency.
  readonly property var graphBands: {
    if (!k17) return []
    var out = []
    for (var i = 0; i < k17.eqShown.length; i++) {
      var b = k17.eqBands[k17.eqShown[i]]
      if (b) out.push(b)
    }
    return out.sort(function (a, b) { return a.hz - b.hz })
  }

  // Band the editor works on: the chosen one, else the first shown band.
  readonly property int currentBand: {
    if (!k17 || k17.eqShown.length === 0) return -1
    return k17.eqShown.indexOf(eqBand) >= 0 ? eqBand : k17.eqShown[0]
  }
  readonly property var band: k17 && currentBand >= 0 && k17.eqBands[currentBand] ? k17.eqBands[currentBand] : null

  // Bar text next to the K17 icon: any combination of input, EQ, and volume;
  // "K17" when none is chosen or the K17 is not connected.
  readonly property string barText: {
    if (!k17) return ""
    var parts = []
    if (online) {
      if (value("barInput") && k17.inputShort) parts.push(k17.inputShort)
      if (value("barEq") && k17.eqShort) parts.push(k17.eqShort)
      if (value("barVolume")) parts.push(muted ? "󰖁" : String(k17.volume))
    }
    if (parts.length === 0) return "K17" + (k17.released ? " 󰏤" : "")
    return parts.join(" · ")
  }

  // Connection state for the panel header: theme colours only, no status colours.
  readonly property string statusText: {
    if (!k17) return ""
    if (!value("host")) return "○ No IP address set"
    if (k17.released) return "󰏤 Released for the FiiO app"
    return (online ? "● Online · " : "○ Offline · ") + value("host")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: barText !== ""

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    // The label is drawn below together with the icon; the button keeps the
    // shared hover, click, tooltip, and dimming behaviour.
    labelVisible: false
    fixedWidth: barRow.implicitWidth + scaledHorizontalMargin * 2
    dimmed: !root.online
    tooltipText: root.online
      ? "FiiO K17 · " + root.k17.inputShort + " · " + root.k17.eqShort + " · " + (root.muted ? "muted" : root.k17.volume)
        + "\nClick for controls, scroll for volume, right-click to mute"
      : "FiiO K17: " + (root.k17 && root.k17.error ? root.k17.error : "offline")
    onPressed: function (b) {
      if (b === Qt.RightButton && root.online) root.k17.toggleMute()
      else root.toggle()
    }
    onWheelMoved: function (delta) {
      if (root.online) root.k17.stepVolume(delta > 0)
    }

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      K17Icon {
        anchors.verticalCenter: parent.verticalCenter
        size: Math.round(button.fontSize * 0.95)
        color: button.foreground
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.barText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }
  }

  component SectionText: Text {
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component Section: Column {
    id: section
    property alias title: header.text
    property string tip: ""
    width: parent.width
    spacing: Style.space(6)

    Row {
      spacing: Style.space(6)

      PanelSectionHeader {
        id: header
        anchors.verticalCenter: parent.verticalCenter
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Text {
        visible: section.tip !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: "󰋽"
        color: root.dim
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption

        HoverHandler { id: tipHover }
        Hint { show: tipHover.hovered; text: section.tip }
      }
    }
  }

  // Label, slider, and value; sends the value while dragging and on release.
  component BandSlider: Item {
    id: bs
    property string label: ""
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property real value: 0
    property var display: function (v) { return String(v) }
    signal picked(real v)
    width: parent.width
    implicitHeight: Math.max(bsLabel.implicitHeight, bsSlider.implicitHeight)

    SectionText {
      id: bsLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40)
      text: bs.label
    }

    PanelSlider {
      id: bsSlider
      bar: root.bar
      anchors.left: bsLabel.right
      anchors.leftMargin: Style.space(6)
      anchors.right: bsValue.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      minimum: bs.minimum
      maximum: bs.maximum
      step: bs.step
      value: bs.value
      onMoved: function (v) { bs.picked(v) }
      onReleased: function (v) { bs.picked(v) }
    }

    SectionText {
      id: bsValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(64)
      horizontalAlignment: Text.AlignRight
      text: bs.display(bsSlider.dragging ? bsSlider.liveValue : bsSlider.value)
      font.bold: true
    }
  }

  // Hover explanation for a settings row; the label gets an info icon so
  // people know there is one.
  component Hint: PanelToolTip {
    property bool show: false
    visible: show && text !== ""
    fontFamily: root.bar.fontFamily
  }

  component SettingRow: Item {
    id: row
    property string label: ""
    property string tip: ""
    property bool checked: false
    signal toggled()
    width: parent.width
    implicitHeight: Math.max(rowLabel.implicitHeight, rowSwitch.implicitHeight)

    HoverHandler { id: rowHover }
    Hint { show: rowHover.hovered; text: row.tip }

    SectionText {
      id: rowLabel
      anchors.left: parent.left
      anchors.right: rowSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: row.label + (row.tip ? "  <font color='" + root.dim + "'>󰋽</font>" : "")
      textFormat: Text.StyledText
    }

    ToggleSwitch {
      id: rowSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: row.checked
      foreground: root.bar.foreground
      onToggled: row.toggled()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.view === "eq" ? 460 : 320))
    // Dropdown popups open downwards inside this surface, so grow it while one is open.
    contentHeight: panel.fittedContentHeight(col.implicitHeight
      + (inputDropdown.popupOpen || eqDropdown.popupOpen ? Style.spacing.popupRowHeight * 8 + Style.space(24) : 0),
      Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.view !== "controls" ? root.view = "controls" : root.close()

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: col.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
        id: col
        width: scrollArea.availableWidth
        spacing: Style.space(14)

        PanelHero {
          iconComponent: Component {
            K17Icon {
              size: Math.round(Style.font.display * 0.75)
              color: root.bar.foreground
            }
          }
          title: root.view === "settings" ? "K17 Settings"
            : root.view === "eq" ? root.eqLabel
            : "FiiO K17"
          // Backups and restores hold the connection for a while; say so instead
          // of showing values that do not update in the meantime.
          meta: root.k17 && root.k17.busyText ? "◌ " + root.k17.busyText
            : root.view === "eq" && root.online
            ? (root.k17.eqDirty ? "● Unsaved changes" : "● Saved on the K17")
            : root.statusText
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          trailingControl: Component {
            PanelActionButton {
              iconText: root.view !== "controls" ? "󰅖" : "󰒓"
              tooltipText: root.view !== "controls" ? "Back" : "Settings"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.view = root.view !== "controls" ? "controls" : "settings"
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ================= Controls =================
        Column {
          width: parent.width
          spacing: Style.space(14)
          visible: root.view === "controls"
          enabled: root.online
          opacity: enabled ? 1 : 0.5

          Section {
            title: "VOLUME"

            Item {
              width: parent.width
              implicitHeight: Math.max(muteButton.implicitHeight, volSlider.implicitHeight, volText.implicitHeight)

              PanelActionButton {
                id: muteButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.muted ? "󰖁" : "󰕾"
                tooltipText: root.muted ? "Unmute" : "Mute"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.k17.toggleMute()
              }

              PanelSlider {
                id: volSlider
                bar: root.bar
                anchors.left: muteButton.right
                anchors.leftMargin: Style.space(8)
                anchors.right: volText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                minimum: 0
                maximum: 100
                step: 1
                integer: true
                value: root.k17 && root.k17.volume >= 0 ? root.k17.volume : 0
                onReleased: function (v) { root.k17.setVolume(Math.round(v)) }
                onRightClicked: root.k17.toggleMute()
              }

              SectionText {
                id: volText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                horizontalAlignment: Text.AlignRight
                text: root.online ? String(Math.round(volSlider.dragging ? volSlider.liveValue : volSlider.value)) : "–"
                font.bold: true
              }
            }
          }

          Section {
            title: "INPUT"

            Dropdown {
              id: inputDropdown
              width: parent.width
              showLabel: false
              fontFamily: root.bar.fontFamily
              options: root.k17 ? root.k17.inputs.map(function (o) { return { value: String(o.value), label: o.label } }) : []
              value: root.k17 ? String(root.k17.input) : ""
              onChanged: function (v) { root.k17.setInput(parseInt(v)) }
            }
          }

          Section {
            title: "EQ"

            Item {
              width: parent.width
              implicitHeight: eqDropdown.implicitHeight

            Dropdown {
              id: eqDropdown
              anchors.left: parent.left
              anchors.right: editButton.visible ? editButton.left : parent.right
              anchors.rightMargin: editButton.visible ? Style.space(8) : 0
              showLabel: false
              fontFamily: root.bar.fontFamily
              options: root.k17 ? root.k17.eqs.map(function (o) { return { value: String(o.value), label: o.label } }) : []
              value: root.k17 ? String(root.k17.eq) : ""
              onChanged: function (v) { root.k17.setEq(parseInt(v)) }
            }

            PanelActionButton {
              id: editButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: !!root.k17 && root.k17.eqEditable
              iconText: "󰏫"
              tooltipText: "Edit this custom EQ"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.openEditor()
            }
            }
          }
        }

        // ================= Custom EQ editor =================
        Column {
          width: parent.width
          spacing: Style.space(14)
          visible: root.view === "eq"
          enabled: root.online && !!root.k17 && root.k17.eqEditable
          opacity: enabled ? 1 : 0.5

          Item {
            width: parent.width
            implicitHeight: nameField.implicitHeight

            SectionText {
              id: nameLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(46)
              text: "Name"
            }

            TextField {
              id: nameField
              anchors.left: nameLabel.right
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              foreground: root.bar.foreground
              maximumLength: 8
              placeholderText: "Up to 8 characters"
              text: root.k17 ? root.k17.eqName : ""
              Hint {
                show: nameField.hovered
                text: "Name of this custom EQ, shown in the EQ list\nand the bar. Up to 8 characters; press Enter\nto store it on the K17."
              }
              // Rename on Enter only: losing focus after the EQ changed must not
              // rename a different slot with leftover text.
              onAccepted: if (text.trim() !== root.k17.eqName) root.k17.renameEq(text.trim())

              Connections {
                target: root.k17
                function onEqChanged() { nameField.text = root.k17.eqName }
                function onEqNameChanged() { if (!nameField.activeFocus) nameField.text = root.k17.eqName }
              }
            }
          }

          Section {
            title: "BANDS"
            tip: "Each bar is one band of this EQ, placed at its frequency.\nClick a bar to select it, drag it up or down to change its gain.\nThe line shows what you hear: all bands combined."

          EqGraph {
            width: parent.width
            bands: root.graphBands
            selected: root.currentBand
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onPicked: function (i) { root.eqBand = i }
            onGainDragged: function (i, db) { root.eqBand = i; root.k17.setBand(i, { gain: db }) }
          }
          }

          Section {
            title: root.band ? "BAND · " + root.hzText(root.band.hz).toUpperCase() : "BAND"
            tip: "Peak raises or lowers the sound around its frequency.\nLow shelf / high shelf raise or lower everything below /\nabove it. Q sets how narrow a peak is: higher is narrower.\n+ Band adds a band (up to 31), Remove band flattens it."
            visible: !!root.band

            ButtonGroup {
              width: parent.width
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              options: [
                { value: "peak", label: "Peak" },
                { value: "lowshelf", label: "Low shelf" },
                { value: "highshelf", label: "High shelf" }
              ]
              value: root.band ? root.band.type : "peak"
              onChanged: function (v) { root.k17.setBand(root.currentBand, { type: v }) }
            }

            BandSlider {
              label: "Freq"
              minimum: 1
              maximum: 360
              step: 1
              value: root.band ? root.hzToCode(root.band.hz) : 1
              display: function (v) { return root.hzText(root.codeToHz(v)) }
              onPicked: function (v) { root.k17.setBand(root.currentBand, { hz: Math.round(root.codeToHz(v)) }) }
            }

            BandSlider {
              label: "Gain"
              minimum: -12
              maximum: 12
              step: 0.2
              value: root.band ? root.band.gain : 0
              display: function (v) { return (v > 0 ? "+" : "") + v.toFixed(1) + " dB" }
              onPicked: function (v) { root.k17.setBand(root.currentBand, { gain: Math.round(v * 5) / 5 }) }
            }

            BandSlider {
              label: "Q"
              minimum: 0.2
              maximum: 10
              step: 0.1
              value: root.band ? root.band.q : 0.8
              display: function (v) { return v.toFixed(1) }
              onPicked: function (v) { root.k17.setBand(root.currentBand, { q: Math.round(v * 10) / 10 }) }
            }

            Row {
              spacing: Style.space(8)

              Button {
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                text: "+ Band"
                tooltipText: "Add a band (up to 31)"
                onClicked: { var i = root.k17.addBand(); if (i >= 0) root.eqBand = i }
              }

              Button {
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                text: root.k17 && root.k17.octaveBands.indexOf(root.currentBand) >= 0 ? "Reset band" : "Remove band"
                onClicked: {
                  var octave = root.k17.octaveBands.indexOf(root.currentBand) >= 0
                  root.k17.removeBand(root.currentBand)
                  if (!octave) root.eqBand = -1
                }
              }
            }
          }

          Section {
            title: "IMPORT & BACKUP"
            tip: "Import AutoEQ loads a headphone correction profile\n(ParametricEQ.txt from autoeq.app) into this EQ.\nIt plays live; Save keeps it.\nBack up saves all ten custom EQs to a file, Restore\nwrites them back. Restoring backs up the current EQs first."

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - 2 * parent.spacing) / 3
                bordered: true
                enabled: !!root.k17 && !root.k17.busyText
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                text: root.k17 && root.k17.busyText === "Importing…" ? "Importing…" : "Import AutoEQ…"
                tooltipText: "Load an AutoEQ ParametricEQ.txt into this custom EQ (plays live, Save keeps it)"
                onClicked: root.k17.pickAutoeq()
              }

              Button {
                width: (parent.width - 2 * parent.spacing) / 3
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                // Backing up switches through the EQs, which drops unsaved changes.
                enabled: !!root.k17 && !root.k17.busyText && !root.k17.eqDirty
                opacity: enabled ? 1 : 0.5
                text: root.k17 && root.k17.busyText === "Backing up…" ? "Backing up…" : "Back up…"
                tooltipText: root.k17 && root.k17.eqDirty ? "Save or discard your changes first"
                  : "Save all ten custom EQs to a file. The K17 briefly switches through them."
                onClicked: root.k17.pickBackup()
              }

              Button {
                width: (parent.width - 2 * parent.spacing) / 3
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: !!root.k17 && !root.k17.busyText && !root.k17.eqDirty
                opacity: enabled ? 1 : 0.5
                text: root.k17 && root.k17.busyText === "Restoring…" ? "Restoring…" : "Restore…"
                tooltipText: root.k17 && root.k17.eqDirty ? "Save or discard your changes first"
                  : "Write custom EQs from a backup file back to the K17. The current ones are backed up first."
                onClicked: root.k17.pickRestore()
              }
            }

            SectionText {
              width: parent.width
              text: root.k17 && root.k17.lastMessage ? root.k17.lastMessage
                : root.k17 && root.k17.backups.length
                  ? "Last backup " + root.k17.backups[0].created.replace("T", " ").slice(0, 16)
                    + (root.k17.backups[0].names.length ? " · " + root.k17.backups[0].names.join(", ") : "")
                  : "No backup yet."
              color: root.dim
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Row {
            width: parent.width
            spacing: Style.space(8)

            // Resetting stores the flat EQ on the device right away, so it
            // takes a second click within a few seconds.
            Button {
              id: resetButton
              property bool armed: false
              width: (parent.width - 2 * parent.spacing) / 3
              bordered: true
              selected: armed
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              text: armed ? "Sure?" : "Reset"
              tooltipText: "Flatten this custom EQ (all bands to 0 dB).\nStored on the K17 at once; click twice to confirm."
              onClicked: {
                if (!armed) { armed = true; disarm.restart(); return }
                armed = false
                root.k17.resetEq()
              }

              Timer {
                id: disarm
                interval: 3000
                onTriggered: resetButton.armed = false
              }
            }

            Button {
              width: (parent.width - 2 * parent.spacing) / 3
              bordered: true
              enabled: !!root.k17 && root.k17.eqDirty
              opacity: enabled ? 1 : 0.5
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              text: "Discard"
              tooltipText: "Undo all changes since the last save"
              onClicked: root.k17.discardEq()
            }

            Button {
              width: (parent.width - 2 * parent.spacing) / 3
              bordered: true
              selected: !!root.k17 && root.k17.eqDirty
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              text: "Save"
              tooltipText: "Store this EQ on the K17. Changes play live\nbut are lost when you switch EQs without saving."
              onClicked: root.k17.saveEq()
            }
          }

        }

        // ================= Settings =================
        Column {
          width: parent.width
          spacing: Style.space(14)
          visible: root.view === "settings"

          Section {
            title: "CONNECTION"

            Item {
              width: parent.width
              implicitHeight: hostField.implicitHeight

              TextField {
                id: hostField
                anchors.left: parent.left
                anchors.right: searchButton.left
                anchors.rightMargin: Style.space(8)
                foreground: root.bar.foreground
                placeholderText: "IP address (K17: Settings > About)"
                text: root.value("host")
                Hint {
                  show: hostField.hovered
                  text: "Network address of the K17.\nYou find it on the K17 under Settings > About.\nPress Enter to connect."
                }
                onAccepted: root.save("host", text.trim())
                onEditingFinished: if (text.trim() !== root.value("host")) root.save("host", text.trim())
              }

              Button {
                id: searchButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                text: root.k17 && root.k17.searching ? "Searching…" : "Search"
                tooltipText: "Looks for K17s in this network for a few seconds.\nIt only finds a K17 in the same network segment that\nno other app (or computer) is connected to right now."
                enabled: !!root.k17 && !root.k17.searching
                onClicked: { searchResult.searched = true; root.k17.discover() }
              }
            }

            // Search results: pick one, or a short note when nothing was found.
            Flow {
              id: searchResult
              property bool searched: false
              width: parent.width
              spacing: Style.space(8)
              visible: searched && !!root.k17 && !root.k17.searching

              Repeater {
                model: root.k17 ? root.k17.found : []

                Button {
                  required property var modelData
                  bordered: true
                  selected: modelData.host === root.value("host")
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  text: modelData.host
                  onClicked: root.save("host", modelData.host)
                }
              }

              SectionText {
                visible: !!root.k17 && root.k17.found.length === 0
                width: parent.width
                text: "No K17 found in this network. Enter its address instead."
                color: root.dim
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            SettingRow {
              label: "Release for the FiiO app"
              tip: "The K17 accepts only one network connection at a time,\nand this plugin holds it. Turn this on to use the\nFiiO Control app on your phone, and off again afterwards\nso the plugin reconnects. While on, the bar shows 󰏤."
              checked: root.value("releaseForApp")
              onToggled: root.save("releaseForApp", !root.value("releaseForApp"))
            }
          }

          Section {
            title: "BAR SHOWS"

            Row {
              spacing: Style.space(8)

              Repeater {
                model: [
                  { key: "barInput", label: "Input", tip: "Show the active input in the bar, e.g. BAL or USB." },
                  { key: "barEq", label: "EQ", tip: "Show the active EQ in the bar, e.g. Jazz or your custom name." },
                  { key: "barVolume", label: "Volume", tip: "Show the K17 volume in the bar (0-100)." }
                ]

                Button {
                  required property var modelData
                  bordered: true
                  selected: root.value(modelData.key)
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  text: (root.value(modelData.key) ? "✓ " : "") + modelData.label
                  tooltipText: modelData.tip + "\nItems with ✓ are shown. With none selected\nthe bar shows just K17, dimmed while not connected."
                  onClicked: root.save(modelData.key, !root.value(modelData.key))
                }
              }
            }
          }

          Section {
            title: "VOLUME KEYS"

            SettingRow {
              label: "Control the K17"
              tip: "Your keyboard's volume and mute keys change the K17\ninstead of the system volume, with the usual on-screen display.\nIf the K17 is off or unreachable, they fall back to the\nsystem volume. Needs the key bindings from the README."
              checked: root.value("volumeKeys")
              onToggled: root.save("volumeKeys", !root.value("volumeKeys"))
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(limitLabel.implicitHeight, limitSlider.implicitHeight)

              HoverHandler { id: limitHover }
              Hint {
                show: limitHover.hovered
                text: "Volume keys and scrolling on the bar never raise\nthe K17 above this level. If the knob is already set\nhigher, that level is kept and the keys only turn it down."
              }

              SectionText {
                id: limitLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Limit  <font color='" + root.dim + "'>󰋽</font>"
                textFormat: Text.StyledText
              }

              PanelSlider {
                id: limitSlider
                bar: root.bar
                anchors.left: limitLabel.right
                anchors.leftMargin: Style.space(10)
                anchors.right: limitText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                minimum: 0
                maximum: 100
                step: 1
                integer: true
                value: root.value("keyMaxVolume")
                onReleased: function (v) { root.save("keyMaxVolume", Math.round(v)) }
              }

              SectionText {
                id: limitText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                horizontalAlignment: Text.AlignRight
                text: String(Math.round(limitSlider.dragging ? limitSlider.liveValue : limitSlider.value))
                font.bold: true
              }
            }
          }

          Section {
            title: "OUTPUT"

            SettingRow {
              label: "Auto-switch to K17 USB"
              tip: "When you set the K17's input to USB, it appears on this\ncomputer as a sound card. This makes it the default\noutput automatically, and switches back to the previous\noutput when the K17 leaves USB mode."
              checked: root.value("usbAuto")
              onToggled: root.save("usbAuto", !root.value("usbAuto"))
            }
          }
        }
      }
      }
    }
  }
}
