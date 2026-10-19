import QtQuick

// Flat line drawing of the K17's front panel in the theme's foreground colour:
// chassis, display on the left with two headphone jacks below it, and the big
// volume knob on the right.
Canvas {
  id: icon

  property color color: "white"
  property real size: 16          // height; the icon is 1.6 times as wide

  implicitHeight: size
  implicitWidth: Math.round(size * 1.6)

  onColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var w = width, h = height
    var lw = Math.max(1, Math.round(h / 11))
    var half = lw / 2
    ctx.strokeStyle = icon.color
    ctx.fillStyle = icon.color
    ctx.lineWidth = lw

    // Chassis.
    var r = h * 0.14
    ctx.beginPath()
    ctx.roundedRect(half, h * 0.12 + half, w - lw, h * 0.76 - lw, r, r)
    ctx.stroke()

    // Volume knob with its position marker.
    var kx = w * 0.72, ky = h / 2, kr = h * 0.26
    ctx.beginPath()
    ctx.arc(kx, ky, kr, 0, Math.PI * 2)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(kx, ky - kr * 0.35)
    ctx.lineTo(kx, ky - kr * 0.85)
    ctx.stroke()

    // Display.
    ctx.fillRect(w * 0.14, h * 0.3, w * 0.24, h * 0.2)

    // Headphone jacks.
    var jr = Math.max(lw * 0.8, h * 0.06)
    ctx.beginPath()
    ctx.arc(w * 0.18, h * 0.66, jr, 0, Math.PI * 2)
    ctx.fill()
    ctx.beginPath()
    ctx.arc(w * 0.34, h * 0.66, jr, 0, Math.PI * 2)
    ctx.fill()
  }
}
