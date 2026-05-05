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

    // 觸發 DWM 重新計算非客戶區，且使用初始位置，并在启动时恢复已有文件
    Component.onCompleted: {
        if (appBackend.initNativeWindow) {
            appBackend.initNativeWindow(tagWindow, true);
        }
        
        if (appBackend.registerTagWindowId) {
            appBackend.registerTagWindowId(tagWindow, tagWindow.tagId);
        }

        // +++ 新增：启动时自动去物理文件夹里把文件读出来，塞进格子里 +++
        if (appBackend.getFilesInFolder) {
            var existingFiles = appBackend.getFilesInFolder(tagWindow.savePath);
            for (var i = 0; i < existingFiles.length; i++) {
                fileModel.append({ "fileName": existingFiles[i] });
            }
            console.log("📂 贴纸 [" + tagWindow.tagTitle + "] 已从文件夹恢复文件数量:", existingFiles.length);
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
                        anchors.margins: 4 
                        
                        // 为了容纳 3 行文字，稍微增加一点格子高度
                        cellWidth: 76
                        cellHeight: 104 
                        model: fileModel
                        clip: true
                        
                        // 默认不选中任何项
                        currentIndex: -1

                        // 点击空白区域取消选中
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: fileGrid.currentIndex = -1
                        }

                        delegate: Item {
                            id: delegateItem
                            width: fileGrid.cellWidth; height: fileGrid.cellHeight
                            
                            // 核心状态：当前项是否被选中
                            property bool isSelected: GridView.isCurrentItem

                            // 智能匹配文件图标和颜色的函数
                            function getFileInfo(name) {
                                var ext = name.split('.').pop().toLowerCase();
                                if (name.indexOf('.') === -1) ext = "folder"; // 无后缀

                                var info = { icon: "📄", colorCode: "#808080" }; // 默认
                                
                                if (["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg"].includes(ext)) { info.icon = "🖼️"; info.colorCode = "#0B8043"; }
                                else if (["pdf"].includes(ext)) { info.icon = "📕"; info.colorCode = "#DB4437"; }
                                else if (["doc", "docx"].includes(ext)) { info.icon = "📘"; info.colorCode = "#4285F4"; }
                                else if (["xls", "xlsx", "csv"].includes(ext)) { info.icon = "📗"; info.colorCode = "#0F9D58"; }
                                else if (["ppt", "pptx"].includes(ext)) { info.icon = "📙"; info.colorCode = "#F4B400"; }
                                else if (["txt", "md", "rtf"].includes(ext)) { info.icon = "📝"; info.colorCode = "#5F6368"; }
                                else if (["zip", "rar", "7z", "tar", "gz"].includes(ext)) { info.icon = "📦"; info.colorCode = "#8D6E63"; }
                                else if (["mp4", "mkv", "avi", "mov"].includes(ext)) { info.icon = "🎬"; info.colorCode = "#E91E63"; }
                                else if (["mp3", "wav", "flac"].includes(ext)) { info.icon = "🎵"; info.colorCode = "#9C27B0"; }
                                else if (["exe", "msi", "bat", "lnk"].includes(ext)) { info.icon = "⚙️"; info.colorCode = "#607D8B"; }
                                else if (["cpp", "h", "qml", "js", "json", "py"].includes(ext)) { info.icon = "💻"; info.colorCode = "#3F51B5"; }
                                else if (ext === "folder") { info.icon = "📁"; info.colorCode = "#F4B400"; }
                                
                                return info;
                            }

                            property var fileInfo: getFileInfo(model.fileName)
                            property color tColor: fileInfo.colorCode

                            // 整个项的层级：选中时必须置顶，防止展开的长文字被下方的图标遮住
                            z: isSelected ? 100 : 1

                            // == 1. 图标区域（改为顶部绝对对齐，彻底解决高低不平问题）==
                            Rectangle {
                                id: iconRect
                                anchors.top: parent.top
                                anchors.topMargin: 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 44; height: 44; radius: 10
                                
                                // 根据选中/悬浮状态和文件类型动态变换颜色
                                color: isSelected ? Qt.rgba(tColor.r, tColor.g, tColor.b, 0.3) :
                                       (itemMouse.containsMouse ? Qt.rgba(tColor.r, tColor.g, tColor.b, 0.2) : 
                                       Qt.rgba(tColor.r, tColor.g, tColor.b, 0.1))
                                
                                border.color: isSelected ? tColor : (itemMouse.containsMouse ? Qt.rgba(tColor.r, tColor.g, tColor.b, 0.3) : "transparent")
                                border.width: isSelected || itemMouse.containsMouse ? 1 : 0
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    text: delegateItem.fileInfo.icon
                                    anchors.centerIn: parent
                                    font.pixelSize: 22
                                }
                            }

                            // == 2. 文字区域（带弹出效果）==
                            Rectangle {
                                id: textBg
                                anchors.top: iconRect.bottom
                                anchors.topMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                
                                width: fileGrid.cellWidth - 4
                                // 核心：高度跟随文字的实际高度自动拉伸
                                height: fileNameText.implicitHeight + 8
                                radius: 6
                                
                                // 选中时变成实心白底，防止展开后文字和背景融为一体看不清
                                color: isSelected ? "#ffffff" : "transparent"
                                border.color: isSelected ? Qt.rgba(0,0,0,0.1) : "transparent"
                                
                                // 选中时加一点发光阴影效果
                                layer.enabled: isSelected
                                layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 8.0; shadowColor: Qt.rgba(0,0,0,0.15) }

                                Text {
                                    id: fileNameText
                                    anchors.centerIn: parent
                                    width: parent.width - 4
                                    text: model.fileName
                                    font.pixelSize: 11
                                    color: isSelected ? "#000000" : "#1D1D1F"
                                    
                                    // 开启折行
                                    wrapMode: Text.WrapAnywhere
                                    // 未选中时最多3行，选中时可无限拓展（比如 99 行）
                                    maximumLineCount: isSelected ? 99 : 3
                                    // 选中时取消省略号
                                    elide: isSelected ? Text.ElideNone : Text.ElideRight
                                    
                                    horizontalAlignment: Text.AlignHCenter
                                    lineHeight: 1.1
                                    // 选中时字体加粗，更清晰
                                    font.weight: isSelected ? Font.DemiBold : Font.Medium
                                }
                            }

                            // == 3. 鼠标交互 ==
                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                
                                // 单击选中（展开文字）
                                onClicked: {
                                    fileGrid.currentIndex = index;
                                }
                                
                                // 双击打开文件
                                onDoubleClicked: {
                                    Qt.openUrlExternally("file:///" + tagWindow.savePath + "/" + model.fileName)
                                }
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
