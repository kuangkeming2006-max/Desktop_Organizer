#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QSettings>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QDebug>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QVariantMap>
#include <QVariantList>
#include <QWindow>
#include <QQuickWindow>
#include <QAbstractNativeEventFilter>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QAction>
#include <QPointer>
#include <QPixmap>
#include <QSet>
#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "user32.lib")

// 原生視窗事件過濾器：
// - 使用 QSet<HWND> 白名單管理受影響的視窗
// - 攔截 WM_NCCALCSIZE → 非客戶區設為 0（無透明框、標題欄、邊框）
// - 保留 WS_CAPTION | WS_THICKFRAME 樣式以觸發 DWM 原生動畫
class WinEventFilter : public QAbstractNativeEventFilter {
public:
    static WinEventFilter* instance() { return s_instance; }

    WinEventFilter() { s_instance = this; }

    // 【新增】：將窗口加入無邊框白名單
    void addWindow(HWND h) {
        if (h) {
            m_hwnds.insert(h);
        }
    }

    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override {
        if (eventType == "windows_generic_MSG") {
            MSG *msg = static_cast<MSG *>(message);

            // 【核心防線】：如果當前觸發消息的窗口不在我們的白名單裡，直接放行！
            // 這可以保護你的右鍵菜單、Tooltip 等標準 Qt 控件不被破壞渲染。
            if (!m_hwnds.contains(msg->hwnd)) {
                return false;
            }

            switch (msg->message) {
            case WM_NCCALCSIZE: {
                if (msg->wParam == TRUE) {
                    NCCALCSIZE_PARAMS *ncp = reinterpret_cast<NCCALCSIZE_PARAMS *>(msg->lParam);
                    ncp->rgrc[0] = ncp->rgrc[1];
                    if (result) *result = 0;
                    return true;
                }
                return false;
            }
            case WM_NCACTIVATE: {
                if (result) *result = TRUE;
                return true;
            }
            // 限制最大化時不要遮擋任務欄，且修正邊緣溢出
            case WM_GETMINMAXINFO: {
                MINMAXINFO *mmi = reinterpret_cast<MINMAXINFO *>(msg->lParam);
                HMONITOR monitor = MonitorFromWindow(msg->hwnd, MONITOR_DEFAULTTONEAREST);
                MONITORINFO mi;
                mi.cbSize = sizeof(MONITORINFO);
                GetMonitorInfo(monitor, &mi);
                mmi->ptMaxSize.x = mi.rcWork.right - mi.rcWork.left;
                mmi->ptMaxSize.y = mi.rcWork.bottom - mi.rcWork.top;
                mmi->ptMaxPosition.x = mi.rcWork.left - mi.rcMonitor.left;
                mmi->ptMaxPosition.y = mi.rcWork.top - mi.rcMonitor.top;
                if (result) *result = 0;
                return true;
            }
            case WM_SHOWWINDOW: {
                if (msg->wParam == TRUE) {
                    // 【修正】：使用當前獨立觸發事件的 msg->hwnd，而不是被覆蓋的 m_hwnd
                    SetWindowPos(msg->hwnd, nullptr, 0, 0, 0, 0,
                                 SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER);
                }
                return false;
            }
            case WM_NCDESTROY: {
                // 【亮點功能：自動 GC】：當窗口（比如貼紙）被徹底銷毀時，
                // Windows 會發送 WM_NCDESTROY。我們在此處將其移出白名單，防止內存洩漏和野指針。
                m_hwnds.remove(msg->hwnd);
                return false;
            }
            }
        }
        return false;
    }
private:
    QSet<HWND> m_hwnds; // 使用 QSet 存儲所有白名單窗口句柄
    static WinEventFilter* s_instance;
};
WinEventFilter* WinEventFilter::s_instance = nullptr;
#endif



class AppBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool trayAvailable READ isTrayAvailable CONSTANT)
private:
    QJsonObject m_config;
    QSystemTrayIcon *m_trayIcon = nullptr;
    QPointer<QQuickWindow> m_mainWindow;

    bool isTrayAvailable() const { return m_trayIcon != nullptr; }

    // 获取配置文件的绝对路径 (C:\Users\用户名\AppData\Roaming\SYSU_DesktopOrganizer\config.json)
    QString getConfigPath() {
        QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        QDir dir(dataDir);
        if (!dir.exists()) dir.mkpath(".");
        return dir.absoluteFilePath("config.json");
    }

    // 将内存中的 JSON 写入硬盘
    void saveConfig() {
        QFile file(getConfigPath());
        if (file.open(QIODevice::WriteOnly)) {
            QJsonDocument doc(m_config);
            file.write(doc.toJson());
            file.close();
        }
    }

    // 从硬盘加载 JSON
    void loadConfig() {
        QFile file(getConfigPath());
        if (file.exists() && file.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
            m_config = doc.object();
        } else {
            // 初始化默认结构
            m_config["settings"] = QJsonObject();
            m_config["tags"] = QJsonArray();
            m_config["fileLedger"] = QJsonObject();
        }
    }

public:
    // ==================== 终极桌面注入 ====================
    Q_INVOKABLE void stickToDesktop(QQuickWindow* window) {
        if (!window) return;
        HWND hwnd = reinterpret_cast<HWND>(window->winId());

        // 1. 找到桌面大管家 Progman
        HWND progman = FindWindowW(L"Progman", nullptr);

        // 2. 发送未公开的系统玄学消息 0x052C
        // 这个消息会逼迫 Windows DWM 从 Progman 中分裂出一个纯净的底层壁纸层 (WorkerW)
        DWORD_PTR result = 0;
        SendMessageTimeoutW(progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, &result);

        // 3. 遍历所有顶层窗口，把刚刚被分离出来的那个壁纸层揪出来
        static HWND workerW = nullptr;
        EnumWindows([](HWND topHandle, LPARAM topParamHandle) -> BOOL {
            // 寻找包含桌面图标的图层 SHELLDLL_DefView
            HWND p = FindWindowExW(topHandle, nullptr, L"SHELLDLL_DefView", nullptr);
            if (p != nullptr) {
                // 桌面图标层的同级下一个 WorkerW，就是我们真正需要的干净壁纸层
                workerW = FindWindowExW(nullptr, topHandle, L"WorkerW", nullptr);
            }
            return TRUE;
        }, 0);

        // 4. 终极注入：把我们的 QML 贴纸强行认贼作父，变成桌面的子窗口
        if (workerW) {
            SetParent(hwnd, workerW);
            qDebug() << "成功注入到 WorkerW 壁纸层！";
        } else if (progman) {
            SetParent(hwnd, progman); // 降级备用方案
            qDebug() << "降级注入到 Progman！";
        }
    }

    // ==================== 调用 Windows 原生最大化/还原 ====================
    Q_INVOKABLE void toggleMaximizeNative(QQuickWindow* window) {
        if (!window) return;
        HWND hwnd = reinterpret_cast<HWND>(window->winId());

        // 获取当前窗口的原生状态
        WINDOWPLACEMENT wp;
        wp.length = sizeof(WINDOWPLACEMENT);
        if (GetWindowPlacement(hwnd, &wp)) {
            // 如果已经是最大化状态，则原生还原
            if (wp.showCmd == SW_SHOWMAXIMIZED) {
                ShowWindow(hwnd, SW_RESTORE);
            } else {
                // 否则，原生最大化
                ShowWindow(hwnd, SW_MAXIMIZE);
            }
        }
    }

    // 確保原生視窗樣式完整，觸發 DWM 重新讀取
    Q_INVOKABLE void initNativeWindow(QQuickWindow* window) {
        if (!window) return;
        HWND hwnd = reinterpret_cast<HWND>(window->winId());

#ifdef Q_OS_WIN
        // 將 HWND 註冊到原生事件過濾器（用於 WM_SHOWWINDOW 刷新）
        if (WinEventFilter::instance())
            WinEventFilter::instance()->addWindow(hwnd);

        // ==========================================
        // 【关键修复】：补回被 Qt.FramelessWindowHint 强制剥夺的原生窗口样式
        // 加上这些样式，Windows DWM 才会接管动画和窗口状态管理
        // ==========================================
        LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
        style |= WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
        SetWindowLongPtr(hwnd, GWL_STYLE, style);

        // 啟用持久場景圖與圖形資源：最小化/隱藏後不會釋放渲染緩衝，避免還原後變透明
        window->setPersistentSceneGraph(true);
        window->setPersistentGraphics(true);
#endif

        // 觸發 DWM 重新計算非客戶區（WM_NCCALCSIZE 將消除它）
        SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER);

        // 關鍵修復：強制 Qt 提交新一幀渲染，填補透明區域
        window->update();
    }

    Q_INVOKABLE QString getRootPath() {
        QJsonObject settings = m_config["settings"].toObject();
        return settings.contains("rootPath") ? settings["rootPath"].toString() : "D:/Stickers";
    }

    // 设置并保存全局根目录
    Q_INVOKABLE void setRootPath(const QString &path) {
        QJsonObject settings = m_config["settings"].toObject();
        settings["rootPath"] = path;
        m_config["settings"] = settings;
        saveConfig(); // 落盘
        qDebug() << "Global root path updated to:" << path;
    }
    explicit AppBackend(QObject *parent = nullptr) : QObject(parent) {
        loadConfig(); // 启动时加载配置
    }

    // ==================== 暴露给 QML 的接口 ====================

    // 1. 开机自启 (保持不变)
    Q_INVOKABLE void setAutoStart(bool enable) { /* ... 之前的代码 ... */ }

    // 2. 获取所有已保存的贴纸 (用于开机恢复)
    Q_INVOKABLE QVariantList getSavedTags() {
        return m_config["tags"].toArray().toVariantList();
    }

    // 3. 保存新生成的贴纸信息
    Q_INVOKABLE void saveNewTag(const QVariantMap& tagInfo) {
        QJsonArray tags = m_config["tags"].toArray();
        tags.append(QJsonObject::fromVariantMap(tagInfo));
        m_config["tags"] = tags;
        saveConfig();
    }

    // 4. 将文件移入贴纸，并在 Ledger 中记账！
    Q_INVOKABLE bool moveFileToTag(const QString &fileUrl, const QString &destFolder) {
        QUrl url(fileUrl);
        if (!url.isLocalFile()) return false;

        QString sourcePath = url.toLocalFile();
        QFileInfo fileInfo(sourcePath);

        QDir dir(destFolder);
        if (!dir.exists()) dir.mkpath(".");

        QString destPath = dir.absoluteFilePath(fileInfo.fileName());

        if (QFile::rename(sourcePath, destPath)) {
            // 【核心记账逻辑】：记录 目标物理路径 -> 原始桌面路径
            QJsonObject ledger = m_config["fileLedger"].toObject();
            ledger[destPath] = sourcePath;
            m_config["fileLedger"] = ledger;
            saveConfig();

            qDebug() << "File moved & logged:" << destPath;
            return true;
        }
        return false;
    }

    // 5. 销毁贴纸并根据 Ledger 逆向复原文件
    Q_INVOKABLE void removeTagAndRestore(const QString &tagId, const QString &tagFolder) {
        QJsonObject ledger = m_config["fileLedger"].toObject();
        QStringList keysToRemove;

        // 遍历账本，把属于这个贴纸目录下的文件全部移回去
        for (auto it = ledger.begin(); it != ledger.end(); ++it) {
            QString currentPath = it.key();
            QString originalPath = it.value().toString();

            if (currentPath.startsWith(tagFolder)) {
                if (QFile::rename(currentPath, originalPath)) {
                    qDebug() << "Restored:" << originalPath;
                    keysToRemove.append(currentPath);
                }
            }
        }

        // 从账本中抹去记录
        for (const QString& k : keysToRemove) {
            ledger.remove(k);
        }
        m_config["fileLedger"] = ledger;

        // 从贴纸数组中删除记录
        QJsonArray tags = m_config["tags"].toArray();
        for (int i = 0; i < tags.size(); ++i) {
            if (tags[i].toObject()["id"].toString() == tagId) {
                tags.removeAt(i);
                break;
            }
        }
        m_config["tags"] = tags;

        saveConfig(); // 最终落盘
        qDebug() << "Tag" << tagId << "removed and files restored.";
    }

    // 6. 更新贴纸位置和尺寸（每次拖拽/調整後保存）
    Q_INVOKABLE void updateTagGeometry(const QString &tagId, int x, int y, int w, int h) {
        QJsonArray tags = m_config["tags"].toArray();
        for (int i = 0; i < tags.size(); ++i) {
            QJsonObject obj = tags[i].toObject();
            if (obj["id"].toString() == tagId) {
                obj["x"] = x;
                obj["y"] = y;
                obj["tagWidth"] = w;
                obj["tagHeight"] = h;
                tags[i] = obj;
                break;
            }
        }
        m_config["tags"] = tags;
        saveConfig();
    }

    // 7. 修改贴纸名称
    Q_INVOKABLE void renameTag(const QString &tagId, const QString &newTitle) {
        QJsonArray tags = m_config["tags"].toArray();
        for (int i = 0; i < tags.size(); ++i) {
            QJsonObject obj = tags[i].toObject();
            if (obj["id"].toString() == tagId) {
                obj["tagTitle"] = newTitle;
                tags[i] = obj;
                break;
            }
        }
        m_config["tags"] = tags;
        saveConfig();
    }

    // ==================== 系統托盤 ====================

    // 初始化系統托盤（由 QML 在 Component.onCompleted 中呼叫）
    Q_INVOKABLE void initSystemTray(QQuickWindow *window) {
        m_mainWindow = window;

        if (!QSystemTrayIcon::isSystemTrayAvailable()) {
            qDebug() << "System tray not available on this system.";
            return;
        }

        m_trayIcon = new QSystemTrayIcon(this);

        // 使用應用程式圖示，若無則建立一個簡單的色塊圖示
        QIcon appIcon = QIcon(":/sticker.ico");
        if (appIcon.isNull()) {
            QPixmap pm(32, 32);
            pm.fill(Qt::darkGray);
            appIcon = QIcon(pm);
        }
        m_trayIcon->setIcon(appIcon);
        m_trayIcon->setToolTip("Desktop Organizer");

        // 右鍵選單
        QMenu *menu = new QMenu();
        QAction *showAction = menu->addAction("顯示主視窗");
        QAction *quitAction = menu->addAction("退出程式");

        // addAction() 和 setContextMenu() 已處理所有權
        m_trayIcon->setContextMenu(menu);

        // 左鍵點擊還原
        QObject::connect(m_trayIcon, &QSystemTrayIcon::activated, this, [window](QSystemTrayIcon::ActivationReason reason) {
            if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
                if (window) {
                    if (window->visibility() == QWindow::Minimized) {
                        window->showNormal();
                    }
                    window->setVisible(true);
                    window->raise();
                    window->requestActivate();
                }
            }
        });

        QObject::connect(showAction, &QAction::triggered, this, [window]() {
            if (window) {
                if (window->visibility() == QWindow::Minimized) {
                    window->showNormal();
                }
                window->setVisible(true);
                window->raise();
                window->requestActivate();
            }
        });

        QObject::connect(quitAction, &QAction::triggered, this, [this]() {
            // 完全退出，先隱藏托盤再 quit
            if (m_trayIcon) m_trayIcon->hide();
            QApplication::quit();
        });

        m_trayIcon->show();
        qDebug() << "System tray initialized.";
    }

    // 最小化到系統托盤（關閉按鈕觸發）
    Q_INVOKABLE void minimizeToTray(QQuickWindow *window) {
        if (!window || !m_trayIcon) return;

        window->hide();
        m_trayIcon->show();

        // Windows 氣泡提示：「Desktop Organizer 已最小化到系統托盤」
        m_trayIcon->showMessage(
            "Desktop Organizer",
            "已最小化到系統托盤，雙擊圖示還原。",
            QSystemTrayIcon::Information,
            3000
        );
    }

    // 從 QML 直接發送托盤提示
    Q_INVOKABLE void showTrayMessage(const QString &title, const QString &msg) {
        if (m_trayIcon)
            m_trayIcon->showMessage(title, msg, QSystemTrayIcon::Information, 3000);
    }
};

// ======================================================================
// 主函数
// ======================================================================
int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif

    QApplication app(argc, argv);
    app.setWindowIcon(QIcon(":/assets/app_icon.ico"));
    // 设置应用元数据 (在注册表和任务管理器中显示)
    app.setOrganizationName("SYSU CyberSec");
    app.setOrganizationDomain("sysu.edu.cn");
    app.setApplicationName("Desktop Organizer");
    app.setWindowIcon(QIcon(":/sticker.ico"));

    QQmlApplicationEngine engine;

#ifdef Q_OS_WIN
    // 安裝原生訊息過濾器：攔截 WM_NCCALCSIZE 消除透明框
    WinEventFilter filter;
    app.installNativeEventFilter(&filter);
#endif

    // 实例化后端类，并将其注册到 QML 的全局上下文中
    AppBackend backend;
    engine.rootContext()->setContextProperty("appBackend", &backend);

    // 加载 QML 主界面
    const QUrl url(QStringLiteral("qrc:/qt/qml/Desktop_Tool/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
                         if (!obj && url == objUrl)
                             QCoreApplication::exit(-1);
                     }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}

// 因为把 Q_OBJECT 写在 cpp 文件里，为了让 MOC (元对象编译器) 正确识别，
// 我们需要在末尾包含生成的 moc 文件（前提是 CMakeLists 中开启了 CMAKE_AUTOMOC）
#include "main.moc"
