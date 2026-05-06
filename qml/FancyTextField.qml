import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property alias selectByMouse: input.selectByMouse
    property alias font: input.font
    property alias readOnly: input.readOnly
    // 常用 TextField 屬性代理
    property alias leftPadding: input.leftPadding
    property alias rightPadding: input.rightPadding
    property alias horizontalAlignment: input.horizontalAlignment
    property alias verticalAlignment: input.verticalAlignment
    property alias color: input.color

    signal accepted()
    signal editingFinished()

    // 可自訂顏色與圓角
    property color hoverColor: "#f5f5f5"
    property color normalBorder: Qt.rgba(0,0,0,0.12)
    property color focusBorder: "#0b57d0"
    property int radius: 8

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: input.focus ? root.focusBorder : root.normalBorder
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }

    HoverHandler {
        id: hoverHandler
        onHoveredChanged: hoverOverlay.opacity = (hoverHandler.hovered || input.focus) ? 1.0 : 0.0
    }

    Rectangle {
        id: hoverOverlay
        anchors.fill: parent
        radius: parent.radius
        color: root.hoverColor
        opacity: 0.0
        z: 1
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    TextField {
        id: input
        anchors.fill: parent
        anchors.margins: 8
        background: null
        z: 2
        onAccepted: root.accepted()
        onEditingFinished: root.editingFinished()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPressed: input.forceActiveFocus()
    }
}
