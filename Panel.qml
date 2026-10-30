import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Salah Time popup: next prayer + live countdown, progress between the
// previous and next time, and the day's six times. BarWidget.qml owns the
// data and the Processes; it sets scheduleData / reminders / soundEnabled and
// connects refreshRequested() / settingsRequested().
Panel {
  id: root
  moduleName: "pursuit2703.salah-time"
  ipcTarget: "pursuit2703.salah-time"
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var scheduleData: null
  property var reminders: []
  property bool soundEnabled: true
  property int soundVolume: 50

  // "main" or "settings". open() always lands on main; openSettings() on settings.
  property string page: "main"

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string remindersFile: homeDir + "/.config/omarchy-salah-time/reminders.json"
  readonly property string configFile: homeDir + "/.config/omarchy-salah-time/config.json"

  property string currentCity: ""
  property var cityList: []
  property bool citiesLoading: false
  property bool cityPickerOpen: false

  readonly property var scopeOptions: [
    { value: "all", label: "All" }, { value: "fajr", label: "Fajr" },
    { value: "sunrise", label: "Sunrise" }, { value: "dhuhr", label: "Dhuhr" },
    { value: "asr", label: "Asr" }, { value: "maghrib", label: "Maghrib" },
    { value: "isha", label: "Isha" }
  ]

  signal refreshRequested()
  signal settingsRequested()

  readonly property var events: [
    { key: "fajr", label: "Fajr", prayer: true },
    { key: "sunrise", label: "Sunrise", prayer: false },
    { key: "dhuhr", label: "Dhuhr", prayer: true },
    { key: "asr", label: "Asr", prayer: true },
    { key: "maghrib", label: "Maghrib", prayer: true },
    { key: "isha", label: "Isha", prayer: true }
  ]

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Commons.Color.accent)
    : Style.selectedFill

  property date now: new Date()

  function minutesOf(text) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(text || ""))
    return m ? Number(m[1]) * 60 + Number(m[2]) : null
  }

  // Day-relative seconds for each event, in order, nulls dropped.
  readonly property var rows: {
    var times = (scheduleData && scheduleData.times) || {}
    var out = []
    for (var i = 0; i < events.length; i++) {
      var ev = events[i]
      var min = minutesOf(times[ev.key])
      out.push({
        key: ev.key, label: ev.label, prayer: ev.prayer,
        text: times[ev.key] || "--:--",
        minute: min
      })
    }
    return out
  }

  readonly property real nowSeconds: now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()

  // Index of the next event today, or -1 when all have passed (next = tomorrow's first).
  readonly property int nextIndex: {
    var secs = nowSeconds
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].minute !== null && rows[i].minute * 60 > secs) return i
    }
    return -1
  }

  readonly property int firstIndex: {
    var best = -1
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].minute === null) continue
      if (best < 0 || rows[i].minute < rows[best].minute) best = i
    }
    return best
  }

  readonly property int lastIndex: {
    var best = -1
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].minute === null) continue
      if (best < 0 || rows[i].minute > rows[best].minute) best = i
    }
    return best
  }

  readonly property int targetIndex: nextIndex >= 0 ? nextIndex : firstIndex
  readonly property var target: targetIndex >= 0 ? rows[targetIndex] : null

  // Seconds until the target (wraps to tomorrow).
  readonly property real remainingSeconds: {
    if (!target) return -1
    var diff = target.minute * 60 - nowSeconds
    return diff > 0 ? diff : diff + 86400
  }

  // Seconds elapsed since the previous event (yesterday's last when before the first).
  readonly property real spanSeconds: {
    if (!target) return 0
    var prevMin = null
    if (nextIndex >= 0 && nextIndex !== firstIndex) {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].minute !== null && rows[i].minute * 60 <= nowSeconds
            && (prevMin === null || rows[i].minute > prevMin)) prevMin = rows[i].minute
      }
    } else if (lastIndex >= 0) {
      prevMin = rows[lastIndex].minute - 1440
    }
    if (prevMin === null) return 0
    var span = target.minute * 60 - prevMin * 60
    if (span <= 0) span += 86400
    return span
  }

  readonly property real progress: {
    if (!target || spanSeconds <= 0) return 0
    return Math.max(0, Math.min(1, 1 - remainingSeconds / spanSeconds))
  }

  function countdownText(secs) {
    if (secs < 0) return ""
    var total = Math.floor(secs / 60)
    var h = Math.floor(total / 60)
    var m = total % 60
    if (h <= 0 && m <= 0) return "in less than a minute"
    if (h <= 0) return "in " + m + "m"
    return "in " + h + "h " + m + "m"
  }

  readonly property string metaText: {
    var parts = []
    var d = scheduleData && scheduleData.date
    if (scheduleData && scheduleData.city) parts.push(scheduleData.city)
    if (scheduleData && scheduleData.weekday) parts.push(scheduleData.weekday)
    if (d && d.iso) parts.push(d.iso)
    if (scheduleData && scheduleData.hijri) {
      var h = scheduleData.hijri
      parts.push(typeof h === "string" ? h : (h.date || h.iso || ""))
    }
    return parts.filter(function(p) { return p !== "" }).join("  ·  ")
  }

  function open() {
    root.now = new Date()
    root.page = "main"
    root.cityPickerOpen = false
    root.controller.show()
  }

  // `omarchy-shell pursuit2703.salah-time.settings open` opens straight on
  // the settings page, for a keybinding.
  IpcHandler {
    target: "pursuit2703.salah-time.settings"
    function open(): void { root.openSettings() }
  }

  function openSettings() {
    root.now = new Date()
    root.page = "settings"
    root.cityPickerOpen = false
    root.controller.show()
  }

  function goBack() {
    if (root.cityPickerOpen) root.cityPickerOpen = false
    else root.page = "main"
    keyCatcher.forceActiveFocus()
  }

  function scopeLabel(scope) {
    if (scope === "all") return "All prayers"
    var s = String(scope || "")
    return s.charAt(0).toUpperCase() + s.slice(1)
  }

  // ---- Writes. Always truncate+write in place (never rename): BarWidget's
  // FileView watches the reminders inode.
  Component {
    id: writeProcComponent
    Process {
      running: false
      onExited: destroy()
    }
  }

  function writeFile(path, text, after) {
    var p = writeProcComponent.createObject(root, { command: [
      "bash", "-c", 'mkdir -p "$(dirname "$2")"; printf "%s\n" "$1" > "$2"', "_", text, path
    ] })
    if (!p) return
    if (after) p.exited.connect(after)
    p.running = true
  }

  function saveReminders(list, enabled, volume) {
    root.reminders = list
    root.soundEnabled = enabled
    root.soundVolume = volume
    root.writeFile(root.remindersFile, JSON.stringify({
      soundEnabled: enabled, soundVolume: volume, reminders: list
    }, null, 2))
  }

  readonly property var stepValues: [0, 5, 10, 15, 20, 25, 30, 45, 60]

  // Minutes of the first reminder for a scope, 0 when none. `list` is passed
  // so bindings re-evaluate when root.reminders changes.
  function minutesFor(scope, list) {
    var l = list || []
    for (var i = 0; i < l.length; i++)
      if (l[i].scope === scope) return Number(l[i].offsetMinutes) || 0
    return 0
  }

  function stepMinutes(cur, dir) {
    var v = root.stepValues
    if (dir > 0) {
      for (var i = 0; i < v.length; i++) if (v[i] > cur) return v[i]
      return cur
    }
    for (var j = v.length - 1; j >= 0; j--) if (v[j] < cur) return v[j]
    return 0
  }

  // At most one entry per scope is managed: the first match is updated or
  // removed; any further entries for the same scope are left untouched.
  function setScopeMinutes(scope, minutes) {
    var list = (root.reminders || []).slice()
    var idx = -1
    for (var i = 0; i < list.length; i++) if (list[i].scope === scope) { idx = i; break }
    if (minutes <= 0) {
      if (idx < 0) return
      list.splice(idx, 1)
    } else if (idx >= 0) {
      var e = Object.assign({}, list[idx])
      e.offsetMinutes = minutes
      list[idx] = e
    } else {
      list.push({ id: "r" + Date.now(), scope: scope, offsetMinutes: minutes })
    }
    root.saveReminders(list, root.soundEnabled, root.soundVolume)
  }

  function chooseCity(city) {
    root.currentCity = city
    root.cityPickerOpen = false
    root.writeFile(root.configFile, JSON.stringify({ city: city }, null, 2), function() {
      root.refreshRequested()
    })
    keyCatcher.forceActiveFocus()
  }

  // Same preparation as scripts/pick_city.sh: make sure the venv and the
  // cached region list exist, then print one city per line.
  Process {
    id: citiesProc
    command: ["bash", "-c",
      'DIR="$1"; source "$DIR/scripts/env.sh"; F="$HOME/.cache/omarchy-salah-time/regions.json"; ' +
      'mkdir -p "$(dirname "$F")"; ' +
      'if [ ! -f "$F" ]; then ' +
      '  if [ ! -x "$VENV_PY" ] || ! "$VENV_PY" -c "import bs4, playwright" >/dev/null 2>&1; then "$DIR/scripts/bootstrap.sh" >/dev/null 2>&1; fi; ' +
      '  "$VENV_PY" "$DIR/scripts/refresh_regions.py" >/dev/null 2>&1; ' +
      'fi; ' +
      'jq -r ".cities[]" "$F"',
      "_", root.pluginDir]
    stdout: StdioCollector {
      onStreamFinished: {
        root.cityList = text.split("\n").filter(function(c) { return c !== "" })
        root.citiesLoading = false
      }
    }
    onExited: root.citiesLoading = false
  }

  function ensureCities() {
    if (root.cityList.length > 0 || citiesProc.running) return
    root.citiesLoading = true
    citiesProc.running = true
  }

  onPageChanged: if (page === "settings") ensureCities()

  FileView {
    id: configView
    path: root.configFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.currentCity = JSON.parse(text()).city || "" } catch (e) { }
    }
    onFileChanged: reload()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: root.now = new Date()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.page === "settings" ? Style.space(340) : Style.space(300))
    contentHeight: panel.fittedContentHeight(
      root.page === "settings" ? settingsColumn.implicitHeight : column.implicitHeight,
      Style.space(780))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: citySearch.activeFocus
      onCloseRequested: {
        if (root.page === "settings") root.goBack()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshRequested()
        else if (t === "s" || t === "S") root.page = "settings"
      }

      Column {
        id: column
        visible: root.page === "main"
        width: parent.width
        spacing: Style.space(10)

        // ---- Hero
        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: root.target ? "NEXT PRAYER" : "SALAH TIME"
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.target ? root.target.label : "No data"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            elide: Text.ElideRight
          }

          Row {
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: root.target ? root.target.text : ""
              color: Commons.Color.accent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: root.countdownText(root.remainingSeconds)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
            }
          }

          Text {
            visible: root.metaText !== ""
            textFormat: Text.PlainText
            width: parent.width
            topPadding: Style.space(2)
            text: root.metaText
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        // ---- Progress
        Rectangle {
          width: parent.width
          height: Math.max(2, Style.space(3))
          radius: height / 2
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

          Rectangle {
            width: parent.width * root.progress
            height: parent.height
            radius: parent.radius
            color: Commons.Color.accent
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        // ---- Times
        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: root.rows

            Rectangle {
              id: rowItem
              required property var modelData
              required property int index
              readonly property bool isNext: root.targetIndex === index
              readonly property bool isPast: root.nextIndex < 0
                ? true
                : (modelData.minute !== null && modelData.minute * 60 <= root.nowSeconds)

              width: parent.width
              height: Style.space(32)
              radius: Style.cornerRadius
              color: isNext ? root.selectedFill : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: rowItem.modelData.label
                color: root.contentForeground
                opacity: rowItem.isNext ? 1 : (rowItem.isPast ? 0.4 : (rowItem.modelData.prayer ? 0.9 : 0.55))
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: rowItem.isNext
                font.italic: !rowItem.modelData.prayer
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: rowItem.modelData.text
                color: rowItem.isNext ? Commons.Color.accent : root.contentForeground
                opacity: rowItem.isNext ? 1 : (rowItem.isPast ? 0.4 : (rowItem.modelData.prayer ? 0.9 : 0.55))
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: rowItem.isNext
              }
            }
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        // ---- Footer
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Refresh"
            iconText: "󰑐"
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.refreshRequested()
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Settings"
            iconText: "󰒓"
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.page = "settings"
          }
        }
      }

      // ================= Settings page =================
      Flickable {
        id: settingsFlick
        visible: root.page === "settings"
        width: parent.width
        height: parent.height
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: settingsColumn
          width: settingsFlick.width
          spacing: Style.space(6)

          // ---- Header: icon-only back button + title
          Row {
            width: parent.width
            height: Style.space(32)
            spacing: Style.space(6)

            Rectangle {
              id: backButton
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.cornerRadius
              color: backMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent) : "transparent"

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰁍"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
              }

              MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goBack()
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Settings"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          // ---- City
          PanelSectionHeader {
            leftPadding: Style.space(10)
            topPadding: Style.space(6)
            text: "Location"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Rectangle {
            width: parent.width
            height: Style.space(36)
            radius: Style.cornerRadius
            color: cityMouse.containsMouse || root.cityPickerOpen
              ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
              : Style.normalFillFor(root.contentForeground, Commons.Color.accent)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "City"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (root.currentCity !== "" ? root.currentCity : "Choose") + "  ›"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: cityMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.cityPickerOpen = !root.cityPickerOpen
                if (root.cityPickerOpen) {
                  root.ensureCities()
                  citySearch.text = ""
                  citySearch.forceActiveFocus()
                } else {
                  keyCatcher.forceActiveFocus()
                }
              }
            }
          }

          Column {
            id: cityPicker
            visible: root.cityPickerOpen
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: citySearch
              width: parent.width
              placeholderText: "Search cities..."
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              horizontalPadding: Style.space(10)

              background: Rectangle {
                radius: Style.cornerRadius
                color: citySearch.activeFocus || citySearch.hovered
                  ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                  : Style.normalFillFor(root.contentForeground, Commons.Color.accent)
              }

              readonly property var filtered: {
                var q = text.toLowerCase()
                if (!q) return root.cityList
                return root.cityList.filter(function(c) { return c.toLowerCase().indexOf(q) !== -1 })
              }
              onTextChanged: cityListView.currentIndex = filtered.length > 0 ? 0 : -1

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cityPickerOpen = false
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  if (cityListView.currentIndex < filtered.length - 1) cityListView.currentIndex++
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  if (cityListView.currentIndex > 0) cityListView.currentIndex--
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (cityListView.currentIndex >= 0 && cityListView.currentIndex < filtered.length)
                    root.chooseCity(filtered[cityListView.currentIndex])
                  event.accepted = true
                }
              }
            }

            Item {
              width: parent.width
              height: Style.space(190)

              Text {
                anchors.centerIn: parent
                visible: cityListView.count === 0
                textFormat: Text.PlainText
                text: root.citiesLoading ? "Loading cities..." : "No matches"
                color: Qt.darker(root.contentForeground, 1.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              ListView {
                id: cityListView
                anchors.fill: parent
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds
                model: citySearch.filtered
                currentIndex: 0
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                  id: cityRow
                  required property string modelData
                  required property int index
                  readonly property bool isCurrent: modelData === root.currentCity
                  width: cityListView.width
                  height: Style.space(30)
                  radius: Style.cornerRadius
                  color: index === cityListView.currentIndex
                    ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                    : (isCurrent ? root.selectedFill : "transparent")

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: cityRow.modelData
                    elide: Text.ElideRight
                    color: cityRow.isCurrent ? Commons.Color.accent : root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: cityRow.isCurrent
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: cityListView.currentIndex = cityRow.index
                    onClicked: root.chooseCity(cityRow.modelData)
                  }
                }
              }
            }
          }

          // ---- Reminders
          PanelSectionHeader {
            leftPadding: Style.space(10)
            topPadding: Style.space(10)
            text: "Remind me before"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.scopeOptions

              Rectangle {
                id: remRow
                required property var modelData
                readonly property int minutes: root.minutesFor(modelData.value, root.reminders)
                width: parent.width
                height: Style.space(36)
                radius: Style.cornerRadius
                color: remHover.hovered
                  ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                  : Style.normalFillFor(root.contentForeground, Commons.Color.accent)

                HoverHandler { id: remHover }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.scopeLabel(remRow.modelData.value)
                  color: root.contentForeground
                  opacity: remRow.minutes > 0 ? 1 : 0.55
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

                  Rectangle {
                    width: Style.space(28)
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: minusMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent) : "transparent"
                    opacity: remRow.minutes > 0 ? 1 : 0.35

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "󰍴"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }

                    MouseArea {
                      id: minusMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setScopeMinutes(remRow.modelData.value, root.stepMinutes(remRow.minutes, -1))
                    }
                  }

                  Text {
                    width: Style.space(56)
                    height: Style.space(28)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    text: remRow.minutes > 0 ? remRow.minutes + " min" : "Off"
                    color: root.contentForeground
                    opacity: remRow.minutes > 0 ? 1 : 0.45
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  Rectangle {
                    width: Style.space(28)
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: plusMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent) : "transparent"
                    opacity: remRow.minutes < 60 ? 1 : 0.35

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "󰐕"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }

                    MouseArea {
                      id: plusMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setScopeMinutes(remRow.modelData.value, root.stepMinutes(remRow.minutes, 1))
                    }
                  }
                }
              }
            }
          }

          // ---- Sound: toggle row with the volume slider attached below
          PanelSectionHeader {
            leftPadding: Style.space(10)
            topPadding: Style.space(10)
            text: "Sound"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Rectangle {
            width: parent.width
            height: soundColumn.implicitHeight
            radius: Style.cornerRadius
            color: soundHover.hovered
              ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
              : Style.normalFillFor(root.contentForeground, Commons.Color.accent)

            HoverHandler { id: soundHover }

            Column {
              id: soundColumn
              width: parent.width

              Item {
                width: parent.width
                height: Style.space(36)

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Reminder sound"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                ToggleSwitch {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.soundEnabled
                  interactive: false
                  foreground: root.contentForeground
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.saveReminders(root.reminders || [], !root.soundEnabled, root.soundVolume)
                }
              }

              Item {
                visible: root.soundEnabled
                width: parent.width
                height: visible ? Style.space(34) : 0

                PanelSlider {
                  id: volumeSlider
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: volumeLabel.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  bar: root.bar
                  minimum: 0
                  maximum: 100
                  step: 5
                  integer: true
                  value: root.soundVolume
                  onReleased: function(v) {
                    root.saveReminders(root.reminders || [], root.soundEnabled, Math.max(0, Math.min(100, Math.round(v / 5) * 5)))
                  }
                }

                Text {
                  id: volumeLabel
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(36)
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: Math.round(volumeSlider.liveValue) + "%"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }
    }
  }
}
