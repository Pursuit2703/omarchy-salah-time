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
  readonly property string remindersFile: Quickshell.env("HOME") + "/.config/omarchy-salah-time/reminders.json"
  readonly property string soundFile: root.pluginDir + "assets/ping.ogg"

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
  // Vertical bar: the prayer's first letter in a filled pill, then the time
  // left (h:mm, or just minutes in the last hour).
  property string verticalBadge: ""
  property var verticalTime: ["—"]
  // 0..1, how far we are from the previous prayer to the next one; drawn as
  // the ring around the letter on a vertical bar.
  property real verticalProgress: 0

  // Reminders and sound-on-off are managed by right-click > Manage Reminders,
  // which edits remindersFile directly (scripts/manage_reminders.sh). Default
  // here matches the file's own default, used only until that file exists.
  readonly property var defaultReminders: [{ id: "default", scope: "all", offsetMinutes: 10 }]
  property var reminders: defaultReminders
  property bool soundEnabled: true
  property int soundVolume: 50

  property string notifiedDate: ""
  property var notifiedKeys: ({})

  implicitWidth: vertical ? barSize : labelDisplay.implicitWidth + Style.space(16)
  implicitHeight: vertical ? verticalColumn.implicitHeight + Style.space(6) : barSize

  function dateKeyOf(date) {
    return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate()
  }

  function maybeNotify(times, now, dateKey) {
    if (!root.reminders || root.reminders.length === 0) return

    if (root.notifiedDate !== dateKey) {
      root.notifiedDate = dateKey
      root.notifiedKeys = ({})
    }

    const nowMinutes = now.getHours() * 60 + now.getMinutes()
    let firedAny = false

    for (const reminder of root.reminders) {
      for (const ev of root.events) {
        if (reminder.scope !== "all" && reminder.scope !== ev.key) continue

        const eventMinute = root.minutesOf(times[ev.key])
        if (eventMinute === null) continue
        const offset = Number(reminder.offsetMinutes)
        const targetMinute = eventMinute - offset
        if (targetMinute < 0 || targetMinute > 1439 || targetMinute !== nowMinutes) continue

        const key = dateKey + ":" + reminder.id + ":" + ev.key
        if (root.notifiedKeys[key]) continue
        root.notifiedKeys[key] = true

        const eventTime = times[ev.key]
        // A bar-widget instance runs once per connected monitor, all on the
        // same reminder clock, so every instance reaches this point in the
        // same tick. claim_and_notify.sh arbitrates with an atomic mkdir so
        // exactly one of them actually sends the notification and sound,
        // no matter how many monitors are attached. Spawned as its own
        // short-lived Process (rather than reusing one shared instance)
        // so two reminders firing in the same tick don't clobber each other.
        const claim = claimProcComponent.createObject(root, { command: [
          "bash", root.pluginDir + "scripts/claim_and_notify.sh",
          key,
          ev.label + " reminder",
          ev.label + " starts in " + offset + " min (" + eventTime + ").",
          root.soundEnabled ? "1" : "0",
          root.soundFile,
          String(root.soundVolume)
        ] })
        if (claim) claim.running = true
      }
    }
  }

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

  // One unit per line, so no line is wider than the clock's two digits.
  function verticalDuration(totalSeconds) {
    const sec = Math.max(0, Math.floor(totalSeconds))
    const h = Math.floor(sec / 3600)
    const m = Math.floor((sec % 3600) / 60)
    if (h > 0) return [h + "h", m + "m"]
    if (m > 0) return [m + "m"]
    return ["now"]
  }

  function updateDisplay() {
    if (!root.scheduleData || !root.scheduleData.times) {
      root.labelText = "Salah"
      root.verticalBadge = ""
      root.verticalTime = ["—"]
      return
    }

    const times = root.scheduleData.times
    const now = new Date()
    const nowMinutes = now.getHours() * 60 + now.getMinutes()
    const nowSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()

    root.maybeNotify(times, now, root.dateKeyOf(now))

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
      root.verticalBadge = ""
      root.verticalTime = ["—"]
      return
    }

    let targetSeconds = chosen.minute * 60
    if (targetSeconds < nowSeconds) targetSeconds += 86400
    const remaining = targetSeconds - nowSeconds

    root.labelText = chosen.label + " · " + root.formatDuration(remaining)
    root.verticalBadge = chosen.label.charAt(0)
    root.verticalTime = root.verticalDuration(remaining)

    let prevMinute = null
    for (const ev of root.events) {
      const minute = root.minutesOf(times[ev.key])
      if (minute === null) continue
      if (minute <= nowMinutes && (prevMinute === null || minute > prevMinute)) prevMinute = minute
    }
    if (prevMinute === null) {
      for (const ev of root.events) {
        const minute = root.minutesOf(times[ev.key])
        if (minute !== null && (prevMinute === null || minute > prevMinute)) prevMinute = minute
      }
      if (prevMinute !== null) prevMinute -= 1440
    }
    const span = prevMinute === null ? 0 : targetSeconds - prevMinute * 60
    root.verticalProgress = span > 0 ? Math.max(0, Math.min(1, 1 - remaining / span)) : 0
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

  FileView {
    id: remindersView
    path: root.remindersFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        const parsed = JSON.parse(text())
        root.reminders = Array.isArray(parsed.reminders) ? parsed.reminders : root.defaultReminders
        root.soundEnabled = parsed.soundEnabled !== false
        root.soundVolume = Number.isFinite(parsed.soundVolume) ? parsed.soundVolume : 50
      } catch (e) {
        root.reminders = root.defaultReminders
        root.soundEnabled = true
        root.soundVolume = 50
      }
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
    id: settingsProc
    command: ["bash", root.pluginDir + "scripts/settings_menu.sh"]
    onExited: {
      scheduleView.reload()
      remindersView.reload()
    }
  }

  Component {
    id: claimProcComponent
    Process {
      running: false
      onExited: destroy()
    }
  }

  Text {
    id: labelDisplay
    visible: !root.vertical
    anchors.centerIn: parent
    text: root.labelText
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground
  readonly property string barFont: root.bar ? root.bar.fontFamily : Style.font.family

  Column {
    id: verticalColumn
    visible: root.vertical
    anchors.centerIn: parent
    width: root.barSize

    // The next prayer's letter inside a ring that fills clockwise from the
    // previous prayer to this one.
    Item {
      visible: root.verticalBadge !== ""
      width: verticalColumn.width
      height: Style.bar.iconSlot

      Canvas {
        id: ring
        anchors.centerIn: parent
        width: Math.round(Style.bar.iconSlot * 0.8)
        height: width
        readonly property real progress: root.verticalProgress
        readonly property color tint: root.fg
        onProgressChanged: requestPaint()
        onTintChanged: requestPaint()
        onPaint: {
          const ctx = getContext("2d")
          ctx.reset()
          const r = width / 2 - 1.5
          ctx.lineWidth = 1.6
          ctx.strokeStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
          ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI); ctx.stroke()
          ctx.strokeStyle = root.fg
          ctx.beginPath()
          ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * progress)
          ctx.stroke()
        }
      }

      OpticalGlyph {
        anchors.fill: parent
        text: root.verticalBadge
        fontFamily: root.barFont
        fontSize: Style.font.body * 0.8
        color: root.fg
      }
    }

    Repeater {
      model: root.verticalTime

      OpticalGlyph {
        required property string modelData
        width: verticalColumn.width
        height: Math.round(Style.bar.iconSlot * 0.8)
        text: modelData
        fontFamily: root.barFont
        fontSize: modelData.length > 2 ? Style.font.body * 0.85 : Style.font.body
        color: root.fg
      }
    }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = root
    target.hostWidget = root
    target.scheduleData = root.scheduleData
    target.reminders = root.reminders
    target.soundEnabled = root.soundEnabled
    target.soundVolume = root.soundVolume
  }

  onBarChanged: injectPanel()
  onScheduleDataChanged: if (panelLoader.item) panelLoader.item.scheduleData = root.scheduleData
  onRemindersChanged: if (panelLoader.item) panelLoader.item.reminders = root.reminders
  onSoundEnabledChanged: if (panelLoader.item) panelLoader.item.soundEnabled = root.soundEnabled
  onSoundVolumeChanged: if (panelLoader.item) panelLoader.item.soundVolume = root.soundVolume

  readonly property bool panelOpen: panelLoader.item ? panelLoader.item.opened === true : false

  // The bar and KeyboardPanel treat this widget as the popup's owner: they
  // close it through close() and read opened back, so these must exist or
  // the panel's open binding gets overwritten and it never shows again.
  readonly property bool opened: panelOpen
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  // On a vertical bar the open-panel mark is one icon long, like the
  // clock's, not a rule running the height of the whole stack.
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Connections {
    target: panelLoader.item
    function onRefreshRequested() { refreshProc.running = true }
    function onSettingsRequested() {
      if (panelLoader.item) panelLoader.item.close()
      settingsProc.running = true
    }
  }

  // A stock button, not a bare MouseArea: it registers with the bar as a
  // click target, which is what gives the pointing-hand cursor and lets the
  // bar's own pointer layer forward presses to it.
  WidgetButton {
    id: hoverArea
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    onPressed: function(button) {
      if (button === Qt.RightButton) {
        if (panelLoader.item) panelLoader.item.openSettings()
      } else {
        root.togglePanel()
      }
    }
  }

}
