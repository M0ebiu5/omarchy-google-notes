import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "waltermonschein.google-notes"
  ipcTarget: "waltermonschein.google-notes"

  // Glyphs (Nerd Font / Material Design Symbols)
  readonly property string glyphBar: String.fromCodePoint(0xF0133)        // Checklist / notes icon
  readonly property string glyphUnchecked: String.fromCodePoint(0xF0131)  // Square unchecked
  readonly property string glyphChecked: String.fromCodePoint(0xF0132)    // Square checked
  readonly property string glyphAdd: String.fromCodePoint(0xF0415)        // Plus icon
  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)    // Refresh icon
  readonly property string glyphCog: String.fromCodePoint(0xF0493)        // Settings gear
  readonly property string glyphTrash: String.fromCodePoint(0xF01E0)      // Trash can
  readonly property string glyphDownload: String.fromCodePoint(0xF01DA)   // Download / install icon

  readonly property string helper: Qt.resolvedUrl("bin/notes-helper").toString().replace("file://", "")

  // Theme styling
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.6)
  readonly property color subtleBg: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.07)
  readonly property color cardBg: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
  readonly property color borderCol: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Plugin settings
  readonly property string prefListTitle: String(setting("targetListTitle", "My Notes"))
  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 120)))
  readonly property bool prefShowCompleted: Boolean(setting("showCompleted", false))
  readonly property string countMode: String(setting("countMode", "all"))

  // State
  property bool authenticated: false
  property bool depsInstalled: false
  property bool installingDeps: false
  property bool authPending: false
  property bool scanning: false
  property bool settingsOpen: false
  property string statusError: ""
  property bool showFinished: root.prefShowCompleted

  property var noteLists: []
  property string activeListId: ""
  property string activeListTitle: "My Notes"

  property var items: []
  property var optimisticallyChecked: ({})

  readonly property var openItems: (items || []).filter(function (t) {
    return !t.checked && !optimisticallyChecked[t.id]
  })

  readonly property var checkedItems: (items || []).filter(function (t) {
    return t.checked || Boolean(optimisticallyChecked[t.id])
  })

  readonly property int badgeCount: countMode === "none" ? 0 : openItems.length

  readonly property string summary: {
    if (!root.depsInstalled) return "Google Notes: Setup required"
    if (!root.authenticated) return "Google Notes: Sign in required"
    if (root.scanning && items.length === 0) return "Syncing Google Keep…"
    if (openItems.length === 0) return activeListTitle + ": All caught up!"
    var str = openItems.length + (openItems.length === 1 ? " item" : " items")
    return activeListTitle + " (" + str + ")"
  }

  // API Process triggers using stdin bounded IPC
  function checkStatus() {
    statusProc.inputPayload = JSON.stringify({ action: "status" })
    statusProc.running = true
  }

  function installDeps() {
    root.installingDeps = true
    root.statusError = ""
    installDepsProc.inputPayload = JSON.stringify({ action: "install-deps" })
    installDepsProc.running = true
  }

  function fetchNoteLists() {
    if (!root.authenticated) return
    listNoteListsProc.running = false
    listNoteListsProc.inputPayload = JSON.stringify({ action: "list-notelists" })
    listNoteListsProc.running = true
  }

  function fetchItems() {
    if (!root.authenticated || root.activeListId === "") return
    root.scanning = true
    listItemsProc.running = false
    listItemsProc.inputPayload = JSON.stringify({
      action: "list-items",
      list_id: root.activeListId
    })
    listItemsProc.running = true
  }

  function quickAddItem(text) {
    var clean = String(text || "").trim()
    if (clean === "" || !root.authenticated || root.activeListId === "") return
    root.statusError = ""
    var tempItem = { id: "temp_" + Date.now(), text: clean, checked: false }
    root.items = [tempItem].concat(root.items || [])
    createItemProc.running = false
    createItemProc.inputPayload = JSON.stringify({
      action: "create-item",
      list_id: root.activeListId,
      text: clean
    })
    createItemProc.running = true
  }

  function toggleItem(item) {
    if (!item || !item.id || !root.authenticated || root.activeListId === "") return
    var updated = Object.assign({}, root.optimisticallyChecked)
    var newChecked = !item.checked
    updated[item.id] = newChecked
    root.optimisticallyChecked = updated
    toggleItemProc.inputPayload = JSON.stringify({
      action: "toggle-item",
      list_id: root.activeListId,
      item_id: item.id,
      checked: newChecked
    })
    toggleItemProc.running = true
  }

  function deleteItem(item) {
    if (!item || !item.id || !root.authenticated || root.activeListId === "" || deleteItemProc.running) return
    root.items = (root.items || []).filter(function (t) { return t.id !== item.id })
    deleteItemProc.inputPayload = JSON.stringify({
      action: "delete-item",
      list_id: root.activeListId,
      item_id: item.id
    })
    deleteItemProc.running = true
  }

  function startAuthFlow(email, token) {
    root.authPending = true
    root.statusError = ""
    authProc.inputPayload = JSON.stringify({
      action: "auth",
      email: String(email || "").trim(),
      token: String(token || "").trim()
    })
    authProc.running = true
  }

  function logout() {
    logoutProc.inputPayload = JSON.stringify({ action: "logout" })
    logoutProc.running = true
  }

  function isAuthError(msg) {
    var m = String(msg || "").toLowerCase()
    return m.indexOf("not authenticated") !== -1 ||
           m.indexOf("authentication failed") !== -1 ||
           m.indexOf("sign-in failed") !== -1 ||
           m.indexOf("invalid_grant") !== -1
  }

  Component.onCompleted: {
    root.checkStatus()
  }

  onOpenedChanged: {
    if (opened) {
      checkStatus()
      if (root.authenticated) {
        root.fetchNoteLists()
      }
    }
  }

  // Periodic Refresh
  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.authenticated) {
        root.fetchNoteLists()
      } else {
        checkStatus()
      }
    }
  }

  // Process Handlers (All pass sensitive and private content over stdin)
  Process {
    id: statusProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(String(text || "{}"))
          root.depsInstalled = res.depsInstalled === true
          root.authenticated = res.authenticated === true
          if (res.email && emailInput && emailInput.text === "") {
            emailInput.text = res.email
          }
          if (root.authenticated && root.noteLists.length === 0) {
            root.fetchNoteLists()
          }
        } catch (e) {
          console.warn("notes-helper status parse error", e)
        }
      }
    }
  }

  Process {
    id: installDepsProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.installingDeps = false
        try {
          var res = JSON.parse(String(text || "{}"))
          if (res.installed) {
            root.checkStatus()
          } else {
            root.statusError = String(res.message || "Dependency installation failed").substring(0, 250)
          }
        } catch (e) {
          console.warn("install-deps parse error", e)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.installingDeps = false
        if (text && text.trim() !== "") {
          try {
            var err = JSON.parse(text)
            root.statusError = String(err.error || text).substring(0, 250)
          } catch (e) {
            root.statusError = String(text).substring(0, 250)
          }
        }
      }
    }
  }

  Process {
    id: listNoteListsProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var arr = JSON.parse(String(text || "[]"))
          if (Array.isArray(arr) && arr.length > 0) {
            root.noteLists = arr.slice(0, 50)
            var target = null
            for (var i = 0; i < root.noteLists.length; i++) {
              if (root.noteLists[i].id === root.activeListId) {
                target = root.noteLists[i]
                break
              }
            }
            if (!target && root.prefListTitle) {
              for (var j = 0; j < root.noteLists.length; j++) {
                if (root.noteLists[j].title.toLowerCase() === root.prefListTitle.toLowerCase() || root.noteLists[j].id === root.prefListTitle) {
                  target = root.noteLists[j]
                  break
                }
              }
            }
            if (!target) target = root.noteLists[0]
            root.activeListId = target.id
            root.activeListTitle = target.title
            root.statusError = ""
            root.fetchItems()
          } else if (Array.isArray(arr) && arr.length === 0) {
            root.noteLists = []
            root.activeListId = ""
            root.items = []
          }
        } catch (e) {
          console.warn("list-notelists parse error", e)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() !== "") {
          console.warn("listNoteListsProc error:", text)
          try {
            var err = JSON.parse(text)
            var errMsg = String(err.error || text)
            if (root.isAuthError(errMsg)) root.authenticated = false
            root.statusError = errMsg.substring(0, 250)
          } catch (e) {
            if (root.isAuthError(text)) root.authenticated = false
            root.statusError = String(text).substring(0, 250)
          }
        }
      }
    }
  }

  Process {
    id: listItemsProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.scanning = false
        try {
          var res = JSON.parse(String(text || "{}"))
          if (res && Array.isArray(res.items)) {
            root.items = res.items.slice(0, 300)
            root.optimisticallyChecked = ({})
          }
        } catch (e) {
          console.warn("list-items parse error", e)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.scanning = false
        if (text && text.trim() !== "") {
          console.warn("listItemsProc error:", text)
          try {
            var err = JSON.parse(text)
            var errMsg = String(err.error || text)
            if (root.isAuthError(errMsg)) root.authenticated = false
            if (errMsg.indexOf("not found") !== -1) {
              root.activeListId = ""
              root.fetchNoteLists()
              return
            }
            root.statusError = errMsg.substring(0, 250)
          } catch (e) {
            if (root.isAuthError(text)) root.authenticated = false
            root.statusError = String(text).substring(0, 250)
          }
        }
      }
    }
  }

  Process {
    id: createItemProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    onExited: root.fetchItems()
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() !== "") {
          console.warn("createItemProc error:", text)
          try {
            var err = JSON.parse(text)
            root.statusError = String(err.error || text).substring(0, 250)
          } catch (e) {
            root.statusError = String(text).substring(0, 250)
          }
        }
      }
    }
  }

  Process {
    id: toggleItemProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    onExited: root.fetchItems()
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() !== "") {
          console.warn("toggleItemProc error:", text)
        }
      }
    }
  }

  Process {
    id: deleteItemProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    onExited: root.fetchItems()
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() !== "") {
          console.warn("deleteItemProc error:", text)
        }
      }
    }
  }

  Process {
    id: authProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.authPending = false
        root.checkStatus()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() !== "") {
          root.authPending = false
          try {
            var err = JSON.parse(text)
            root.statusError = String(err.error || text).substring(0, 250)
          } catch(e) {
            root.statusError = String(text).substring(0, 250)
          }
        }
      }
    }
  }

  Process {
    id: logoutProc
    command: [root.helper]
    stdinEnabled: true
    property string inputPayload: ""
    onStarted: {
      if (inputPayload) write(inputPayload + "\n")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.authenticated = false
        root.items = []
        root.noteLists = []
        root.activeListId = ""
        root.checkStatus()
      }
    }
  }

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  // Top Bar Icon
  WidgetButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: root.badgeCount > 0 ? (root.glyphBar + " " + root.badgeCount) : root.glyphBar
    dimmed: !root.authenticated || root.badgeCount === 0
    tooltipText: root.summary
    onPressed: function (btn) {
      if (btn === Qt.RightButton) {
        root.fetchItems()
      } else {
        root.toggle()
      }
    }
  }

  // Dropdown Popup Panel
  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: addField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(mainCol.implicitHeight + Style.space(24), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: addField.activeFocus || emailInput.activeFocus || tokenInput.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function (dir) { root.switchPanel(dir) }
      onTextKey: function (k) {
        if (k === "a" || k === "A") addField.forceActiveFocus()
        else if (k === "r" || k === "R") root.fetchItems()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainCol
          width: flick.width
          spacing: Style.space(12)

          // Header
          Item {
            width: parent.width
            implicitHeight: Math.max(headerLabels.implicitHeight, headerActions.implicitHeight)

            Row {
              id: headerLabels
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                text: root.glyphBar
                textFormat: Text.PlainText
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: root.activeListTitle
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }

                Text {
                  text: root.summary
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                iconText: root.glyphRefresh
                tooltipText: "Sync Google Notes"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  root.statusError = ""
                  if (root.authenticated) root.fetchNoteLists()
                  else root.checkStatus()
                }
              }

              PanelActionButton {
                iconText: root.glyphCog
                tooltipText: root.settingsOpen ? "Close Settings" : "Account Settings"
                foreground: root.settingsOpen ? root.accent : root.foreground
                fontFamily: root.fontFamily
                onClicked: root.settingsOpen = !root.settingsOpen
              }
            }
          }

          // Settings / Auth Section
          Rectangle {
            id: settingsBox
            visible: root.settingsOpen || !root.depsInstalled || !root.authenticated
            width: parent.width
            implicitHeight: settingsCol.implicitHeight + Style.space(20)
            color: root.subtleBg
            radius: 8
            border.color: root.borderCol
            border.width: 1

            Column {
              id: settingsCol
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(10)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  text: root.authenticated ? "Google Account Connected" : "Connect Google Notes"
                  textFormat: Text.PlainText
                  color: root.authenticated ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Button {
                  visible: root.authenticated
                  text: "Sign Out"
                  onClicked: root.logout()
                }
              }

              // Step 1: install dependencies
              Column {
                visible: !root.depsInstalled
                width: parent.width
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Google Keep has no official personal-account API. This plugin talks to it the unofficial way (same as Home Assistant's google_keep_sync), which needs two small Python packages (gkeepapi, gpsoauth) installed in a private, plugin-local virtual environment. See README.md before continuing."
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Button {
                  width: parent.width
                  text: root.installingDeps ? "Installing…" : "Install Dependencies"
                  enabled: !root.installingDeps
                  onClicked: root.installDeps()
                }
              }

              // Step 2: sign in
              Text {
                visible: root.depsInstalled && !root.authenticated
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Paste your Google account email and a Keep master/OAuth token below. See README.md → \"Getting a Token\" for how to generate one. Never paste your actual Google password here."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                visible: root.depsInstalled && !root.authenticated
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: emailInput
                  width: parent.width
                  placeholderText: "Google Account Email"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  background: Rectangle {
                    color: root.cardBg
                    border.color: root.borderCol
                    radius: 4
                  }
                }

                TextField {
                  id: tokenInput
                  width: parent.width
                  placeholderText: "Master or OAuth token"
                  echoMode: TextInput.Password
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  background: Rectangle {
                    color: root.cardBg
                    border.color: root.borderCol
                    radius: 4
                  }
                }

                Button {
                  width: parent.width
                  text: root.authPending ? "Signing In…" : "Sign In"
                  enabled: !root.authPending
                  onClicked: root.startAuthFlow(emailInput.text, tokenInput.text)
                }
              }

              Text {
                visible: root.statusError !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.statusError
                textFormat: Text.PlainText
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // Note (list) selector if authenticated
              Column {
                visible: root.authenticated && root.noteLists.length > 1
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: "Switch Note:"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: root.noteLists
                    delegate: Rectangle {
                      implicitWidth: listLabel.implicitWidth + Style.space(16)
                      implicitHeight: Style.space(26)
                      color: root.activeListId === modelData.id ? root.accent : root.cardBg
                      radius: 13
                      border.color: root.borderCol

                      Text {
                        id: listLabel
                        anchors.centerIn: parent
                        text: String(modelData.title || "")
                        textFormat: Text.PlainText
                        color: root.activeListId === modelData.id ? "#ffffff" : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.activeListId = modelData.id
                          root.activeListTitle = modelData.title
                          root.fetchItems()
                        }
                      }
                    }
                  }
                }
              }

              Text {
                visible: root.authenticated && root.noteLists.length === 0 && !root.scanning
                width: parent.width
                wrapMode: Text.WordWrap
                text: "No checklist notes found. In Google Keep, create a note, enable \"Show checkboxes\", then hit Sync."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Toggle {
                visible: root.authenticated
                width: parent.width
                label: "Show finished items"
                description: root.checkedItems.length + " checked off"
                checked: root.showFinished
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.showFinished = !root.showFinished
              }
            }
          }

          // Quick Add Box
          Rectangle {
            visible: root.authenticated && root.activeListId !== ""
            width: parent.width
            implicitHeight: Style.space(38)
            color: root.cardBg
            radius: 6
            border.color: addField.activeFocus ? root.accent : root.borderCol
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              MouseArea {
                implicitWidth: Style.space(24)
                implicitHeight: Style.space(24)
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.quickAddItem(addField.text)
                  addField.text = ""
                }

                Text {
                  anchors.centerIn: parent
                  text: root.glyphAdd
                  textFormat: Text.PlainText
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              TextField {
                id: addField
                Layout.fillWidth: true
                placeholderText: "Add an item… (Enter to save)"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                background: null
                selectByMouse: true
                onAccepted: {
                  root.quickAddItem(text)
                  text = ""
                }
                Keys.onReturnPressed: function(event) {
                  root.quickAddItem(text)
                  text = ""
                  event.accepted = true
                }
                Keys.onEnterPressed: function(event) {
                  root.quickAddItem(text)
                  text = ""
                  event.accepted = true
                }
              }
            }
          }

          // Items List
          Column {
            visible: root.authenticated && root.activeListId !== ""
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.openItems
              delegate: Rectangle {
                id: itemCard
                width: parent.width
                implicitHeight: cardContent.implicitHeight + Style.space(14)
                color: root.cardBg
                radius: 6
                border.color: root.borderCol
                border.width: 1

                RowLayout {
                  id: cardContent
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(10)

                  // Checkbox
                  MouseArea {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Style.space(24)
                    implicitHeight: Style.space(24)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleItem(modelData)

                    Text {
                      anchors.centerIn: parent
                      text: Boolean(modelData && modelData.checked) || Boolean(root.optimisticallyChecked && root.optimisticallyChecked[modelData.id]) ? root.glyphChecked : root.glyphUnchecked
                      textFormat: Text.PlainText
                      color: Boolean(modelData && modelData.checked) || Boolean(root.optimisticallyChecked && root.optimisticallyChecked[modelData.id]) ? root.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  // Text
                  Text {
                    Layout.fillWidth: true
                    text: String((modelData && modelData.text) || "")
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    font.strikeout: Boolean(modelData && modelData.checked) || Boolean(root.optimisticallyChecked && root.optimisticallyChecked[modelData.id])
                  }

                  // Delete action
                  MouseArea {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Style.space(20)
                    implicitHeight: Style.space(20)
                    cursorShape: Qt.PointingHandCursor
                    opacity: 0.6
                    onClicked: root.deleteItem(modelData)

                    Text {
                      anchors.centerIn: parent
                      text: root.glyphTrash
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            // Checked items (collapsed under open items) when enabled
            Repeater {
              model: root.showFinished ? root.checkedItems : []
              delegate: Rectangle {
                width: parent.width
                implicitHeight: checkedContent.implicitHeight + Style.space(10)
                color: "transparent"
                radius: 6

                RowLayout {
                  id: checkedContent
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(10)

                  MouseArea {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Style.space(24)
                    implicitHeight: Style.space(24)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleItem(modelData)

                    Text {
                      anchors.centerIn: parent
                      text: root.glyphChecked
                      textFormat: Text.PlainText
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: String((modelData && modelData.text) || "")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.strikeout: true
                    wrapMode: Text.WordWrap
                  }

                  MouseArea {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Style.space(20)
                    implicitHeight: Style.space(20)
                    cursorShape: Qt.PointingHandCursor
                    opacity: 0.6
                    onClicked: root.deleteItem(modelData)

                    Text {
                      anchors.centerIn: parent
                      text: root.glyphTrash
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            // Empty state
            Item {
              visible: root.openItems.length === 0 && !root.scanning && root.activeListId !== ""
              width: parent.width
              implicitHeight: Style.space(60)

              Column {
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "🎉 All items checked off!"
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Type above to add a new item."
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}
