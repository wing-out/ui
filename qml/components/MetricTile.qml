import QtQuick
import WingOut

GlassCard {
    id: root

    property string title: ""
    property string value: "--"
    property string unit: ""
    property color valueColor: Theme.textPrimary
    property real warningThreshold: -1
    property real criticalThreshold: -1
    property real numericValue: 0

    Accessible.name: root.objectName || root.title
    Accessible.description: root.value + (root.unit ? " " + root.unit : "")
    Accessible.role: Accessible.Indicator

    implicitHeight: Theme.metricTileHeight
    hoverEnabled: true

    function computeColor() {
        if (criticalThreshold >= 0 && numericValue >= criticalThreshold) return Theme.error
        if (warningThreshold >= 0 && numericValue >= warningThreshold) return Theme.warning
        return Theme.textPrimary
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingTiny

        Text {
            text: root.title
            font.pixelSize: Theme.fontSmall
            font.weight: Font.Medium
            color: Theme.textSecondary
            elide: Text.ElideRight
            width: parent.width
        }

        Row {
            spacing: Theme.spacingTiny
            anchors.left: parent.left

            Text {
                text: root.value
                font.pixelSize: Theme.fontHuge
                font.weight: Font.Bold
                color: root.computeColor()

                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }

            Text {
                text: root.unit
                font.pixelSize: Theme.fontSmall
                color: Theme.textTertiary
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                visible: root.unit !== ""
            }
        }
    }
}
