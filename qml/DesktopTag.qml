import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Window {
    id: tagWindow
    property string tagId: ""
    property string tagTitle: "新建标签"
    property int tagWidth: 220
    property int tagHeight: 280
    property color tagColor: "#0b57d0"
    property string savePath: "D:/"
    property string allowedExts: ""

    width: tagWidth
    height: tagHeight
    visible: true
    flags: Qt.Window | Qt.WindowStaysOnBottomHint
    color: "transparent"

    // 觸發 DWM 重新計算非客戶區
    Component.onCompleted: {
        if (appBackend.initNativeWindow) {
            appBackend.initNativeWindow(tagWindow);
        }
    }

    ListModel { id: fileModel }

    // --- 主容器 ---
    Item {
        id: mainContainer
        anchors.fill: parent
        // 这里的边距用于留出极其微小的空间防止抗锯齿切边，但不产生阴影
        anchors.margins: 1

        // --- 1. 背景模糊层 (边缘清晰的关键：不直接在边框层做模糊) ---
        Rectangle {
            id: backgroundBlur
            anchors.fill: parent
            radius: 12 // 扁平化通常采用适中的圆角
            color: hoverArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0.15)

            // 仅对背景内容开启模糊，不影响边框
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.7
            }

            Behavior on color { ColorAnimation { duration: 250 } }
        }

        // --- 2. 扁平化边框层 (确保边缘绝对清晰) ---
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.4) // 清晰的浅色描边
            border.width: 1
        }

        // --- 3. 内容布局层 ---
        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // --- 顶部标题栏：内切重合 + 同宽 ---
            Rectangle {
                id: headerBar
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                // 顶部圆角与外框一致，底部圆角为0实现“内切”效果
                radius: 12
                color: Qt.rgba(tagColor.r, tagColor.g, tagColor.b, 0.85)

                // 遮盖层：利用一个小矩形遮掉 headerBar 底部的圆角，使其与下方内容无缝衔接
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: parent.radius
                    color: parent.color
                    visible: true
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 15
                    anchors.rightMargin: 8

                    Text {
                        id: nameText
                        text: tagWindow.tagTitle
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Button {
                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                        background: null
                        contentItem: Text { text: "⋮"; font.pixelSize: 18; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: tagMenu.open()
                        Menu {
                            id: tagMenu
                            MenuItem { text: "打开所在文件夹"; onTriggered: Qt.openUrlExternally("file:///" + tagWindow.savePath) }
                            MenuItem {
                                text: "关闭并复原文件"
                                onTriggered: {
                                    appBackend.removeTagAndRestore(tagWindow.tagId, tagWindow.savePath);
                                    tagWindow.destroy();
                                }
                            }
                        }
                    }
                }
            }

            // --- 文件展示区 ---
            GridView {
                id: fileGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 8
                cellWidth: width / 3 // 自动平分宽度
                cellHeight: 80
                model: fileModel
                clip: true

                delegate: Item {
                    width: fileGrid.cellWidth; height: 80
                    Column {
                        anchors.centerIn: parent; spacing: 4
                        Rectangle {
                            width: 42; height: 42; radius: 8
                            color: Qt.rgba(tagColor.r, tagColor.g, tagColor.b, 0.1)
                            Text { text: "📄"; anchors.centerIn: parent; font.pixelSize: 22 }
                        }
                        Text {
                            text: model.fileName
                            font.pixelSize: 11; width: parent.width - 10; color: "#2c2c2c"
                            elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
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

        // --- 交互层 ---
        MouseArea {
            id: hoverArea
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            onPressed: tagWindow.startSystemMove()
        }

        // --- 右下角拉伸手柄 (扁平化设计) ---
        Item {
            id: resizeHandle
            width: 20; height: 20
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            z: 10

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.15);
                    ctx.lineWidth = 1;
                    ctx.moveTo(20, 10); ctx.lineTo(10, 20);
                    ctx.moveTo(20, 15); ctx.lineTo(15, 20);
                    ctx.stroke();
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeFDiagCursor
                property point lastPos
                onPressed: (mouse) => lastPos = Qt.point(mouse.x, mouse.y)
                onPositionChanged: (mouse) => {
                    if (pressed) {
                        let dx = mouse.x - lastPos.x;
                        let dy = mouse.y - lastPos.y;
                        if (tagWindow.width + dx > 180) tagWindow.width += dx;
                        if (tagWindow.height + dy > 120) tagWindow.height += dy;
                    }
                }
            }
        }
    }
}
