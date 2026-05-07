import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    width: 1050
    height: 700
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"

    // 攔截關閉事件 → 最小化到系統托盤
    onClosing: function(close) {
        close.accepted = false;
        appBackend.minimizeToTray(root);
    }

    // 【防重入鎖】：防止 DWM 刷新與 visibility 變化形成無限事件循環
    property bool isRefreshingDwm: false

    // 監聽 Visibility 變化（專門處理任務欄的最小化與還原）
    onVisibilityChanged: {
        if (!isRefreshingDwm && visibility !== Window.Minimized && visibility !== Window.Hidden) {
            isRefreshingDwm = true;
            if (appBackend.initNativeWindow) {
                forceDwmRefresh.start();
            }
        }
    }

    // 保持對 visible 的監聽（處理從系統托盤徹底隱藏後還原的情況）
    onVisibleChanged: {
        if (!isRefreshingDwm && visible && appBackend.initNativeWindow) {
            isRefreshingDwm = true;
            forceDwmRefresh.start();
        }
    }

    Timer {
        id: forceDwmRefresh
        interval: 50
        onTriggered: {
            if (appBackend.initNativeWindow) {
                appBackend.initNativeWindow(root, false);
            }
            // 延遲解鎖，防止風暴
            Qt.callLater(function() { root.isRefreshingDwm = false; })
        }
    }

    property int activeIndex: 0
    property string globalRootPath: "D:/Stickers"
    property var activeTagWindows: ({})
    // 1. 碰撞檢測：檢查給定的矩形區域是否與現有的貼紙重疊
    function isRectOverlapping(testX, testY, testW, testH) {
        for (var key in root.activeTagWindows) {
            var win = root.activeTagWindows[key];
            if (!win) continue;

            // 包圍盒碰撞算法 (留出 10px 的安全間距)
            var gap = 10;
            if (testX < win.x + win.width + gap &&
                testX + testW + gap > win.x &&
                testY < win.y + win.height + gap &&
                testY + testH + gap > win.y) {
                return true; // 發生重疊
            }
        }
        return false; // 當前位置是空的
    }

    // 2. 智能放置：從右上角開始掃描，尋找第一個不重疊的合適位置
    function findBestTagPosition(tagW, tagH) {
        var margin = 30;
        var gap = 20;

        // 獲取當前螢幕可用尺寸 (防多屏導致的總寬度過大，做個基礎限制)
        var screenW = Screen.desktopAvailableWidth > 0 ? Screen.desktopAvailableWidth : 1920;
        var screenH = Screen.desktopAvailableHeight > 0 ? Screen.desktopAvailableHeight : 1080;

        // 強行規避多屏導致的超大解析度 (比如 3840)，確保貼紙落在主視口內
        if (screenW > 3000) screenW = screenW / 2;

        var startX = screenW - tagW - margin;
        var startY = margin;

        var testX = startX;
        var testY = startY;

        // 最多嘗試掃描 50 個網格位置，防止死循環
        for (var i = 0; i < 50; i++) {
            if (!isRectOverlapping(testX, testY, tagW, tagH)) {
                break; // 找到空位了！
            }

            // 沒找到，往下移一格
            testY += tagH + gap;

            // 如果到底部了，換到左邊一列，Y 重置到頂部
            if (testY + tagH > screenH) {
                testY = startY;
                testX -= (tagW + gap);
            }
        }

        // 【終極安全鉗制】：無論如何計算，絕對不允許超出當前螢幕邊界
        testX = Math.max(10, Math.min(testX, screenW - tagW - 10));
        testY = Math.max(10, Math.min(testY, screenH - tagH - 10));

        return { x: testX, y: testY };
    }

    // 創建 DesktopTag 元件（處理非同步載入）
    function createTagComponent(callback) {
        var comp = Qt.createComponent("DesktopTag.qml");
        if (comp.status === Component.Ready) {
            callback(comp);
        } else if (comp.status === Component.Loading) {
            comp.statusChanged.connect(function() {
                if (comp.status === Component.Ready) {
                    callback(comp);
                } else {
                    console.error("Failed to load DesktopTag.qml:", comp.errorString());
                }
            });
        } else {
            console.error("Failed to load DesktopTag.qml:", comp.errorString());
        }
    }

    // 工廠方法創建 tagClosed 連接器（避免 for 迴圈閉包問題）
    function createTagCloser() {
        return function(tid) {
            // 清理模型
            for (var i = 0; i < activeTagsModel.count; i++) {
                if (activeTagsModel.get(i).tagId === tid) {
                    activeTagsModel.remove(i);
                    break;
                }
            }
            // 【新增】：清理字典，防止幽灵对象
            if (root.activeTagWindows[tid]) {
                root.activeTagWindows[tid].destroy();
                var updatedWindows = root.activeTagWindows;
                delete updatedWindows[tid];
                root.activeTagWindows = updatedWindows;
            }
        };
    }

    // ===== 使用 Windows 原生 DWM 最大化/還原動畫（無抽搐） =====
    function toggleMaximize() {
        if (appBackend.toggleMaximizeNative) {
            appBackend.toggleMaximizeNative(root);
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
        // 初始化系統托盤
        if (appBackend.initSystemTray) {
            appBackend.initSystemTray(root);
        }

        // 觸發 DWM 重新計算非客戶區（WM_NCCALCSIZE 將消除它）
        if (appBackend.initNativeWindow) {
            appBackend.initNativeWindow(root, false);
        }

        globalRootPath = appBackend.getRootPath();
        var savedTags = appBackend.getSavedTags();
        if (savedTags.length > 0) {

            var screenW = Screen.desktopAvailableWidth > 0 ? Screen.desktopAvailableWidth : 1920;
            var screenH = Screen.desktopAvailableHeight > 0 ? Screen.desktopAvailableHeight : 1080;
            if (screenW > 3000) screenW = screenW / 2; // 防多屏漂移

            createTagComponent(function(comp) {
                for (var i = 0; i < savedTags.length; i++) {
                    var tagData = savedTags[i];
                    // 在添加模型之前，先数一数文件夹里到底有几个文件
                    var actualFileCount = 0;
                    if (appBackend.getFilesInFolder) {
                        actualFileCount = appBackend.getFilesInFolder(tagData.savePath).length;
                    }

                    activeTagsModel.append({
                        "tagId": tagData.id,
                        "title": tagData.tagTitle,
                        "path": tagData.savePath,
                        "tagColor": tagData.tagColor,
                        "fileCount": actualFileCount,
                        "allowedExts": tagData.allowedExts || ""
                    });

                    var qmlProps = Object.assign({}, tagData);
                    qmlProps.tagId = qmlProps.id;
                    delete qmlProps.id;

                    var tW = qmlProps.tagWidth || 220;
                    var tH = qmlProps.tagHeight || 280;
                    var tX = qmlProps.x;
                    var tY = qmlProps.y;

                    if (tX === undefined || tY === undefined) {
                        var pos = root.findBestTagPosition(tW, tH);
                        tX = pos.x;
                        tY = pos.y;
                    } else {
                        // ==========================================
                        // 【越界抢救逻辑】：检查保存的坐标是否飞出当前屏幕
                        // ==========================================
                        var needsRescue = false;

                        if (tX + tW > screenW) { tX = screenW - tW - 20; needsRescue = true; } // 右溢出
                        if (tX < 0) { tX = 20; needsRescue = true; }                           // 左溢出
                        if (tY + tH > screenH) { tY = screenH - tH - 20; needsRescue = true; } // 底溢出
                        if (tY < 0) { tY = 20; needsRescue = true; }                           // 顶溢出

                        // 如果发生了抢救，立即通知 C++ 后端更新配置文件里的错误坐标
                        if (needsRescue && appBackend.updateTagGeometry) {
                            appBackend.updateTagGeometry(qmlProps.tagId, tX, tY, tW, tH);
                            console.log("已修复越界贴纸:", qmlProps.tagId, " 新坐标:", tX, tY);
                        }
                    }

                    qmlProps.startX = tX;
                    qmlProps.startY = tY;

                    // 直接以 null 作为父对象创建（因为一会儿要在 C++ 里给它找个"干爹"）
                    var tag = comp.createObject(null, qmlProps);
                    if (tag) {
                        root.activeTagWindows[qmlProps.tagId] = tag;
                        tag.show();

                        // 关键：窗口显示出来后，立刻执行 C++ 注入，把它拍死在桌面上
                        appBackend.stickToDesktop(tag);

                        tag.tagClosed.connect(createTagCloser());
                    }
                }
            });
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
                    onPositionChanged: {
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
                            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: appBackend.minimizeToTray(root) }
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
                        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
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

                                RowLayout {
                                    anchors.left: parent.left; anchors.leftMargin: 24; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                                    Text {
                                        text: model.icon; font.pixelSize: 18
                                        color: root.activeIndex === index ? model.colorCode : mdTextSecondary
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        text: model.name; font.pixelSize: 15; font.weight: root.activeIndex === index ? Font.DemiBold : Font.Medium
                                        color: root.activeIndex === index ? model.colorCode : mdTextSecondary
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                        Layout.alignment: Qt.AlignVCenter
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
                                        onTextChanged: inputNameBg.hasError = false
                                        background: Rectangle {
                                            id: inputNameBg
                                            property bool hasError: false
                                            implicitHeight: 44; radius: 8; color: mdInputBg; border.color: hasError ? "#FF3B30" : (parent.activeFocus ? currentThemeColor : mdCardBorder); border.width: parent.activeFocus || hasError ? 2 : 1; Behavior on border.color { ColorAnimation { duration: 200 } } Behavior on color { ColorAnimation { duration: 200 } }
                                        }
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

                                    // ================= 1. 优化的主题颜色选择 =================
                                    Text { 
                                        text: "主题颜色"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium
                                        Layout.alignment: Qt.AlignTop | Qt.AlignLeft; Layout.topMargin: 14 
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 12
                                        
                                        TextField {
                                            id: inputColor
                                            Layout.fillWidth: true; text: isDarkMode ? "#ffffff" : "#000000"; placeholderText: "颜色代码"; font.pixelSize: 14; color: mdTextPrimary
                                            verticalAlignment: TextInput.AlignVCenter; leftPadding: 16; rightPadding: 16
                                            background: Rectangle { implicitHeight: 44; radius: 8; color: mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                        }

                                        // 新增：快捷颜色块预设
                                        Row {
                                            spacing: 14
                                            Repeater {
                                                model: ["#0b57d0", "#188038", "#d93025", "#9333ea", "#e37400", "#e91e63"]
                                                delegate: Rectangle {
                                                    width: 28; height: 28; radius: 14
                                                    color: modelData
                                                    border.color: inputColor.text.toLowerCase() === modelData.toLowerCase() ? mdTextPrimary : Qt.rgba(0,0,0,0.1)
                                                    border.width: inputColor.text.toLowerCase() === modelData.toLowerCase() ? 2 : 1
                                                    
                                                    scale: colorMouse.containsMouse ? 1.15 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                                    MouseArea {
                                                        id: colorMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: inputColor.text = modelData
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ================= 2. 优化的映射地址 =================
                                    Text { text: "映射地址"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12
                                        
                                        TextField {
                                            id: inputPath
                                            Layout.fillWidth: true; readOnly: true; color: mdTextSecondary; font.pixelSize: 14
                                            text: root.globalRootPath + "/" + (inputName.text.trim() === "" ? "新贴纸" : inputName.text.trim())
                                            verticalAlignment: TextInput.AlignVCenter; leftPadding: 16; rightPadding: 16
                                            background: Rectangle { implicitHeight: 44; radius: 8; color: isDarkMode ? Qt.rgba(0,0,0,0.3) : Qt.rgba(0,0,0,0.02); border.color: mdCardBorder; border.width: 1 }
                                        }

                                        // 新增：跳转到设置的按钮
                                        Rectangle {
                                            width: 80; height: 44; radius: 8
                                            color: mdInputBg
                                            border.color: mdCardBorder; border.width: 1

                                            Rectangle {
                                                anchors.fill: parent; radius: parent.radius
                                                color: mdHover
                                                opacity: jumpMouse.containsMouse ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            }

                                            Text { 
                                                text: "修改";
                                                font.pixelSize: 12; 
                                                font.weight: Font.Medium; 
                                                anchors.centerIn: parent; z: 2
                                                color: mdTextPrimary 
                                            }

                                            MouseArea {
                                                id: jumpMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: {
                                                    root.activeIndex = 2; 
                                                }
                                            }
                                        }
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
                                            if (inputName.text.trim() === "") {
                                                inputNameBg.hasError = true;
                                                inputName.forceActiveFocus();
                                                return;
                                            }
                                            inputNameBg.hasError = false;
                                            var newId = "tag_" + new Date().getTime();
                                            var tagW = parseInt(inputW.text);
                                            var tagH = parseInt(inputH.text);
                                            var pos = root.findBestTagPosition(tagW, tagH);
                                            var jsonProps = {
                                                "id": newId, "tagTitle": inputName.text,
                                                "tagWidth": tagW, "tagHeight": tagH,
                                                "tagColor": inputColor.text,
                                                "savePath": inputPath.text, "allowedExts": inputExt.text
                                            };
                                            createTagComponent(function(comp) {
                                                var qmlProps = Object.assign({}, jsonProps);
                                                qmlProps.tagId = newId; delete qmlProps.id;
                                                qmlProps.startX = pos.x;
                                                qmlProps.startY = pos.y;
                                                // 直接以 null 作为父对象创建（因为一会儿要在 C++ 里给它找个"干爹"）
                                                var tag = comp.createObject(null, qmlProps);
                                                if (tag) {
                                                    root.activeTagWindows[newId] = tag;
                                                    tag.show();

                                                    // 关键：窗口显示出来后，立刻执行 C++ 注入，把它拍死在桌面上
                                                    appBackend.stickToDesktop(tag);

                                                    appBackend.saveNewTag(jsonProps);
                                                    var newTagFileCount = 0;
                                                    if (appBackend.getFilesInFolder) {
                                                        newTagFileCount = appBackend.getFilesInFolder(jsonProps.savePath).length;
                                                    }
                                                    activeTagsModel.append({ "tagId": newId, "title": jsonProps.tagTitle, "path": jsonProps.savePath, "tagColor": jsonProps.tagColor, "fileCount": newTagFileCount, "allowedExts": jsonProps.allowedExts });
                                                    tag.tagClosed.connect(createTagCloser());
                                                }
                                                console.log("🚀 新贴纸已生成！真实坐标 X:", tag.x, " Y:", tag.y, " 尺寸 W:", tag.width, " H:", tag.height, " 可见性:", tag.visible);
                                            });
                                        }
                                    }
                                }
                            }
                        }

                        // ----------------- Page 1: 管理贴纸 -----------------
                        Item {
                            anchors.fill: parent

                            // 全局点击任意空白处取消输入框焦点
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: mainContainer.forceActiveFocus()
                            }

                            // === 顶部标题与一键呼出按钮区 ===
                            Item {
                                id: topBarArea
                                x: 48; y: 48
                                width: parent.width - 96
                                height: 40

                                Text {
                                    id: manageTitle
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "管理活动贴纸"; font.pixelSize: 26; font.weight: Font.DemiBold; color: mdTextPrimary
                                }

                                // === 新增：一键呼出全部按钮 ===
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 140; height: 38; radius: 19
                                    color: showAllBtnMouse.pressed ? Qt.darker(currentThemeColor, 1.2) : currentThemeColor
                                    opacity: showAllBtnMouse.containsMouse ? 0.85 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Row {
                                        anchors.centerIn: parent; spacing: 8
                                        Text { text: ""; font.pixelSize: 16; color: currentThemeColorInv }
                                        Text { text: "Reveal All"; color: currentThemeColorInv; font.pixelSize: 14; font.weight: Font.Medium }
                                    }

                                    MouseArea {
                                        id: showAllBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            var screenW = Screen.desktopAvailableWidth > 0 ? Screen.desktopAvailableWidth : 1920;
                                            var screenH = Screen.desktopAvailableHeight > 0 ? Screen.desktopAvailableHeight : 1080;
                                            if (screenW > 3000) screenW = screenW / 2; // 规避多屏导致的超大分辨率

                                            // 遍历所有存活的贴纸窗口
                                            for (var key in root.activeTagWindows) {
                                                var win = root.activeTagWindows[key];
                                                if (win) {
                                                    // 1. 强制取消最小化、显示、提权置顶
                                                    win.showNormal();
                                                    win.visible = true;
                                                    win.raise();
                                                    win.requestActivate();

                                                    // 2. 越界抢救：如果贴纸飞出屏幕了，强行拽回来
                                                    var needsRescue = false;
                                                    var tX = win.x;
                                                    var tY = win.y;

                                                    if (tX + win.width > screenW) { tX = screenW - win.width - 20; needsRescue = true; }
                                                    if (tX < 0) { tX = 20; needsRescue = true; }
                                                    if (tY + win.height > screenH) { tY = screenH - win.height - 20; needsRescue = true; }
                                                    if (tY < 0) { tY = 20; needsRescue = true; }

                                                    if (needsRescue) {
                                                        win.x = tX;
                                                        win.y = tY;
                                                        if (appBackend.updateTagGeometry) {
                                                            appBackend.updateTagGeometry(key, tX, tY, win.width, win.height);
                                                        }
                                                        console.log("🛠️ 已执行越界救援，贴纸:", key, "新坐标:", tX, tY);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // === 贴纸网格列表 ===
                            GridView {
                                id: manageGrid
                                anchors.top: topBarArea.bottom; anchors.topMargin: 24
                                anchors.left: parent.left; anchors.leftMargin: 48
                                anchors.right: parent.right; anchors.rightMargin: 48
                                anchors.bottom: manageHint.top; anchors.bottomMargin: 12
                                cellWidth: 280; cellHeight: 180
                                model: activeTagsModel
                                clip: true

                                delegate: Rectangle {
                                    width: 260; height: 160; radius: 12;
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
                                        
                                        // 新增：规则显示和修改
                                        RowLayout {
                                            width: parent.width
                                            spacing: 8
                                            Text { text: "规则:"; color: mdTextSecondary; font.pixelSize: 13 }
                                            TextField {
                                                id: extField
                                                Layout.fillWidth: true
                                                text: model.allowedExts === "" ? "无" : model.allowedExts
                                                font.pixelSize: 12
                                                color: mdTextPrimary
                                                background: Rectangle { 
                                                    implicitHeight: 24; radius: 4; 
                                                    color: parent.activeFocus ? mdInputBg : "transparent"
                                                    border.color: parent.activeFocus ? currentThemeColor : isDarkMode ? Qt.rgba(1,1,1,0.1) : Qt.rgba(0,0,0,0.1)
                                                }
                                                onEditingFinished: {
                                                    model.allowedExts = text;
                                                    if (appBackend.updateTagRules) {
                                                        appBackend.updateTagRules(model.tagId, text);
                                                    }
                                                    // 如果对应的贴纸窗口开着，也同步更新属性
                                                    if (root.activeTagWindows[model.tagId]) {
                                                        root.activeTagWindows[model.tagId].allowedExts = text;
                                                    }
                                                }
                                            }

                                            // 确认修改按钮（带圆圈和勾）
                                            Rectangle {
                                                id: checkBtn
                                                Layout.preferredWidth: 20
                                                Layout.preferredHeight: 20
                                                radius: 10
                                                color: extField.activeFocus ? (checkMouse.containsMouse ? currentThemeColor : "transparent") : "transparent"
                                                border.color: extField.activeFocus ? currentThemeColor : "transparent"
                                                border.width: 1
                                                opacity: extField.activeFocus ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    font.pixelSize: 12
                                                    font.weight: Font.Bold
                                                    color: checkMouse.containsMouse ? currentThemeColorInv : currentThemeColor
                                                }

                                                MouseArea {
                                                    id: checkMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onClicked: {
                                                        mainContainer.forceActiveFocus() // 取消焦点自动触发上面的 onEditingFinished 保存
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // 删除按钮
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
                                        onClicked: mainContainer.forceActiveFocus() // 卡片内空白处点击也取消焦点
                                    }
                                }
                            }

                            // === 使用提示 ===
                            Rectangle {
                                id: manageHint
                                anchors.left: parent.left; anchors.leftMargin: 48
                                anchors.right: parent.right; anchors.rightMargin: 48
                                anchors.bottom: parent.bottom
                                height: 40
                                color: "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8
                                    Text {
                                        text: ""
                                        font.pixelSize: 16
                                    }
                                    Text {
                                        text: "提示：鼠标悬停到贴纸卡片右上角可显示 ✕ 按钮，点击即可删除该贴纸"
                                        color: mdTextSecondary
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                        verticalAlignment: Text.AlignVCenter
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
                                    Layout.fillWidth: true; Layout.preferredHeight: 160; radius: 12
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
                                                }
                                                Rectangle {
                                                    id: browseBtn
                                                    implicitWidth: 80; implicitHeight: 40; radius: 8
                                                    color: "transparent"
                                                    border.color: mdCardBorder; border.width: 1

                                                    Rectangle {
                                                        anchors.fill: parent; radius: parent.radius
                                                        color: mdHover
                                                        opacity: browseMouse.containsMouse ? 1.0 : 0.0
                                                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "浏览..."; color: mdTextPrimary
                                                        font.pixelSize: 14; font.weight: Font.Medium
                                                    }
                                                    MouseArea {
                                                        id: browseMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: folderDialog.open()
                                                    }
                                                }
                                                Rectangle {
                                                    id: applyBtn
                                                    implicitWidth: 80; implicitHeight: 40; radius: 8
                                                    color: currentThemeColor
                                                    property bool pressed: false
                                                    property bool hovered: false
                                                    Rectangle {
                                                        anchors.fill: parent; radius: parent.radius
                                                        color: applyBtn.pressed ? "black" : "white"
                                                        opacity: applyBtn.pressed ? 0.20 : (applyBtn.hovered ? 0.18 : 0.0)
                                                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "应用"; color: currentThemeColorInv
                                                        font.pixelSize: 14; font.weight: Font.Medium
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onEntered: applyBtn.hovered = true
                                                        onExited: applyBtn.hovered = false
                                                        onPressed: applyBtn.pressed = true
                                                        onReleased: applyBtn.pressed = false
                                                        onClicked: { root.globalRootPath = rootDirInput.text; appBackend.setRootPath(rootDirInput.text); }
                                                    }
                                                }
                                            }

                                            FolderDialog {
                                                id: folderDialog
                                                currentFolder: "file:///" + rootDirInput.text.replace("\\", "/")
                                                onAccepted: {
                                                    var chosenPath = selectedFolder.toString();
                                                    // 去掉 "file:///" 前缀
                                                    if (chosenPath.startsWith("file:///")) {
                                                        chosenPath = chosenPath.substring(8);
                                                    } else if (chosenPath.startsWith("file://")) {
                                                        chosenPath = chosenPath.substring(7);
                                                    }
                                                    // 确保是 Windows 路径格式 (D:/xxx)
                                                    chosenPath = chosenPath.replace("/", "/");
                                                    rootDirInput.text = chosenPath;
                                                    root.globalRootPath = chosenPath;
                                                    appBackend.setRootPath(chosenPath);
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
                                anchors.centerIn: parent; spacing: 20 // 增加间距

                                // 1. 应用大图标
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter; width: 80; height: 80; radius: 24
                                    color: mdInputBg
                                    border.color: mdCardBorder; border.width: 1
                                    Text { text: "❖"; font.pixelSize: 40; color: mdTextPrimary; anchors.centerIn: parent }
                                }

                                // 2. 项目标题与版本
                                ColumnLayout {
                                    spacing: 4; Layout.alignment: Qt.AlignHCenter
                                    Text { text: "Desktop Organizer"; color: mdTextPrimary; font.pixelSize: 24; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: "Version 1.0.0"; color: mdTextSecondary; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter }
                                }

                                // 3. GitHub 链接按钮 (新增)
                                Rectangle {
                                    id: githubBtn
                                    Layout.alignment: Qt.AlignHCenter; width: 160; height: 44; radius: 22
                                    color: "transparent"
                                    border.color: mdCardBorder; border.width: 1

                                    Rectangle {
                                        anchors.fill: parent; radius: parent.radius
                                        color: isDarkMode ? "#333" : "#f5f5f5"
                                        opacity: gitMouse.containsMouse ? 1.0 : 0.0
                                        z: 1
                                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    }

                                    Row {
                                        anchors.centerIn: parent; spacing: 10; z: 2
                                        Item {
                                            width: 20; height: 20
                                            Canvas {
                                                anchors.fill: parent
                                                onPaint: {
                                                    var ctx = getContext("2d");
                                                    ctx.fillStyle = mdTextPrimary;
                                                    ctx.beginPath();
                                                    ctx.arc(10, 10, 9, 0, Math.PI * 2, true);
                                                    ctx.fill();
                                                    ctx.fillStyle = mdInputBg;
                                                    ctx.beginPath();
                                                    ctx.arc(10, 10, 6, 0, Math.PI * 2, true);
                                                    ctx.fill();
                                                }
                                            }
                                        }
                                        Text {
                                            text: "View on GitHub"; font.pixelSize: 14; font.weight: Font.Medium; color: mdTextPrimary
                                        }
                                    }

                                    MouseArea {
                                        id: gitMouse; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Qt.openUrlExternally("https://github.com/kuangkeming2006-max/Desktop_Organizer")
                                        }
                                    }
                                }

                                Text { text: "迭戈"; color: mdTextSecondary; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 20 }
                            }
                        }
                    }
                }
            }
        }
    }
}
