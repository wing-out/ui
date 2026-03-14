import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "avdPage"
    Accessible.role: Accessible.Pane

    // Route data from server
    property var allRoutes: []
    // Set of selected route paths (routes we care about)
    property var selectedPaths: ({})
    // Expanded forwarding key: "routePath:fwdIndex" or "" if none expanded
    property string expandedKey: ""

    // Filter state for the expanded forwarding
    property var privacyBlurState: ({})
    property var deblemishState: ({})

    function loadRoutes() {
        controller.avdListRoutes(
            function(routes) { root.allRoutes = routes },
            function(err) { console.warn("avdListRoutes error:", err) }
        )
    }

    function loadPrivacyBlur(routePath, fwdIndex) {
        controller.avdGetPrivacyBlur(routePath, fwdIndex,
            function(state) { root.privacyBlurState = state },
            function(err) { console.warn("avdGetPrivacyBlur error:", err) }
        )
    }

    function loadDeblemish(routePath, fwdIndex) {
        controller.avdGetDeblemish(routePath, fwdIndex,
            function(state) { root.deblemishState = state },
            function(err) { console.warn("avdGetDeblemish error:", err) }
        )
    }

    function expandForwarding(routePath, fwdIndex, fwd) {
        var key = routePath + ":" + fwdIndex
        if (root.expandedKey === key) {
            root.expandedKey = ""
            return
        }
        root.expandedKey = key
        root.privacyBlurState = {}
        root.deblemishState = {}
        if (fwd.hasPrivacyBlur) loadPrivacyBlur(routePath, fwdIndex)
        if (fwd.hasDeblemish) loadDeblemish(routePath, fwdIndex)
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: loadRoutes()
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: Theme.spacingMedium

            // Section: Route Selection
            Text {
                text: "Select Routes"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Text {
                text: "Check the routes you want to manage."
                font.pixelSize: Theme.fontSmall
                color: Theme.textSecondary
                visible: root.allRoutes.length > 0
            }

            Text {
                text: "No routes available. Ensure AVD backend is connected."
                font.pixelSize: Theme.fontSmall
                color: Theme.textSecondary
                visible: root.allRoutes.length === 0
            }

            // Route checkboxes
            Repeater {
                model: root.allRoutes

                Components.GlassCard {
                    required property int index
                    required property var modelData

                    width: col.width
                    implicitHeight: routeCheckRow.implicitHeight + Theme.spacingMedium * 2

                    Row {
                        id: routeCheckRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingSmall
                        spacing: Theme.spacingSmall

                        CheckBox {
                            id: routeCheckBox
                            checked: root.selectedPaths[modelData.path] === true
                            anchors.verticalCenter: parent.verticalCenter
                            onCheckedChanged: {
                                var paths = root.selectedPaths
                                if (checked) {
                                    paths[modelData.path] = true
                                } else {
                                    delete paths[modelData.path]
                                }
                                root.selectedPaths = paths
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: modelData.path
                                font.pixelSize: Theme.fontMedium
                                font.weight: Font.Medium
                                color: Theme.textPrimary
                            }
                            Text {
                                text: (modelData.isServing ? "Serving" : "Idle") +
                                      " \u2022 " + modelData.forwardings.length + " forwarding(s)"
                                font.pixelSize: Theme.fontSmall
                                color: Theme.textSecondary
                            }
                        }
                    }
                }
            }

            // Section: Selected Routes & Controls
            Text {
                text: "Filter Controls"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingMedium
                visible: hasSelectedRoutes()
            }

            function hasSelectedRoutes() {
                return Object.keys(root.selectedPaths).length > 0
            }

            Repeater {
                model: root.allRoutes

                Column {
                    required property int index
                    required property var modelData

                    width: col.width
                    spacing: Theme.spacingSmall
                    visible: root.selectedPaths[modelData.path] === true

                    // Route header
                    Text {
                        text: modelData.path
                        font.pixelSize: Theme.fontMedium
                        font.weight: Font.Bold
                        color: Theme.accentPrimary
                        topPadding: Theme.spacingSmall
                    }

                    // Forwardings for this route
                    Repeater {
                        model: modelData.forwardings

                        Components.GlassCard {
                            required property int index
                            required property var modelData

                            property string routePath: parent.parent.modelData.path
                            property int fwdIndex: modelData.index
                            property string fwdKey: routePath + ":" + fwdIndex
                            property bool isExpanded: root.expandedKey === fwdKey

                            width: col.width
                            implicitHeight: fwdCol.implicitHeight + Theme.spacingMedium * 2

                            Column {
                                id: fwdCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingSmall
                                spacing: Theme.spacingSmall

                                // Forwarding header (clickable to expand)
                                AbstractButton {
                                    width: parent.width
                                    height: fwdHeaderRow.implicitHeight + Theme.spacingSmall

                                    contentItem: Row {
                                        id: fwdHeaderRow
                                        spacing: Theme.spacingSmall

                                        Text {
                                            text: isExpanded ? "\ue5cf" : "\ue5ce"
                                            font.family: Theme.iconFont
                                            font.pixelSize: Theme.fontLarge
                                            color: Theme.textSecondary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Forwarding #" + fwdIndex
                                            font.pixelSize: Theme.fontMedium
                                            font.weight: Font.Medium
                                            color: Theme.textPrimary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: {
                                                var caps = []
                                                if (modelData.hasPrivacyBlur) caps.push("Privacy Blur")
                                                if (modelData.hasDeblemish) caps.push("Deblemish")
                                                return caps.length > 0 ? "(" + caps.join(", ") + ")" : "(no filters)"
                                            }
                                            font.pixelSize: Theme.fontSmall
                                            color: Theme.textSecondary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    onClicked: expandForwarding(routePath, fwdIndex, modelData)
                                }

                                // Expanded controls
                                Column {
                                    width: parent.width
                                    spacing: Theme.spacingMedium
                                    visible: isExpanded
                                    leftPadding: Theme.spacingMedium

                                    // Privacy Blur controls
                                    Column {
                                        width: parent.width - Theme.spacingMedium
                                        spacing: Theme.spacingSmall
                                        visible: modelData.hasPrivacyBlur

                                        Text {
                                            text: "Privacy Blur"
                                            font.pixelSize: Theme.fontMedium
                                            font.weight: Font.Medium
                                            color: Theme.textPrimary
                                        }

                                        Row {
                                            spacing: Theme.spacingSmall

                                            Text {
                                                text: "Enabled"
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Switch {
                                                checked: root.privacyBlurState.enabled === true
                                                onToggled: {
                                                    controller.avdSetPrivacyBlur(routePath, fwdIndex,
                                                        {"enabled": checked},
                                                        function() { loadPrivacyBlur(routePath, fwdIndex) },
                                                        function(err) { console.warn("setPrivacyBlur error:", err) }
                                                    )
                                                }
                                            }
                                        }

                                        Row {
                                            spacing: Theme.spacingSmall

                                            Text {
                                                text: "Blur Radius"
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 120
                                            }
                                            Slider {
                                                id: blurRadiusSlider
                                                width: 200
                                                from: 1
                                                to: 100
                                                stepSize: 1
                                                value: root.privacyBlurState.blurRadius || 10
                                                onPressedChanged: {
                                                    if (!pressed) {
                                                        controller.avdSetPrivacyBlur(routePath, fwdIndex,
                                                            {"blurRadius": value},
                                                            function() { loadPrivacyBlur(routePath, fwdIndex) },
                                                            function(err) { console.warn("setPrivacyBlur error:", err) }
                                                        )
                                                    }
                                                }
                                            }
                                            Text {
                                                text: Math.round(blurRadiusSlider.value).toString()
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Row {
                                            spacing: Theme.spacingSmall

                                            Text {
                                                text: "Block Size"
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 120
                                            }
                                            Slider {
                                                id: pixelateSlider
                                                width: 200
                                                from: 0
                                                to: 64
                                                stepSize: 1
                                                value: root.privacyBlurState.pixelateBlockSize || 0
                                                onPressedChanged: {
                                                    if (!pressed) {
                                                        controller.avdSetPrivacyBlur(routePath, fwdIndex,
                                                            {"pixelateBlockSize": value},
                                                            function() { loadPrivacyBlur(routePath, fwdIndex) },
                                                            function(err) { console.warn("setPrivacyBlur error:", err) }
                                                        )
                                                    }
                                                }
                                            }
                                            Text {
                                                text: Math.round(pixelateSlider.value).toString()
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    // Deblemish controls
                                    Column {
                                        width: parent.width - Theme.spacingMedium
                                        spacing: Theme.spacingSmall
                                        visible: modelData.hasDeblemish

                                        Rectangle {
                                            width: parent.width
                                            height: 1
                                            color: Theme.glassBorderColor
                                            visible: modelData.hasPrivacyBlur
                                        }

                                        Text {
                                            text: "Deblemish (Skin Smoothing)"
                                            font.pixelSize: Theme.fontMedium
                                            font.weight: Font.Medium
                                            color: Theme.textPrimary
                                        }

                                        Row {
                                            spacing: Theme.spacingSmall

                                            Text {
                                                text: "Enabled"
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Switch {
                                                checked: root.deblemishState.enabled === true
                                                onToggled: {
                                                    controller.avdSetDeblemish(routePath, fwdIndex,
                                                        {"enabled": checked},
                                                        function() { loadDeblemish(routePath, fwdIndex) },
                                                        function(err) { console.warn("setDeblemish error:", err) }
                                                    )
                                                }
                                            }
                                        }

                                        Row {
                                            spacing: Theme.spacingSmall

                                            Text {
                                                text: "Sigma S"
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 120
                                            }
                                            Slider {
                                                id: sigmaSSlider
                                                width: 200
                                                from: 1
                                                to: 200
                                                stepSize: 1
                                                value: root.deblemishState.sigmaS || 10
                                                onPressedChanged: {
                                                    if (!pressed) {
                                                        controller.avdSetDeblemish(routePath, fwdIndex,
                                                            {"sigmaS": value},
                                                            function() { loadDeblemish(routePath, fwdIndex) },
                                                            function(err) { console.warn("setDeblemish error:", err) }
                                                        )
                                                    }
                                                }
                                            }
                                            Text {
                                                text: Math.round(sigmaSSlider.value).toString()
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Row {
                                            spacing: Theme.spacingSmall

                                            Text {
                                                text: "Sigma R"
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 120
                                            }
                                            Slider {
                                                id: sigmaRSlider
                                                width: 200
                                                from: 0.01
                                                to: 1.0
                                                stepSize: 0.01
                                                value: root.deblemishState.sigmaR || 0.1
                                                onPressedChanged: {
                                                    if (!pressed) {
                                                        controller.avdSetDeblemish(routePath, fwdIndex,
                                                            {"sigmaR": value},
                                                            function() { loadDeblemish(routePath, fwdIndex) },
                                                            function(err) { console.warn("setDeblemish error:", err) }
                                                        )
                                                    }
                                                }
                                            }
                                            Text {
                                                text: sigmaRSlider.value.toFixed(2)
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Row {
                                            spacing: Theme.spacingSmall

                                            Text {
                                                text: "Diameter"
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 120
                                            }
                                            Slider {
                                                id: diameterSlider
                                                width: 200
                                                from: -1
                                                to: 30
                                                stepSize: 1
                                                value: root.deblemishState.diameter || -1
                                                onPressedChanged: {
                                                    if (!pressed) {
                                                        controller.avdSetDeblemish(routePath, fwdIndex,
                                                            {"diameter": value},
                                                            function() { loadDeblemish(routePath, fwdIndex) },
                                                            function(err) { console.warn("setDeblemish error:", err) }
                                                        )
                                                    }
                                                }
                                            }
                                            Text {
                                                text: Math.round(diameterSlider.value).toString() + (diameterSlider.value < 0 ? " (auto)" : "")
                                                font.pixelSize: Theme.fontSmall
                                                color: Theme.textPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
