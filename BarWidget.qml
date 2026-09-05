import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "pursuit2703.salah-time"

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string scheduleFile: Quickshell.env("HOME") + "/.cache/omarchy-salah-time/schedule.json"

  readonly property var events: [
    { key: "fajr", label: "Fajr" },
    { key: "sunrise", label: "Sun" },
    { key: "dhuhr", label: "Dhuhr" },
    { key: "asr", label: "Asr" },
    { key: "maghrib", label: "Maghrib" },
    { key: "isha", label: "Isha" }
  ]

  property var scheduleData: null
  property string labelText: "Salah"
  property string tooltipText: "Loading prayer times..."

  implicitWidth: labelDisplay.implicitWidth + Style.space(16)
  implicitHeight: barSize

  function minutesOf(hhmm) {
    if (!hhmm || typeof hhmm !== "string") return null
    const m = hhmm.trim().match(/^(\d{1,2}):(\d{2})$/)
    if (!m) return null
    return Number(m[1]) * 60 + Number(m[2])
  }

  function formatDuration(totalSeconds) {
    const sec = Math.max(0, Math.floor(totalSeconds))
    const h = Math.floor(sec / 3600)
    const m = Math.floor((sec % 3600) / 60)
    if (h > 0) return m > 0 ? (h + "h " + m + "m") : (h + "h")
    if (m > 0) return m + "m"
    return "now"
  }

  function updateDisplay() {
    if (!root.scheduleData || !root.scheduleData.times) {
      root.labelText = "Salah"
      root.tooltipText = "No data yet - right-click to pick a city"
      return
    }

    const times = root.scheduleData.times
    const now = new Date()
    const nowMinutes = now.getHours() * 60 + now.getMinutes()
    const nowSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()

    // Find the soonest event at/after now; wrap to first event tomorrow otherwise.
    let chosen = null
    let soonestFallback = null
    for (const ev of root.events) {
      const minute = root.minutesOf(times[ev.key])
      if (minute === null) continue
      if (soonestFallback === null || minute < soonestFallback.minute) {
        soonestFallback = { key: ev.key, label: ev.label, minute: minute }
      }
      if (minute >= nowMinutes && (chosen === null || minute < chosen.minute)) {
        chosen = { key: ev.key, label: ev.label, minute: minute }
      }
    }
    if (!chosen) chosen = soonestFallback
    if (!chosen) {
      root.labelText = "Salah"
      root.tooltipText = "No data yet - right-click to pick a city"
      return
    }

    let targetSeconds = chosen.minute * 60
    if (targetSeconds < nowSeconds) targetSeconds += 86400
    const remaining = targetSeconds - nowSeconds

    root.labelText = chosen.label + " · " + root.formatDuration(remaining)

    const lines = [
      (root.scheduleData.city || "") + " — " + (root.scheduleData.weekday || ""),
      "Next: " + chosen.label + " in " + root.formatDuration(remaining),
      ""
    ]
    for (const ev of root.events) {
      lines.push(ev.label + ": " + (times[ev.key] || "--:--"))
    }
    lines.push("")
    lines.push("Right-click to change city")
    root.tooltipText = lines.join("\n")
  }

  FileView {
    id: scheduleView
    path: root.scheduleFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.scheduleData = JSON.parse(text())
      } catch (e) {
        root.scheduleData = null
      }
      root.updateDisplay()
    }
    onFileChanged: reload()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.updateDisplay()
  }

  // Catches day rollover and does the monthly heavy prefetch when due.
  // Cheap on every run except the first call of a new month.
  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: refreshProc.running = true
  }

  Process {
    id: refreshProc
    command: ["bash", root.pluginDir + "scripts/run_refresh.sh"]
  }

  Process {
    id: pickCityProc
    command: ["bash", root.pluginDir + "scripts/pick_city.sh"]
    onExited: scheduleView.reload()
  }

  Text {
    id: labelDisplay
    anchors.centerIn: parent
    text: root.labelText
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        pickCityProc.running = true
      } else {
        refreshProc.running = true
      }
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
