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
    // 起始位置（由 Main.qml 級聯計算或還原保存值）
    property int startX: 100
    property int startY: 100

    signal tagClosed(string tagId)

    width: tagWidth
    height: tagHeight

    // 【新增】告诉系统原生缩放时的最小界限
    minimumWidth: 220
    minimumHeight: 220

    x: startX
    y: startY
    visible: true
    // 连 Qt.Tool 和 WindowStaysOnBottomHint 都不需要了，因为桌面的子窗口天生就在底层且不在任务栏
    flags: Qt.FramelessWindowHint
    // flags: Qt.Tool | Qt.WindowStaysOnBottomHint
    // flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"

    // 觸發 DWM 重新計算非客戶區，且使用初始位置
    Component.onCompleted: {
        if (appBackend.initNativeWindow) {
            // 【修改】：传入 true，明确自己是贴纸
            appBackend.initNativeWindow(tagWindow, true);
        }
        // +++ 向底层注册自己的句柄，建立原生拖拽通道 +++
        if (appBackend.registerTagWindowId) {
            appBackend.registerTagWindowId(tagWindow, tagWindow.tagId);
        }
    }

    // 位置/尺寸變化後延遲保存（去抖 800ms）
    Timer {
        id: saveGeoDebounce
        interval: 800
        onTriggered: {
            if (appBackend.updateTagGeometry) {
                appBackend.updateTagGeometry(tagWindow.tagId,
                    tagWindow.x, tagWindow.y,
                    tagWindow.width, tagWindow.height);
            }
        }
    }
    onXChanged: saveGeoDebounce.restart()
    onYChanged: saveGeoDebounce.restart()
    onWidthChanged: saveGeoDebounce.restart()
    onHeightChanged: saveGeoDebounce.restart()

    ListModel { id: fileModel }

    // ===== Apple 黄金比例设计常数 =====
    readonly property int outerRadius: 28
    readonly property int cardPadding: 6
    readonly property int capsuleRadius: outerRadius - cardPadding   // 同心圆角 22
    readonly property int capsuleHeight: 66

    // --- 主卡片（边距 20px：安全容纳阴影 + 防抗锯齿切边）---
    Item {
        anchors.fill: parent
        anchors.margins: 20

        // ---- 卡片本体 + Apple 多层阴影 ----
        Rectangle {
            id: cardBody
            anchors.fill: parent
            radius: outerRadius
            color: "#F5F5F7"

            // 墊底的 MouseArea：點擊卡片空白處時置頂
            MouseArea {
                anchors.fill: parent
                onPressed: tagWindow.raise()
            }

            // 内白边（Apple 招牌 inset border）
            Rectangle {
                anchors.fill: parent
                radius: outerRadius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.8)
                border.width: 1
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
                        onPressed: {
                            tagWindow.raise();          // 被抓取時主動提權
                            tagWindow.startSystemMove();
                        }
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
                                onClicked: { if (tagMenu.opened) tagMenu.close(); else tagMenu.open(); }
                            }

                            Popup {
                                id: tagMenu
                                y: 40
                                x: parent.width - 150
                                width: 150
                                padding: 4
                                closePolicy: Popup.CloseOnEscape
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
                                            { text: "修改贴纸名称", action: function() { tagMenu.close(); renameDialog.open(); } },
                                            { text: "打开所在文件夹", action: function() { Qt.openUrlExternally("file:///" + tagWindow.savePath); tagMenu.close(); } },
                                            { text: "关闭并复原文件", action: function() { tagWindow.tagClosed(tagWindow.tagId); appBackend.removeTagAndRestore(tagWindow.tagId, tagWindow.savePath); tagWindow.destroy(); } }
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
                        // 给网格边缘留一点呼吸空间
                        anchors.margins: 4 
                        
                        // 1. 固定且紧凑的单元格尺寸
                        cellWidth: 76
                        cellHeight: 88
                        model: fileModel
                        clip: true

                        delegate: Item {
                            width: fileGrid.cellWidth; height: fileGrid.cellHeight
                            
                            // 2. 增加现代 UI 的悬停反馈背景
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 8
                                color: itemMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.05) : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4 // 缩小图标和文字的间距

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 40; height: 40; radius: 10 // 图标稍微精简一点
                                    color: Qt.rgba(tagColor.r, tagColor.g, tagColor.b, 0.1)
                                    Text {
                                        text: "\uD83D\uDCC4"
                                        anchors.centerIn: parent
                                        font.pixelSize: 20
                                    }
                                }

                                Text {
                                    text: model.fileName
                                    font.pixelSize: 11
                                    color: "#1D1D1F"
                                    // 让文字占用整个格子的宽度
                                    width: fileGrid.cellWidth - 8 
                                    
                                    // 3. 核心修改：允许最多两行折行显示
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    
                                    horizontalAlignment: Text.AlignHCenter
                                    lineHeight: 1.1 // 紧凑的行高
                                    font.weight: Font.Medium
                                }
                            }
                            
                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onDoubleClicked: Qt.openUrlExternally("file:///" + tagWindow.savePath + "/" + model.fileName)
                            }
                        }

                        // +++ 监听底层传来的原生拖拽事件 +++
                        Connections {
                            target: appBackend
                            function onFilesDroppedNative(droppedTagId, fileUrls) {
                                if (tagWindow.tagId === droppedTagId) {
                                    console.log("🚀 [底层原生接管] 成功捕获拖入文件！数量:", fileUrls.length);

                                    for (var i = 0; i < fileUrls.length; i++) {
                                        var urlStr = fileUrls[i];
                                        console.log("准备移动文件:", urlStr);

                                        if (appBackend.moveFileToTag(urlStr, tagWindow.savePath)) {
                                            var fName = urlStr.substring(urlStr.lastIndexOf("/") + 1);
                                            fileModel.append({ "fileName": fName });
                                        } else {
                                            console.error("❌ 文件移动失败: ", urlStr);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- 右下角拉伸手柄 (iPadOS 极简圆弧) ---
        Item {
            id: resizeHandle
            width: 36; height: 36
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            z: 10

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();

                    // iPadOS 风格的圆润粗线条
                    ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.25); // 柔和的半透明灰色
                    ctx.lineWidth = 4;
                    ctx.lineCap = "round";

                    // 巧妙的几何计算：为了视觉上协调，圆弧应当与卡片的圆角(outerRadius: 28)同心
                    var cx = 8;
                    var cy = 8;
                    var r = 16;

                    ctx.beginPath();
                    // 从 0 度（水平向右）画到 90 度（垂直向下），形成内收的完美圆弧
                    ctx.arc(cx, cy, r, 0, Math.PI / 2);
                    ctx.stroke();
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeFDiagCursor

                onPressed: {
                    tagWindow.raise();                  // 準備縮放時主動提權

                    // 【新增】核心修复：直接调用系统的右下角缩放机制！
                    tagWindow.startSystemResize(Qt.RightEdge | Qt.BottomEdge);
                }
            }
        }
    }

    // ===== 修改名称对话窗 =====
    Dialog {
        id: renameDialog
        modal: true
        dim: false
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 220
        height: 140
        padding: 16
        background: Rectangle {
            radius: 14
            color: "#F5F5F7"
            border.color: Qt.rgba(0,0,0,0.08)
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0,0,0,0.15)
                shadowBlur: 0.5
                shadowVerticalOffset: 8
            }
        }

        Overlay.modal: Rectangle { color: Qt.rgba(0,0,0,0.2) }

        contentItem: ColumnLayout {
            spacing: 12
            Text {
                text: "修改贴纸名称"
                font.pixelSize: 16
                font.weight: Font.Medium
                color: "#1D1D1F"
            }
            TextField {
                id: renameInput
                Layout.fillWidth: true
                text: tagWindow.tagTitle
                selectByMouse: true
                font.pixelSize: 14
                padding: 8
                background: Rectangle {
                    id: renameInputBg
                    radius: 8
                    color: "white"
                    border.color: Qt.rgba(0,0,0,0.12)
                    border.width: 1
                }
                onAccepted: renameConfirm.clicked()
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Button {
                    id: renameCancel
                    text: "取消"
                    flat: true
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        renameInputBg.border.color = Qt.rgba(0,0,0,0.12);
                        renameDialog.close();
                    }
                }
                Button {
                    id: renameConfirm
                    text: "确定"
                    focusPolicy: Qt.NoFocus
                    background: Rectangle {
                        radius: 8
                        color: tagColor
                    }
                    contentItem: Text {
                        text: "确定"
                        color: "white"
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        var newName = renameInput.text.trim();
                        if (newName.length === 0) {
                            renameInputBg.border.color = "#FF3B30";
                            return;
                        }
                        tagWindow.tagTitle = newName;
                        appBackend.renameTag(tagWindow.tagId, newName);
                        renameInputBg.border.color = Qt.rgba(0,0,0,0.12);
                        renameDialog.close();
                    }
                }
            }
        }
    }
}
