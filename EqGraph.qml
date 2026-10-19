import QtQuick
import qs.Commons

// Graphic view of the custom EQ editor on a log frequency axis (20 Hz-20 kHz):
// one bar per shown band at its frequency, and the combined response of all
// bands as a curve. Click near a bar to select the band, drag up or down to
// change its gain.
Item {
  id: g

  property var bands: []          // [{ band, gain, hz, q, type }]
  property int selected: -1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real range: 12         // dB above and below 0

  signal picked(int band)
  signal gainDragged(int band, real gain)

  implicitHeight: Style.space(190)

  readonly property color dim: Qt.darker(foreground, 1.8)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property real axisW: Style.space(28)
  readonly property real plotLeft: axisW + Style.space(10)
  readonly property real plotRight: width - Style.space(10)
  readonly property real plotTop: Style.space(18)
  readonly property real plotBottom: height - Style.space(20)
  readonly property real barW: Math.max(4, Style.space(10))

  function xFor(hz) {
    return plotLeft + (plotRight - plotLeft) * Math.log(Math.max(20, Math.min(20000, hz)) / 20) / Math.log(1000)
  }
  function yFor(db) {
    var d = Math.max(-range, Math.min(range, db))
    return plotTop + (range - d) / (2 * range) * (plotBottom - plotTop)
  }
  function dbAt(y) {
    var db = range - (y - plotTop) / (plotBottom - plotTop) * 2 * range
    return Math.max(-range, Math.min(range, Math.round(db * 5) / 5))
  }
  function shortHz(hz) {
    if (hz < 1000) return String(Math.round(hz))
    var k = hz / 1000
    return (k < 10 ? Math.round(k * 10) / 10 : Math.round(k)) + "k"
  }
  function dbText(db) {
    return db === 0 ? "0" : (db > 0 ? "+" : "") + db.toFixed(1)
  }
  // Bands whose labels fit without overlapping a neighbour; the selected band
  // always keeps its label and pushes overlapping neighbours out.
  readonly property var labeled: {
    var gap = Style.space(34)
    var order = bands.slice().sort(function (a, b) { return a.hz - b.hz })
    var sel = null
    for (var i = 0; i < order.length; i++) if (order[i].band === selected) sel = order[i]
    var kept = sel ? [xFor(sel.hz)] : []
    var out = {}
    if (sel) out[sel.band] = true
    for (var j = 0; j < order.length; j++) {
      var x = xFor(order[j].hz), ok = true
      if (order[j] === sel) continue
      for (var k = 0; k < kept.length; k++) if (Math.abs(kept[k] - x) < gap) { ok = false; break }
      if (ok) { kept.push(x); out[order[j].band] = true }
    }
    return out
  }

  function nearestBand(x) {
    var best = -1, bestD = 1e9
    for (var i = 0; i < bands.length; i++) {
      var d = Math.abs(xFor(bands[i].hz) - x)
      if (d < bestD) { bestD = d; best = bands[i].band }
    }
    return best
  }

  // Response of one RBJ biquad (peak / low shelf / high shelf) at frequency f, in dB.
  function biquadDb(b, f) {
    var fs = 96000
    var A = Math.pow(10, b.gain / 40)
    var w0 = 2 * Math.PI * b.hz / fs
    var cw = Math.cos(w0), alpha = Math.sin(w0) / (2 * Math.max(0.1, b.q))
    var sA = 2 * Math.sqrt(A) * alpha
    var b0, b1, b2, a0, a1, a2
    if (b.type === "lowshelf") {
      b0 = A * ((A + 1) - (A - 1) * cw + sA); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - sA)
      a0 = (A + 1) + (A - 1) * cw + sA; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - sA
    } else if (b.type === "highshelf") {
      b0 = A * ((A + 1) + (A - 1) * cw + sA); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - sA)
      a0 = (A + 1) - (A - 1) * cw + sA; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - sA
    } else {
      b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
      a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
    }
    var w = 2 * Math.PI * f / fs
    var c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w)
    var nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2)
    var dr = a0 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2)
    return 10 * Math.log((nr * nr + ni * ni) / (dr * dr + di * di)) / Math.LN10
  }

  onBandsChanged: curve.requestPaint()
  onWidthChanged: curve.requestPaint()
  onHeightChanged: curve.requestPaint()

  // Grid lines with dB labels.
  Repeater {
    model: [g.range, g.range / 2, 0, -g.range / 2, -g.range]

    Item {
      required property var modelData
      width: g.width
      height: 1
      y: g.yFor(modelData)

      Rectangle {
        x: g.axisW
        width: parent.width - g.axisW
        height: 1
        color: modelData === 0 ? g.dim : g.faint
      }

      Text {
        anchors.right: parent.left
        anchors.rightMargin: -g.axisW + Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: (modelData > 0 ? "+" : "") + modelData
        color: g.dim
        font.family: g.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Selected band highlight.
  Rectangle {
    readonly property var sel: {
      for (var i = 0; i < g.bands.length; i++) if (g.bands[i].band === g.selected) return g.bands[i]
      return null
    }
    visible: !!sel
    x: sel ? g.xFor(sel.hz) - width / 2 : 0
    y: g.plotTop - Style.space(4)
    width: g.barW + Style.space(14)
    height: g.plotBottom - g.plotTop + Style.space(8)
    radius: Style.cornerRadius > 0 ? Style.space(4) : 0
    color: g.faint
  }

  Repeater {
    model: g.bands

    Item {
      id: col
      required property var modelData
      readonly property bool isSelected: modelData.band === g.selected
      readonly property real barY: Math.min(g.yFor(modelData.gain), g.yFor(0))
      readonly property real barH: Math.max(2, Math.abs(g.yFor(modelData.gain) - g.yFor(0)))
      readonly property real cx: g.xFor(modelData.hz)

      Rectangle {
        x: col.cx - width / 2
        y: col.barY
        width: g.barW
        height: col.barH
        radius: Style.cornerRadius > 0 ? Math.min(width / 2, Style.space(3)) : 0
        color: col.isSelected ? g.foreground : g.dim
        opacity: 0.85
      }

      Text {
        x: col.cx - width / 2
        y: col.modelData.gain >= 0 ? col.barY - height - Style.space(1) : col.barY + col.barH + Style.space(1)
        visible: (col.modelData.gain !== 0 || col.isSelected) && !!g.labeled[col.modelData.band]
        text: g.dbText(col.modelData.gain)
        color: col.isSelected ? g.foreground : g.dim
        font.family: g.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        x: col.cx - width / 2
        y: g.plotBottom + Style.space(5)
        visible: !!g.labeled[col.modelData.band]
        text: g.shortHz(col.modelData.hz) + (col.modelData.type === "lowshelf" ? "◢" : col.modelData.type === "highshelf" ? "◣" : "")
        color: col.isSelected ? g.foreground : g.dim
        font.family: g.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: col.isSelected
      }
    }
  }

  // Combined response of every band that is in use.
  Canvas {
    id: curve
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var active = g.bands.filter(function (b) { return b.gain !== 0 })
      var steps = Math.max(2, Math.round(g.plotRight - g.plotLeft) / 3)
      var pts = []
      for (var i = 0; i <= steps; i++) {
        var x = g.plotLeft + (g.plotRight - g.plotLeft) * i / steps
        var f = 20 * Math.pow(1000, i / steps)
        var db = 0
        for (var j = 0; j < active.length; j++) db += g.biquadDb(active[j], f)
        pts.push([x, g.yFor(db)])
      }
      // Soft fill between the curve and 0 dB, then the line on top.
      ctx.beginPath()
      ctx.moveTo(pts[0][0], g.yFor(0))
      for (var k = 0; k < pts.length; k++) ctx.lineTo(pts[k][0], pts[k][1])
      ctx.lineTo(pts[pts.length - 1][0], g.yFor(0))
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(g.foreground.r, g.foreground.g, g.foreground.b, 0.08)
      ctx.fill()
      ctx.beginPath()
      for (var m = 0; m < pts.length; m++) m === 0 ? ctx.moveTo(pts[m][0], pts[m][1]) : ctx.lineTo(pts[m][0], pts[m][1])
      ctx.lineWidth = Math.max(1.5, Style.space(2))
      ctx.strokeStyle = g.foreground
      ctx.lineJoin = "round"
      ctx.stroke()
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    property int dragging: -1
    onPressed: function (mouse) {
      dragging = g.nearestBand(mouse.x)
      if (dragging >= 0) g.picked(dragging)
    }
    onPositionChanged: function (mouse) {
      if (!pressed || dragging < 0) return
      g.gainDragged(dragging, g.dbAt(mouse.y))
    }
    onReleased: dragging = -1
  }
}
