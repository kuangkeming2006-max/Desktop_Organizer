import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Window {
    id: tagWindow
    property string tagId: ""
    property string tagTitle: "新建标签"
    property int tagWidth: 250
    property int tagHeight: Math.round(250 * 1.618)   // 黄金比例 ≈ 405
    property color tagColor: "#0b57d0"
    property string savePath: "D:/"
    property string allowedExts: ""

    width: tagWidth
    height: tagHeight
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint
    color: "transparent"

    ListModel { id: fileModel }

    // ===== Apple 黄金比例设计常数 =====
    readonly property int outerRadius: 28
    readonly property int cardPadding: 6
    readonly property int capsuleRadius: outerRadius - cardPadding   // 同心圆角 22
    readonly property int capsuleHeight: 66

    // --- 主卡片（边距 1px 防抗锯齿切边）---
    Item {
        anchors.fill: parent
        anchors.margins: 1

        // ---- 卡片本体 + Apple 多层阴影 ----
        Rectangle {
            id: cardBody
            anchors.fill: parent
            radius: outerRadius
            color: "#F5F5F7"

            // 内白边（Apple 招牌 inset border）
            Rectangle {
                anchors.fill: parent
                radius: outerRadius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.8)
                border.width: 1
            }

            // Apple 风格阴影
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.12)
                shadowBlur: 0.6
                shadowVerticalOffset: 14
            }

            // ===== 布局 =====
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: cardPadding
                spacing: 0

                // --- 顶部深灰胶囊（内切圆角）---
                Rectangle {
                    id: headerCapsule
                    Layout.fillWidth: true
                    Layout.preferredHeight: capsuleHeight
                    radius: capsuleRadius
                    color: "#1D1D1F"

                    // 拖拽區（放在最底層，不遮擋按鈕）
                    MouseArea {
                        anchors.fill: parent
                        onPressed: tagWindow.startSystemMove()
                    }

                    // 极淡边框增加立体感
                    Rectangle {
                        anchors.fill: parent
                        radius: capsuleRadius
                        color: "transparent"
                        border.color: Qt.rgba(0, 0, 0, 0.12)
                        border.width: 1
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 8

                        // 标签色小圆点（取代整条彩色标题列）
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: tagColor
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: tagWindow.tagTitle
                            color: "#F5F5F7"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item {
                            id: menuBtn
                            Layout.preferredWidth: 34; Layout.preferredHeight: 34
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                id: menuBtnBg
                                anchors.fill: parent; radius: 17
                                color: menuBtnArea.containsMouse ? Qt.rgba(1,1,1,0.18) : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "\u22EF"
                                font.pixelSize: 20
                                color: "#F5F5F7"
                            }

                            MouseArea {
                                id: menuBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: false
                                onClicked: tagMenu.open()
                            }

                            Popup {
                                id: tagMenu
                                y: 40
                                x: parent.width - 150
                                width: 150
                                padding: 4
                                background: Rectangle {
                                    radius: 10
                                    color: "#1D1D1F"
                                    border.color: Qt.rgba(1,1,1,0.12)
                                    border.width: 1
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: Qt.rgba(0,0,0,0.25)
                                        shadowBlur: 0.5
                                        shadowVerticalOffset: 8
                                    }
                                }
                                contentItem: Column {
                                    spacing: 2
                                    Repeater {
                                        model: [
                                            { text: "打开所在文件夹", action: function() { Qt.openUrlExternally("file:///" + tagWindow.savePath); tagMenu.close(); } },
                                            { text: "关闭并复原文件", action: function() { appBackend.removeTagAndRestore(tagWindow.tagId, tagWindow.savePath); tagWindow.destroy(); } }
                                        ]
                                        delegate: Rectangle {
                                            width: parent.width
                                            height: 36
                                            radius: 8
                                            color: itemMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            Text {
                                                anchors.left: parent.left; anchors.leftMargin: 14
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.text
                                                color: "#F5F5F7"
                                                font.pixelSize: 14
                                            }

                                            MouseArea {
                                                id: itemMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: modelData.action()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- 内容区：大面积留白 + 档案网格 ---
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 18
                    Layout.bottomMargin: 8
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10

                    GridView {
                        id: fileGrid
                        anchors.fill: parent
                        cellWidth: width / 3
                        cellHeight: 90
                        model: fileModel
                        clip: true

                        delegate: Item {
                            width: fileGrid.cellWidth; height: 90
                            Column {
                                anchors.centerIn: parent; spacing: 6
                                Rectangle {
                                    width: 44; height: 44; radius: 10
                                    color: Qt.rgba(tagColor.r, tagColor.g, tagColor.b, 0.1)
                                    Text {
                                        text: "\uD83D\uDCC4"
                                        anchors.centerIn: parent
                                        font.pixelSize: 22
                                    }
                                }
                                Text {
                                    text: model.fileName
                                    font.pixelSize: 12
                                    color: "#1D1D1F"
                                    width: parent.width - 6
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    font.weight: Font.Medium
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onDoubleClicked: Qt.openUrlExternally("file:///" + tagWindow.savePath + "/" + model.fileName)
                            }
                        }

                        DropArea {
                            anchors.fill: parent
                            onDropped: (drop) => {
                                if (drop.hasUrls) {
                                    for (var i = 0; i < drop.urls.length; i++) {
                                        var urlStr = drop.urls[i].toString();
                                        if (appBackend.moveFileToTag(urlStr, tagWindow.savePath)) {
                                            var fName = urlStr.substring(urlStr.lastIndexOf("/") + 1);
                                            fileModel.append({ "fileName": fName });
                                        }
                                    }
                                    drop.accept();
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- 右下角拉伸手柄 ---
        Item {
            id: resizeHandle
            width: 20; height: 20
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 4
            anchors.bottomMargin: 4
            z: 10

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.12);
                    ctx.lineWidth = 1.5;
                    ctx.moveTo(20, 8); ctx.lineTo(8, 20);
                    ctx.moveTo(20, 14); ctx.lineTo(14, 20);
                    ctx.stroke();
                }
            }

            MouseArea {
                anchors.fill: parent
                property point lastPos
                onPressed: (mouse) => lastPos = Qt.point(mouse.x, mouse.y)
                onPositionChanged: (mouse) => {
                    if (pressed) {
                        let dx = mouse.x - lastPos.x;
                        let dy = mouse.y - lastPos.y;
                        if (tagWindow.width + dx > 200) tagWindow.width += dx;
                        if (tagWindow.height + dy > 200) tagWindow.height += dy;
                    }
                }
            }
        }
    }
}