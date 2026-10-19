import QtQuick
import Quickshell
import Quickshell.Io

// Shared state for every bar instance. Runs the plugin's k17-vol daemon, which
// owns the single network connection the K17 allows, polls its status, and
// queues commands. Settings come from the bar widget entry (shell.json) and are
// sent along with every status poll, so the daemon never has its own config.
Item {
  id: root

  // Injected by Omarchy's generic service loader.
  property var shell: null
  property bool panelOpen: false
  // Set by the `settings` / `editEq` IPC calls; the panel opens on that view.
  property string requestedView: ""
  property var settings: ({})

  readonly property string cli: String(Qt.resolvedUrl("bin/k17-vol")).replace(/^file:\/\//, "")

  // Setting defaults come from manifest.json (barWidget.defaults), the single
  // place they are declared for the shell and the panel.
  property var defaults: ({})
  property bool defaultsReady: false
  FileView {
    path: String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, "")
    blockLoading: true
    onLoaded: {
      try { root.defaults = JSON.parse(text()).barWidget.defaults } catch (e) { root.defaults = {} }
      root.defaultsReady = true
    }
  }

  property var status: ({})
  readonly property bool online: !!status.online
  readonly property string host: settings.host || ""
  readonly property bool released: !!settings.releaseForApp
  readonly property int volume: status.volume !== undefined ? status.volume : -1
  readonly property int eq: status.eq !== undefined ? status.eq : -1
  readonly property int input: status.input !== undefined ? status.input : -1
  readonly property var eqs: status.eqs || []
  readonly property var inputs: status.inputs || []
  readonly property string error: status.error || ""
  readonly property bool muted: online && volume === 0
  readonly property bool eqEditable: eq >= 0xA0 && eq <= 0xA9
  // Short EQ text for the bar: preset name, custom EQ name, or "Custom N".
  readonly property string eqShort: {
    if (eq === 0xFF) return "EQ off"
    for (var i = 0; i < eqs.length; i++) {
      if (eqs[i].value !== eq) continue
      var at = eqs[i].label.indexOf(" · ")
      return at >= 0 ? eqs[i].label.slice(at + 3) : eqs[i].label
    }
    return ""
  }

  // Name of the active custom EQ ("" when unnamed); labels read "Custom 2 · Name".
  readonly property string eqName: {
    for (var i = 0; i < eqs.length; i++) {
      if (eqs[i].value !== eq) continue
      var at = eqs[i].label.indexOf(" · ")
      return at >= 0 ? eqs[i].label.slice(at + 3) : ""
    }
    return ""
  }

  // EQ editor: all bands of the active custom EQ, which of them the editor
  // shows, and whether live changes have not been stored on the device yet.
  property var eqBands: []
  property var eqShown: []
  property bool eqDirty: false

  // The K17 drops unsaved band edits when the EQ changes.
  onEqChanged: eqDirty = false

  function bandActive(b) { return b.gain !== 0 || b.type !== "peak" }

  // The presets are 10-band graphic EQs on bands 2, 5, ..., 29 (31 Hz to 16 kHz);
  // the editor always shows those and adds any other band that is in use.
  readonly property var octaveBands: [2, 5, 8, 11, 14, 17, 20, 23, 26, 29]
  // Unused bands (0-30) sit at 1, 12, 24, ... 360 on the device's frequency scale.
  function defaultHz(i) { return Math.round(20 * Math.pow(10, ((i === 0 ? 1 : i * 12) - 1) / 120)) }
  function shownBands(bands) {
    var shown = root.octaveBands.slice()
    for (var i = 0; i < bands.length; i++)
      if (bandActive(bands[i]) && shown.indexOf(i) < 0) shown.push(i)
    return shown.sort(function (a, b) { return a - b })
  }

  function loadBands() {
    if (bandsProc.running) return
    bandsProc.command = [root.cli, "eqbands"]
    bandsProc.running = true
  }

  function setBand(i, fields) {
    var next = root.eqBands.slice()
    next[i] = Object.assign({}, next[i], fields)
    delete next[i].raw                       // changed: the daemon re-encodes this band
    if ("hz" in fields) delete next[i].code  // and places the new frequency
    root.eqBands = next
    root.eqDirty = true
    run(["eqset", JSON.stringify(next)])
  }

  function addBand() {
    for (var i = 0; i < root.eqBands.length; i++) {
      if (root.eqShown.indexOf(i) < 0 && !bandActive(root.eqBands[i])) {
        root.eqShown = root.eqShown.concat([i]).sort(function (a, b) { return a - b })
        return i
      }
    }
    return -1
  }

  // Octave bands go back to their default; extra bands are flattened and hidden.
  function removeBand(i) {
    setBand(i, { gain: 0, type: "peak", hz: defaultHz(i), q: 0.8 })
    if (root.octaveBands.indexOf(i) < 0)
      root.eqShown = root.eqShown.filter(function (x) { return x !== i })
  }

  function renameEq(name) {
    if (!eqEditable) return
    var slot = root.eq
    patch({ eqs: root.eqs.map(function (e) {
      return e.value === slot ? { value: e.value, label: e.label.split(" · ")[0] + (name ? " · " + name : "") } : e
    }) })
    run(["eqname", "0x" + slot.toString(16), name])
  }

  function discardEq() { root.eqDirty = false; run(["eqdiscard"]); root._reloadBands = true }

  // ---- Backups and discovery (long-running; results arrive asynchronously) ----
  property var backups: []
  property var found: []
  property bool searching: discoverProc.running
  property string busyText: ""      // "Backing up…", "Restoring…" while one runs
  property string lastMessage: ""

  // System file dialogs (desktop portal) for AutoEQ import and backups.
  readonly property string backupDir: Quickshell.env("HOME") + "/.local/share/fiio-k17/backups"
  property string _pickFor: ""
  function _pick(purpose, args) {
    if (pickProc.running || jobProc.running) return
    root._pickFor = purpose
    pickProc.command = [root.cli, "pick"].concat(args)
    pickProc.running = true
  }
  function pickAutoeq() { _pick("autoeq", ["open", "Import AutoEQ profile", "*.txt", Quickshell.env("HOME") + "/Downloads"]) }
  function pickBackup() {
    var stamp = new Date().toISOString().slice(0, 19).replace(/[-:]/g, "").replace("T", "-")
    _pick("backup", ["save", "Back up custom EQs", "*.json", root.backupDir, "k17-eq-" + stamp + ".json"])
  }
  function pickRestore() { _pick("restore", ["open", "Restore custom EQs", "*.json", root.backupDir]) }

  function importAutoeq(path) {
    if (!eqEditable) return
    root.eqDirty = true
    _job("Importing…", ["eqautoeq", path])
  }

  function loadBackups() {
    if (!backupsProc.running) { backupsProc.command = [root.cli, "eqbackups"]; backupsProc.running = true }
  }
  function backupNow(path) { _job("Backing up…", path ? ["eqbackup", path] : ["eqbackup"]) }
  function restoreBackup(path) { _job("Restoring…", ["eqrestore", path]) }
  function discover() {
    if (discoverProc.running) return
    root.found = []
    discoverProc.command = [root.cli, "discover", "4"]
    discoverProc.running = true
  }
  function _job(text, args) {
    if (jobProc.running) return
    root.busyText = text
    root.lastMessage = ""
    jobProc.command = [root.cli].concat(args)
    jobProc.running = true
  }

  function saveEq() { root.eqDirty = false; run(["eqsave"]) }
  function resetEq() { root.eqDirty = false; run(["eqreset"]); root._reloadBands = true }
  property bool _reloadBands: false

  readonly property string inputShort: {
    for (var i = 0; i < inputs.length; i++)
      if (inputs[i].value === input) return inputs[i].short
    return ""
  }

  property var _queue: []

  // Persist one setting on the widget's shell.json entry; the shell then hands
  // the new settings back to the bar widget, which calls configure().
  function save(key, value) {
    var next = Object.assign({}, root.settings)
    next[key] = value
    if (root.shell) root.shell.updateEntryInline("io.github.homelabsealinsideout.fiio-k17", next)
  }

  function configure(s) {
    root.settings = s || {}
    root.refresh()
  }

  function refresh() {
    if (statusProc.running || actionProc.running) return
    statusProc.command = [root.cli, "status", JSON.stringify(root.settings)]
    statusProc.running = true
  }

  // Optimistic update so controls don't snap back while the command runs.
  function patch(fields) {
    root.status = Object.assign({}, root.status, fields)
  }

  function run(args) {
    // A newer command of the same kind supersedes a queued one (slider drags).
    root._queue = root._queue.filter(function (a) { return a[0] !== args[0] })
    root._queue.push(args)
    root._next()
  }

  function _next() {
    if (actionProc.running || root._queue.length === 0) return
    actionProc.command = [root.cli].concat(root._queue.shift())
    actionProc.running = true
  }

  function setVolume(v) { patch({ volume: v }); run(["set", String(v)]) }
  function stepVolume(up) { run([up ? "up" : "down"]) }
  function toggleMute() { run(["mute"]) }
  function setInput(n) { patch({ input: n }); run(["input", String(n)]) }
  function setEq(v) { patch({ eq: v }); run(["eq", String(v)]) }

  Process {
    id: daemonProc
    command: [root.cli, "daemon"]
    running: true
    stderr: SplitParser {
      onRead: function (line) { console.info("io.github.homelabsealinsideout.fiio-k17:", line) }
    }
    onExited: restartTimer.start()
  }

  Timer {
    id: restartTimer
    interval: 2000
    onTriggered: daemonProc.running = true
  }

  Timer {
    interval: root.panelOpen ? 1500 : 4000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.status = JSON.parse(String(text || "{}"))
        } catch (e) {
          root.status = { error: "daemon not ready" }
        }
      }
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg) console.warn("io.github.homelabsealinsideout.fiio-k17:", msg)
      }
    }
    onExited: {
      if (root._queue.length > 0) root._next()
      else if (root._reloadBands) { root._reloadBands = false; root.loadBands() }
      else root.refresh()
    }
  }

  Process {
    id: jobProc
    stdout: StdioCollector { id: jobOut }
    stderr: StdioCollector { id: jobErr }
    onExited: function (code) {
      var out = String(jobOut.text || "").trim()
      if (code !== 0) {
        root.lastMessage = String(jobErr.text || "").trim().replace(/^k17-vol: (error: )?/, "")
        if (root.busyText === "Importing…") root.eqDirty = false  // nothing was applied
      }
      else if (root.busyText === "Backing up…") root.lastMessage = "Saved " + out.split("/").pop()
      else if (root.busyText === "Importing…") {
        try {
          var a = JSON.parse(out)
          root.lastMessage = "Imported " + a.filters + " filters, not saved yet."
            + (a.preamp < 0 ? " The profile asks for " + a.preamp.toFixed(1) + " dB preamp; the K17 has none, so leave some volume headroom." : "")
        } catch (e) { root.lastMessage = out }
        root.loadBands()
      }
      else {
        try {
          var r = JSON.parse(out)
          root.lastMessage = "Restored " + r.restored.length + " EQs. Previous state saved as " + r.backup.split("/").pop()
        } catch (e) { root.lastMessage = out }
        if (root.eqEditable) root.loadBands()  // the open editor shows the restored bands
      }
      root.busyText = ""
      root.loadBackups()
      root.refresh()
    }
  }

  Process {
    id: pickProc
    stdout: StdioCollector {
      onStreamFinished: {
        var path = String(text || "").trim()
        if (!path) return  // cancelled
        if (root._pickFor === "autoeq") root.importAutoeq(path)
        else if (root._pickFor === "backup") root.backupNow(path)
        else if (root._pickFor === "restore") root.restoreBackup(path)
      }
    }
  }

  Process {
    id: backupsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.backups = JSON.parse(String(text || "[]")) } catch (e) { root.backups = [] }
      }
    }
  }

  Process {
    id: discoverProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.found = JSON.parse(String(text || "[]")) } catch (e) { root.found = [] }
      }
    }
  }

  Process {
    id: bandsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var bands = JSON.parse(String(text || "[]"))
          root.eqBands = bands
          root.eqShown = root.shownBands(bands)
        } catch (e) {
          root.eqBands = []
          root.eqShown = []
        }
      }
    }
  }

  IpcHandler {
    target: "io.github.homelabsealinsideout.fiio-k17"

    function open(): void { if (root.shell) root.shell.summon("io.github.homelabsealinsideout.fiio-k17") }
    function close(): void { if (root.shell) root.shell.hide("io.github.homelabsealinsideout.fiio-k17") }
    function toggle(): void { if (root.shell) root.shell.toggle("io.github.homelabsealinsideout.fiio-k17") }
    function settings(): void {
      root.requestedView = "settings"
      if (root.shell) root.shell.summon("io.github.homelabsealinsideout.fiio-k17")
    }
    function editEq(): void {
      root.requestedView = "eq"
      if (root.shell) root.shell.summon("io.github.homelabsealinsideout.fiio-k17")
    }
    function refresh(): void { root.refresh() }
    function set(key: string, value: string): void {
      if (!(key in root.settings)) return
      var current = root.settings[key]
      root.save(key, typeof current === "boolean" ? value === "true"
        : typeof current === "number" ? parseInt(value) : value)
    }
  }
}
