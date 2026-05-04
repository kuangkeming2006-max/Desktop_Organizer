import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

ApplicationWindow {
    id: root
    width: 1050
    height: 700
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"

    property int activeIndex: 0
    property string globalRootPath: "D:/Stickers"
    property var activeTagWindows: ({})

    // ===== 自製最大化/還原動畫 =====
    property bool isMaximized: false
    property int normalX: 0
    property int normalY: 0
    property int normalW: 1050
    property int normalH: 700

    ParallelAnimation {
        id: maxAnim
        NumberAnimation { id: maxAnimX; target: root; property: "x"; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { id: maxAnimY; target: root; property: "y"; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { id: maxAnimW; target: root; property: "width"; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { id: maxAnimH; target: root; property: "height"; duration: 200; easing.type: Easing.OutCubic }
    }

    function toggleMaximize() {
        if (isMaximized) {
            maxAnimX.to = normalX; maxAnimY.to = normalY;
            maxAnimW.to = normalW; maxAnimH.to = normalH;
            maxAnim.start();
            isMaximized = false;
        } else {
            normalX = root.x; normalY = root.y;
            normalW = root.width; normalH = root.height;
            maxAnimX.to = 0; maxAnimY.to = 0;
            maxAnimW.to = Screen.width; maxAnimH.to = Screen.height;
            maxAnim.start();
            isMaximized = true;
        }
    }

    // ===== 深浅色模式控制 =====
    property bool isDarkMode: false

    // --- 黑白纯色 + 云母层级 色板 ---
    // 第1层：基础介质层 (Window Background)
    readonly property color mdSurfaceBg: isDarkMode ? Qt.rgba(0.05, 0.05, 0.05, 0.98) : Qt.rgba(0.98, 0.98, 0.98, 0.98)
    
    // 第2层：卡片层 (Content card / Sidebar)
    readonly property color mdCardBg: isDarkMode ? Qt.rgba(0.12, 0.12, 0.12, 0.85) : Qt.rgba(1.0, 1.0, 1.0, 0.85)
    readonly property color mdCardBorder: isDarkMode ? Qt.rgba(1.0, 1.0, 1.0, 0.1) : Qt.rgba(0.0, 0.0, 0.0, 0.08)
    
    // 第3层：输入框/交互元素层 (Input/Hover areas)
    readonly property color mdInputBg: isDarkMode ? Qt.rgba(0.18, 0.18, 0.18, 0.6) : Qt.rgba(0.92, 0.92, 0.92, 0.6)
    readonly property color mdHover: isDarkMode ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : Qt.rgba(0.0, 0.0, 0.0, 0.05)
    
    // 文本颜色
    readonly property color mdTextPrimary: isDarkMode ? "#ffffff" : "#000000"
    readonly property color mdTextSecondary: isDarkMode ? "#888888" : "#666666"

    readonly property color currentThemeColor: isDarkMode ? "#ffffff" : "#222222"
    readonly property color currentThemeColorInv: isDarkMode ? "#000000" : "#ffffff"

    readonly property int menuHeight: 48
    readonly property int menuSpacing: 10

    ListModel {
        id: sidebarModel
        ListElement { name: "添加标签"; icon: "❖"; colorCode: "#0b57d0" }
        ListElement { name: "管理贴纸"; icon: "◫"; colorCode: "#9333ea" }
        ListElement { name: "设置中心"; icon: "⛭"; colorCode: "#e37400" }
        ListElement { name: "关于项目"; icon: "ⓘ"; colorCode: "#188038" }
    }

    ListModel {
        id: activeTagsModel
    }

    Component.onCompleted: {
        // 呼叫 C++ 方法注入原生視窗樣式以啟用 DWM 動畫
        if (appBackend.setNativeWindowStyle) {
            appBackend.setNativeWindowStyle(root);
        }

        globalRootPath = appBackend.getRootPath();
        var savedTags = appBackend.getSavedTags();
        var comp = Qt.createComponent("DesktopTag.qml");

        for (var i = 0; i < savedTags.length; i++) {
            var tagData = savedTags[i];
            activeTagsModel.append({
                "tagId": tagData.id,
                "title": tagData.tagTitle,
                "path": tagData.savePath,
                "tagColor": tagData.tagColor,
                "fileCount": 0
            });

            if (comp.status === Component.Ready) {
                var qmlProps = Object.assign({}, tagData);
                qmlProps.tagId = qmlProps.id;
                delete qmlProps.id;
                var tag = comp.createObject(null, qmlProps);
                if (tag) {
                    root.activeTagWindows[qmlProps.tagId] = tag;
                }
            }
        }
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        anchors.margins: 20
        radius: 12
        color: "transparent"

        // === Layer 1: 底层云母材质 ===
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: mdSurfaceBg
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        // 外层轻微边框
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: isDarkMode ? Qt.rgba(1,1,1,0.15) : Qt.rgba(0,0,0,0.15)
            Behavior on border.color { ColorAnimation { duration: 300 } }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: isDarkMode ? Qt.rgba(0, 0, 0, 0.8) : Qt.rgba(0, 0, 0, 0.35)
            shadowBlur: 32.0
            shadowVerticalOffset: 12
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ==================== 1. 标题栏区域 ====================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: "transparent"

                MouseArea {
                    anchors.fill: parent
                    onPositionChanged: (mouse) => {
                        if (pressedButtons & Qt.LeftButton) root.startSystemMove()
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Row {
                        Layout.leftMargin: 24
                        spacing: 12
                        Rectangle {
                            width: 14; height: 14; radius: 7; color: "#ff5f56"
                            border.color: Qt.rgba(0,0,0,0.1); border.width: 0.5
                            scale: closeMouse.pressed ? 0.85 : (closeMouse.containsMouse ? 1.1 : 1.0)
                            opacity: closeMouse.containsMouse ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.close() }
                        }
                        Rectangle {
                            width: 14; height: 14; radius: 7; color: "#ffbd2e"
                            border.color: Qt.rgba(0,0,0,0.1); border.width: 0.5
                            scale: minMouse.pressed ? 0.85 : (minMouse.containsMouse ? 1.1 : 1.0)
                            opacity: minMouse.containsMouse ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            MouseArea { id: minMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.showMinimized() }
                        }
                        Rectangle {
                            width: 14; height: 14; radius: 7; color: "#27c93f"
                            border.color: Qt.rgba(0,0,0,0.1); border.width: 0.5
                            scale: maxMouse.pressed ? 0.85 : (maxMouse.containsMouse ? 1.1 : 1.0)
                            opacity: maxMouse.containsMouse ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            MouseArea { id: maxMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleMaximize() }
                        }
                    }

                    Text {
                        text: "Desktop Organizer"
                        color: mdTextSecondary
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 20
                Layout.topMargin: 0
                spacing: 24

                // ==================== 2. 左侧导航菜单 ====================
                Item {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 220

                    Rectangle {
                        id: capsuleBg
                        x: 0; width: parent.width; height: menuHeight; radius: menuHeight / 2
                        property color activeAcc: sidebarModel.get(root.activeIndex).colorCode
                        color: isDarkMode ? Qt.rgba(activeAcc.r, activeAcc.g, activeAcc.b, 0.2) : Qt.rgba(activeAcc.r, activeAcc.g, activeAcc.b, 0.15)
                        border.color: isDarkMode ? Qt.rgba(activeAcc.r, activeAcc.g, activeAcc.b, 0.5) : Qt.rgba(activeAcc.r, activeAcc.g, activeAcc.b, 0.3)
                        border.width: 1
                        y: 10 + root.activeIndex * (menuHeight + menuSpacing)
                        Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                        Behavior on color { ColorAnimation { duration: 300 } }
                        Behavior on border.color { ColorAnimation { duration: 300 } }
                    }

                    Column {
                        anchors.top: parent.top; anchors.topMargin: 10; anchors.left: parent.left; anchors.right: parent.right; spacing: menuSpacing

                        Repeater {
                            model: sidebarModel
                            delegate: Item {
                                width: parent.width; height: menuHeight

                                Rectangle {
                                    x: 0; width: parent.width; height: parent.height; radius: parent.height / 2
                                    color: (hMouse.containsMouse && root.activeIndex !== index) ? mdHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: 24; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                                    Text {
                                        text: model.icon; font.pixelSize: 18
                                        color: root.activeIndex === index ? model.colorCode : mdTextSecondary
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                    }
                                    Text {
                                        text: model.name; font.pixelSize: 15; font.weight: root.activeIndex === index ? Font.DemiBold : Font.Medium
                                        color: root.activeIndex === index ? model.colorCode : mdTextSecondary
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                    }
                                }

                                MouseArea {
                                    id: hMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.activeIndex = index
                                }
                            }
                        }
                    }

                    // --- 新增：深色/浅色 切换按钮 ---
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 160; height: 44; radius: 22
                        color: themeMouse.containsMouse ? mdHover : "transparent"
                        border.color: mdCardBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 12
                            Text {
                                text: isDarkMode ? "☽" : "☼"
                                font.pixelSize: 20
                                color: mdTextPrimary
                            }
                            Text {
                                text: isDarkMode ? "深色模式" : "浅色模式"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                color: mdTextPrimary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: themeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                isDarkMode = !isDarkMode;
                            }
                        }
                    }
                }

                // ==================== 3. 主内容区卡片 (Layer 2) ====================
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 16
                    border.color: mdCardBorder; border.width: 1
                    color: mdCardBg
                    Behavior on color { ColorAnimation { duration: 300 } }

                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: isDarkMode ? Qt.rgba(0,0,0,0.4) : Qt.rgba(0,0,0,0.05); shadowBlur: 2.0; shadowVerticalOffset: 2 }

                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.activeIndex

                        // ----------------- Page 0: 添加标签 -----------------
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 48; spacing: 24

                                ColumnLayout {
                                    spacing: 8
                                    Text { text: "配置新标签"; font.pixelSize: 26; font.weight: Font.DemiBold; color: mdTextPrimary }
                                    Text { text: "创建一个带有自定义规则的桌面收纳区。"; font.pixelSize: 14; color: mdTextSecondary }
                                }

                                GridLayout {
                                    columns: 2; rowSpacing: 20; columnSpacing: 24; Layout.fillWidth: true; Layout.topMargin: 10

                                    // --- Layer 3: 输入框和元素 ---
                                    Text { text: "贴纸名称"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputName
                                        Layout.fillWidth: true; font.pixelSize: 14; color: mdTextPrimary; placeholderText: "例如：PDF 收纳区"
                                        verticalAlignment: TextInput.AlignVCenter; leftPadding: 16; rightPadding: 16
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1; Behavior on border.color { ColorAnimation { duration: 200 } } Behavior on color { ColorAnimation { duration: 200 } } }
                                    }

                                    Text { text: "尺寸 (宽x高)"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    RowLayout {
                                        spacing: 12
                                        TextField {
                                            id: inputW
                                            Layout.preferredWidth: 100; text: "220"; font.pixelSize: 14; color: mdTextPrimary; horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                                            background: Rectangle { implicitHeight: 44; radius: 8; color: mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                        }
                                        Text { text: "×"; color: mdTextSecondary; font.pixelSize: 16 }
                                        TextField {
                                            id: inputH
                                            Layout.preferredWidth: 100; text: "280"; font.pixelSize: 14; color: mdTextPrimary; horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                                            background: Rectangle { implicitHeight: 44; radius: 8; color: mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                        }
                                    }

                                    Text { text: "主题颜色"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputColor
                                        Layout.fillWidth: true; text: isDarkMode ? "#ffffff" : "#000000"; placeholderText: "颜色代码"; font.pixelSize: 14; color: mdTextPrimary
                                        verticalAlignment: TextInput.AlignVCenter; leftPadding: 16; rightPadding: 16
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                    }

                                    Text { text: "映射地址"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputPath
                                        Layout.fillWidth: true; readOnly: true; color: mdTextSecondary; font.pixelSize: 14
                                        text: root.globalRootPath + "/" + (inputName.text.trim() === "" ? "新贴纸" : inputName.text.trim())
                                        verticalAlignment: TextInput.AlignVCenter; leftPadding: 16; rightPadding: 16
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: isDarkMode ? Qt.rgba(0,0,0,0.3) : Qt.rgba(0,0,0,0.02); border.color: mdCardBorder; border.width: 1 }
                                    }

                                    Text { text: "限制后缀"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputExt
                                        Layout.fillWidth: true; text: "*.pdf, *.docx"; placeholderText: "多后缀逗号分隔"; font.pixelSize: 14; color: mdTextPrimary
                                        verticalAlignment: TextInput.AlignVCenter; leftPadding: 16; rightPadding: 16
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                Rectangle {
                                    Layout.alignment: Qt.AlignRight; width: 140; height: 44; radius: 8
                                    color: btnMouse.pressed ? Qt.darker(currentThemeColor, 1.2) : currentThemeColor
                                    opacity: btnMouse.containsMouse ? 0.85 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Text { text: "生成贴纸"; color: currentThemeColorInv; font.pixelSize: 15; font.weight: Font.Medium; anchors.centerIn: parent }

                                    MouseArea {
                                        id: btnMouse; anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                            var comp = Qt.createComponent("DesktopTag.qml");
                                            if (comp.status === Component.Ready) {
                                                var newId = "tag_" + new Date().getTime();
                                                var jsonProps = {
                                                    "id": newId, "tagTitle": inputName.text, "tagWidth": parseInt(inputW.text), "tagHeight": parseInt(inputH.text), "tagColor": inputColor.text, "savePath": inputPath.text, "allowedExts": inputExt.text
                                                };
                                                var qmlProps = Object.assign({}, jsonProps);
                                                qmlProps.tagId = newId; delete qmlProps.id;
                                                var tag = comp.createObject(null, qmlProps);
                                                if (tag) {
                                                    root.activeTagWindows[newId] = tag;
                                                    appBackend.saveNewTag(jsonProps);
                                                    activeTagsModel.append({ "tagId": newId, "title": jsonProps.tagTitle, "path": jsonProps.savePath, "tagColor": jsonProps.tagColor, "fileCount": 0 });
                                                    root.requestActivate(); root.raise();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ----------------- Page 1: 管理贴纸 -----------------
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 48; spacing: 24
                                Text { text: "管理活动贴纸"; font.pixelSize: 26; font.weight: Font.DemiBold; color: mdTextPrimary }

                                GridView {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    cellWidth: 260; cellHeight: 140
                                    model: activeTagsModel
                                    clip: true

                                    delegate: Rectangle {
                                        width: 240; height: 120; radius: 12;
                                        color: mdInputBg
                                        border.color: mdCardBorder; border.width: 1

                                        layer.enabled: true
                                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: isDarkMode ? Qt.rgba(0,0,0,0.5) : Qt.rgba(0,0,0,0.06); shadowBlur: 3.0; shadowVerticalOffset: 3 }

                                        Column {
                                            anchors.fill: parent; anchors.margins: 20; spacing: 8
                                            RowLayout {
                                                width: parent.width; spacing: 10
                                                Rectangle { width: 14; height: 14; radius: 7; color: model.tagColor; border.width: 1; border.color: mdCardBorder }
                                                Text { text: model.title; font.weight: Font.DemiBold; color: mdTextPrimary; font.pixelSize: 16; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }
                                            Text { text: "映射: " + model.path; color: mdTextSecondary; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
                                            Text { text: "当前收纳: " + model.fileCount + " 个文件"; color: mdTextSecondary; font.pixelSize: 13 }
                                        }

                                        Rectangle {
                                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12
                                            width: 28; height: 28; radius: 14; color: isDarkMode ? "#331111" : "#fce8e6"
                                            border.color: isDarkMode ? "#ff4444" : "transparent"; border.width: isDarkMode ? 1 : 0
                                            opacity: delMouse.containsMouse ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }

                                            Text { text: "✕"; color: isDarkMode ? "#ff6666" : "#ea4335"; font.pixelSize: 14; font.weight: Font.DemiBold; anchors.centerIn: parent }
                                            MouseArea {
                                                id: delMouse; anchors.fill: parent; hoverEnabled: true;
                                                onClicked: {
                                                    var targetId = model.tagId;
                                                    appBackend.removeTagAndRestore(targetId, model.path);
                                                    if (root.activeTagWindows[targetId]) {
                                                        root.activeTagWindows[targetId].destroy();
                                                        var updatedWindows = root.activeTagWindows; delete updatedWindows[targetId]; root.activeTagWindows = updatedWindows;
                                                    }
                                                    activeTagsModel.remove(index);
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent; hoverEnabled: true; z: -1
                                            onEntered: delMouse.opacity = 1.0
                                            onExited: if(!delMouse.containsMouse) delMouse.opacity = 0.0
                                        }
                                    }
                                }
                            }
                        }

                        // ----------------- Page 2: 设置中心 -----------------
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 48; spacing: 24
                                Text { text: "系统偏好设置"; font.pixelSize: 26; font.weight: Font.DemiBold; color: mdTextPrimary }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: 120; radius: 12
                                    color: mdInputBg; border.color: mdCardBorder; border.width: 1
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 24
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Text { text: "默认收纳根目录"; font.pixelSize: 16; font.weight: Font.DemiBold; color: mdTextPrimary }
                                            Text { text: "新建贴纸时，将在此目录下自动建立同名文件夹存放拖入的文件。"; font.pixelSize: 13; color: mdTextSecondary }

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 16; Layout.topMargin: 8
                                                TextField {
                                                    id: rootDirInput
                                                    Layout.fillWidth: true; font.pixelSize: 14; color: mdTextPrimary
                                                    text: root.globalRootPath
                                                    verticalAlignment: TextInput.AlignVCenter; leftPadding: 16; rightPadding: 16
                                                    background: Rectangle { implicitHeight: 40; radius: 8; color: mdSurfaceBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: 1 }
                                                    onEditingFinished: { root.globalRootPath = text; appBackend.setRootPath(text); }
                                                }
                                                Button {
                                                    text: "应用"
                                                    background: Rectangle { implicitWidth: 80; implicitHeight: 40; radius: 8; color: currentThemeColor; opacity: parent.hovered ? 0.85 : 1.0 }
                                                    contentItem: Text { text: "应用"; color: currentThemeColorInv; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 14; font.weight: Font.Medium }
                                                    onClicked: { root.globalRootPath = rootDirInput.text; appBackend.setRootPath(rootDirInput.text); }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: 80; radius: 12
                                    color: mdInputBg; border.color: mdCardBorder; border.width: 1
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 24
                                        Column {
                                            Layout.fillWidth: true; spacing: 6
                                            Text { text: "开机自动启动"; font.pixelSize: 16; font.weight: Font.DemiBold; color: mdTextPrimary }
                                            Text { text: "登录 Windows 后自动恢复所有桌面贴纸"; font.pixelSize: 13; color: mdTextSecondary }
                                        }
                                        Switch {
                                            id: bootSwitch; checked: true
                                            indicator: Rectangle {
                                                implicitWidth: 44; implicitHeight: 24; radius: 12
                                                color: bootSwitch.checked ? currentThemeColor : (isDarkMode ? Qt.rgba(1,1,1,0.1) : Qt.rgba(0,0,0,0.1))
                                                border.color: bootSwitch.checked ? currentThemeColor : (isDarkMode ? Qt.rgba(1,1,1,0.2) : Qt.rgba(0,0,0,0.2))
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                Rectangle {
                                                    x: bootSwitch.checked ? parent.width - width - 2 : 2; y: 2; width: 20; height: 20; radius: 10; color: currentThemeColorInv
                                                    layer.enabled: true; layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 2.0; shadowColor: isDarkMode ? Qt.rgba(0,0,0,0.8) : Qt.rgba(0,0,0,0.2) }
                                                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                            onCheckedChanged: appBackend.setAutoStart(checked)
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        // ----------------- Page 3: 关于 -----------------
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 12

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter; width: 72; height: 72; radius: 24
                                    color: mdInputBg
                                    border.color: mdCardBorder; border.width: 1
                                    Text { text: "❖"; font.pixelSize: 36; color: mdTextPrimary; anchors.centerIn: parent }
                                }

                                Text { text: "Desktop Tool v0.7.1"; color: mdTextPrimary; font.pixelSize: 22; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 10 }
                                Text { text: "纯色云母 UI - Dark/Light"; color: mdTextSecondary; font.pixelSize: 15; font.weight: Font.Medium; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                    }
                }
            }
        }
    }
}