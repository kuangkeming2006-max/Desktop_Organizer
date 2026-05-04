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

    // --- 璋冩暣鍚庣殑浜氬厠鍔?姣涚幓鐠冭川鎰熻壊鏉?---
    readonly property color mdSurfaceBg: Qt.rgba(0.96, 0.97, 0.98, 0.92)
    readonly property color mdCardBg: Qt.rgba(1.0, 1.0, 1.0, 0.85)
    readonly property color mdCardBorder: Qt.rgba(1.0, 1.0, 1.0, 0.9)
    readonly property color mdTextPrimary: "#1a1a1c"
    readonly property color mdTextSecondary: "#5f6368"
    readonly property color mdHover: Qt.rgba(0.0, 0.0, 0.0, 0.05)
    readonly property color mdInputBg: Qt.rgba(1.0, 1.0, 1.0, 0.6)

    readonly property int menuHeight: 48
    readonly property int menuSpacing: 10

    property color currentThemeColor: sidebarModel.get(activeIndex).colorCode

    ListModel {
        id: sidebarModel
        ListElement { name: "娣诲姞鏍囩"; icon: "鉂?; colorCode: "#0b57d0" }
        ListElement { name: "绠＄悊璐寸焊"; icon: "鈼?; colorCode: "#9333ea" }
        ListElement { name: "璁剧疆涓績"; icon: "鉀?; colorCode: "#e37400" }
        ListElement { name: "鍏充簬椤圭洰"; icon: "鈸?; colorCode: "#188038" }
    }

    ListModel {
        id: activeTagsModel
    }

    Component.onCompleted: {
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
                    // 杞崲灞炴€у悕閬垮紑淇濈暀瀛?
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
        anchors.margins: 20 // 鍔犲ぇ杈硅窛鐣欑粰鏇村ぇ鐨勯槾褰?
        radius: 12
        color: "transparent"

        // 涓昏儗鏅甫涓€瀹氶€忔槑搴?(澧為€忎互绐佹樉姣涚幓鐠冭川鎰?
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.98, 0.98, 0.99, 0.65) }
                GradientStop { position: 1.0; color: Qt.rgba(0.94, 0.95, 0.97, 0.55) }
            }
        }

        // 椤跺眰/宸︿晶 浜壊楂樹寒杈规 (妯℃嫙 3D 鍑歌捣锛屽寮鸿竟缂樺弽鍏?
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.9)
        }

        // 搴曞眰/鍙充晶 鏆楄壊鍔犳繁杈规 (澧炲己绔嬩綋鎰?
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.leftMargin: 1
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0.0, 0.0, 0.0, 0.25)
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.35)
            shadowBlur: 32.0 // 鍔犲ぇ闃村奖妯＄硦鍗婂緞
            shadowVerticalOffset: 12 // 澧炲姞鍨傜洿鍋忕Щ
            shadowHorizontalOffset: 0
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ==================== 1. 鏍囬鏍忓尯鍩?====================
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
                            MouseArea { anchors.fill: parent; onClicked: root.close() }
                        }
                        Rectangle {
                            width: 14; height: 14; radius: 7; color: "#ffbd2e"
                            border.color: Qt.rgba(0,0,0,0.1); border.width: 0.5
                            MouseArea { anchors.fill: parent; onClicked: root.showMinimized() }
                        }
                        Rectangle {
                            width: 14; height: 14; radius: 7; color: "#27c93f"
                            border.color: Qt.rgba(0,0,0,0.1); border.width: 0.5
                            MouseArea { anchors.fill: parent; onClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized() }
                        }
                    }

                    Text {
                        text: "Desktop Organizer"
                        color: mdTextSecondary
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        font.letterSpacing: 0.5
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

                // ==================== 2. 宸︿晶瀵艰埅鑿滃崟 ====================
                Item {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 220

                    Rectangle {
                        id: capsuleBg
                        x: 0; width: parent.width; height: menuHeight; radius: menuHeight / 2
                        color: Qt.rgba(currentThemeColor.r, currentThemeColor.g, currentThemeColor.b, 0.15)
                        border.color: Qt.rgba(currentThemeColor.r, currentThemeColor.g, currentThemeColor.b, 0.25)
                        border.width: 1
                        y: 10 + root.activeIndex * (menuHeight + menuSpacing)
                        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
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
                }

                // ==================== 3. 涓诲唴瀹瑰尯鍗＄墖 ====================
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 16
                    border.color: mdCardBorder; border.width: 1

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1.0, 1.0, 1.0, 0.95) }
                        GradientStop { position: 1.0; color: mdCardBg }
                    }

                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0,0,0,0.05); shadowBlur: 2.0; shadowVerticalOffset: 2 }

                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.activeIndex

                        // ----------------- Page 0: 娣诲姞鏍囩 -----------------
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 48; spacing: 24

                                ColumnLayout {
                                    spacing: 8
                                    Text { text: "閰嶇疆鏂版爣绛?; font.pixelSize: 26; font.weight: Font.DemiBold; color: mdTextPrimary }
                                    Text { text: "鍒涘缓涓€涓甫鏈夎嚜瀹氫箟瑙勫垯鐨勬闈㈡敹绾冲尯銆?; font.pixelSize: 14; color: mdTextSecondary }
                                }

                                GridLayout {
                                    columns: 2; rowSpacing: 20; columnSpacing: 24; Layout.fillWidth: true; Layout.topMargin: 10

                                    Text { text: "璐寸焊鍚嶇О"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputName
                                        Layout.fillWidth: true; font.pixelSize: 14; color: mdTextPrimary; placeholderText: "渚嬪锛歅DF 鏀剁撼鍖?
                                        verticalAlignment: TextInput.AlignVCenter   // 鏂板鍨傜洿灞呬腑
                                        leftPadding: 16                             // 鏂板宸︿晶鍛煎惛鎰熼棿璺?
                                        rightPadding: 16                            // 鏂板鍙充晶闂磋窛
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: parent.activeFocus ? "#ffffff" : mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1; Behavior on border.color { ColorAnimation { duration: 200 } } Behavior on color { ColorAnimation { duration: 200 } } }
                                    }

                                    Text { text: "灏哄 (瀹絰楂?"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    RowLayout {
                                        spacing: 12
                                        TextField {
                                            id: inputW
                                            Layout.preferredWidth: 100; text: "220"; font.pixelSize: 14; color: mdTextPrimary; horizontalAlignment: TextInput.AlignHCenter
                                            verticalAlignment: TextInput.AlignVCenter   // 鏂板鍨傜洿灞呬腑
                                            background: Rectangle { implicitHeight: 44; radius: 8; color: parent.activeFocus ? "#ffffff" : mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                        }
                                        Text { text: "脳"; color: mdTextSecondary; font.pixelSize: 16 }
                                        TextField {
                                            id: inputH
                                            Layout.preferredWidth: 100; text: "280"; font.pixelSize: 14; color: mdTextPrimary; horizontalAlignment: TextInput.AlignHCenter
                                            verticalAlignment: TextInput.AlignVCenter   // 鏂板鍨傜洿灞呬腑
                                            background: Rectangle { implicitHeight: 44; radius: 8; color: parent.activeFocus ? "#ffffff" : mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                        }
                                    }

                                    Text { text: "涓婚棰滆壊"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputColor
                                        Layout.fillWidth: true; text: "#0b57d0"; placeholderText: "Hex 浠ｇ爜濡?#ea4335"; font.pixelSize: 14; color: mdTextPrimary
                                        verticalAlignment: TextInput.AlignVCenter   // 鏂板鍨傜洿灞呬腑
                                        leftPadding: 16
                                        rightPadding: 16
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: parent.activeFocus ? "#ffffff" : mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                    }

                                    Text { text: "鏄犲皠鍦板潃"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputPath
                                        Layout.fillWidth: true; readOnly: true; color: mdTextSecondary; font.pixelSize: 14
                                        text: root.globalRootPath + "/" + (inputName.text.trim() === "" ? "鏂拌创绾? : inputName.text.trim())
                                        verticalAlignment: TextInput.AlignVCenter   // 鏂板鍨傜洿灞呬腑
                                        leftPadding: 16
                                        rightPadding: 16
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: Qt.rgba(0,0,0,0.04); border.color: mdCardBorder; border.width: 1 }
                                    }

                                    Text { text: "闄愬埗鍚庣紑"; color: mdTextPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    TextField {
                                        id: inputExt
                                        Layout.fillWidth: true; text: "*.pdf, *.docx"; placeholderText: "澶氬悗缂€閫楀彿鍒嗛殧"; font.pixelSize: 14; color: mdTextPrimary
                                        verticalAlignment: TextInput.AlignVCenter   // 鏂板鍨傜洿灞呬腑
                                        leftPadding: 16
                                        rightPadding: 16
                                        background: Rectangle { implicitHeight: 44; radius: 8; color: parent.activeFocus ? "#ffffff" : mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: parent.activeFocus ? 2 : 1 }
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                Rectangle {
                                    Layout.alignment: Qt.AlignRight; width: 140; height: 44; radius: 8
                                    color: btnMouse.pressed ? Qt.darker(currentThemeColor, 1.1) : currentThemeColor
                                    opacity: btnMouse.containsMouse ? 0.9 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Text { text: "鐢熸垚璐寸焊"; color: "white"; font.pixelSize: 15; font.weight: Font.Medium; anchors.centerIn: parent }

                                    MouseArea {
                                        id: btnMouse; anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                                var comp = Qt.createComponent("DesktopTag.qml");
                                                if (comp.status === Component.Ready) {
                                                    var newId = "tag_" + new Date().getTime();

                                                    // 浼犵粰 C++ 鐨勫師濮嬫暟鎹紙JSON 璁?id锛?
                                                    var jsonProps = {
                                                        "id": newId,
                                                        "tagTitle": inputName.text,
                                                        "tagWidth": parseInt(inputW.text),
                                                        "tagHeight": parseInt(inputH.text),
                                                        "tagColor": inputColor.text,
                                                        "savePath": inputPath.text,
                                                        "allowedExts": inputExt.text
                                                    };

                                                    // 浼犵粰 QML 鐨勫睘鎬э紙璁?tagId锛?
                                                    var qmlProps = Object.assign({}, jsonProps);
                                                    qmlProps.tagId = newId;
                                                    delete qmlProps.id;

                                                    var tag = comp.createObject(null, qmlProps);
                                                                if (tag) {
                                                                    // 銆愭柊澧炪€戯細鎶婂垰鐢熸垚鐨勭獥鍙ｅ瓨杩涘瓧鍏?
                                                                    root.activeTagWindows[newId] = tag;

                                                                    appBackend.saveNewTag(jsonProps);
                                                                    activeTagsModel.append({
                                                                        "tagId": newId, "title": jsonProps.tagTitle, "path": jsonProps.savePath, "tagColor": jsonProps.tagColor, "fileCount": 0
                                                                    });
                                                                    root.requestActivate();
                                                                    root.raise();
                                                                }
                                                }


                                            }
                                    }
                                }
                            }
                        }

                        // ----------------- Page 1: 绠＄悊璐寸焊 -----------------
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 48; spacing: 24
                                Text { text: "绠＄悊娲诲姩璐寸焊"; font.pixelSize: 26; font.weight: Font.DemiBold; color: mdTextPrimary }

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
                                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0,0,0,0.06); shadowBlur: 2.0; shadowVerticalOffset: 3 }

                                        Column {
                                            anchors.fill: parent; anchors.margins: 20; spacing: 8
                                            RowLayout {
                                                width: parent.width; spacing: 10
                                                Rectangle { width: 14; height: 14; radius: 7; color: model.tagColor }
                                                Text { text: model.title; font.weight: Font.DemiBold; color: mdTextPrimary; font.pixelSize: 16; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }
                                            Text { text: "鏄犲皠: " + model.path; color: mdTextSecondary; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
                                            Text { text: "褰撳墠鏀剁撼: " + model.fileCount + " 涓枃浠?; color: mdTextSecondary; font.pixelSize: 13 }
                                        }

                                        Rectangle {
                                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12
                                            width: 28; height: 28; radius: 14; color: "#fce8e6"
                                            opacity: delMouse.containsMouse ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }

                                            Text { text: "鉁?; color: "#ea4335"; font.pixelSize: 14; font.weight: Font.DemiBold; anchors.centerIn: parent }
                                            MouseArea {
                                                        id: delMouse; anchors.fill: parent; hoverEnabled: true;
                                                        onClicked: {
                                                            var targetId = model.tagId;
                                                            appBackend.removeTagAndRestore(targetId, model.path);

                                                            if (root.activeTagWindows[targetId]) {
                                                                root.activeTagWindows[targetId].destroy();
                                                                // 褰诲簳鍒犻櫎寮曠敤锛岄槻姝㈠唴瀛樻硠婕?
                                                                var updatedWindows = root.activeTagWindows;
                                                                delete updatedWindows[targetId];
                                                                root.activeTagWindows = updatedWindows;
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

                        // ----------------- Page 2: 璁剧疆涓績 -----------------
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 48; spacing: 24
                                Text { text: "绯荤粺鍋忓ソ璁剧疆"; font.pixelSize: 26; font.weight: Font.DemiBold; color: mdTextPrimary }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: 120; radius: 12
                                    color: mdInputBg; border.color: mdCardBorder; border.width: 1
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 24
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Text { text: "榛樿鏀剁撼鏍圭洰褰?; font.pixelSize: 16; font.weight: Font.DemiBold; color: mdTextPrimary }
                                            Text { text: "鏂板缓璐寸焊鏃讹紝灏嗗湪姝ょ洰褰曚笅鑷姩寤虹珛鍚屽悕鏂囦欢澶瑰瓨鏀炬嫋鍏ョ殑鏂囦欢銆?; font.pixelSize: 13; color: mdTextSecondary }

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 16; Layout.topMargin: 8
                                                TextField {
                                                    id: rootDirInput
                                                    Layout.fillWidth: true; font.pixelSize: 14; color: mdTextPrimary
                                                    text: root.globalRootPath
                                                    verticalAlignment: TextInput.AlignVCenter   // 鏂板鍨傜洿灞呬腑
                                                    leftPadding: 16                             // 鏂板宸︿晶闂磋窛
                                                    rightPadding: 16
                                                    background: Rectangle { implicitHeight: 40; radius: 8; color: parent.activeFocus ? "#ffffff" : mdInputBg; border.color: parent.activeFocus ? currentThemeColor : mdCardBorder; border.width: 1 }
                                                    onEditingFinished: { root.globalRootPath = text; appBackend.setRootPath(text); }
                                                }
                                                Button {
                                                    text: "搴旂敤"
                                                    background: Rectangle { implicitWidth: 80; implicitHeight: 40; radius: 8; color: currentThemeColor; opacity: parent.hovered ? 0.9 : 1.0 }
                                                    contentItem: Text { text: "搴旂敤"; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 14; font.weight: Font.Medium }
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
                                            Text { text: "寮€鏈鸿嚜鍔ㄥ惎鍔?; font.pixelSize: 16; font.weight: Font.DemiBold; color: mdTextPrimary }
                                            Text { text: "鐧诲綍 Windows 鍚庤嚜鍔ㄦ仮澶嶆墍鏈夋闈㈣创绾?; font.pixelSize: 13; color: mdTextSecondary }
                                        }
                                        Switch {
                                            id: bootSwitch; checked: true
                                            indicator: Rectangle {
                                                implicitWidth: 44; implicitHeight: 24; radius: 12
                                                color: bootSwitch.checked ? currentThemeColor : Qt.rgba(0,0,0,0.1)
                                                border.color: bootSwitch.checked ? currentThemeColor : Qt.rgba(0,0,0,0.2)
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                Rectangle {
                                                    x: bootSwitch.checked ? parent.width - width - 2 : 2; y: 2; width: 20; height: 20; radius: 10; color: "white"
                                                    layer.enabled: true; layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 2.0; shadowColor: Qt.rgba(0,0,0,0.2) }
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

                        // ----------------- Page 3: 鍏充簬 -----------------
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 12

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter; width: 72; height: 72; radius: 24
                                    color: Qt.rgba(currentThemeColor.r, currentThemeColor.g, currentThemeColor.b, 0.15)
                                    border.color: Qt.rgba(currentThemeColor.r, currentThemeColor.g, currentThemeColor.b, 0.4); border.width: 1
                                    Text { text: "鉂?; font.pixelSize: 36; color: currentThemeColor; anchors.centerIn: parent }
                                }

                                Text { text: "Desktop Tool v0.7.1"; color: mdTextPrimary; font.pixelSize: 22; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 10 }
                                Text { text: "Ke Ming @ SYSU Cybersecurity"; color: mdTextSecondary; font.pixelSize: 15; font.weight: Font.Medium; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                    }
                }
            }
        }
    }
}
