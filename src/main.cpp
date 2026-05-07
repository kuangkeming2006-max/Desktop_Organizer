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
#include <QQuickImageProvider>
#include <QFileIconProvider>
#include <QMenu>
#include <QAction>
#include <QPointer>
#include <QPixmap>
#include <QSet>
#include <QTimer>
#include <QtConcurrent/QtConcurrentRun>
#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <ole2.h>
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "user32.lib")

// 前向宣告（自由函數，繞過 WinEventFilter ↔ AppBackend 循環依賴）
class AppBackend;
extern AppBackend* g_appBackend;
void forwardNativeDrop(HWND hwnd, const QStringList& filePaths);
void forwardUnregisterHwnd(HWND hwnd);

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
            // +++ 拦截基础拖拽消息 +++
            case WM_DROPFILES: {
                HDROP hDrop = (HDROP)msg->wParam;
                UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, NULL, 0);
                QStringList filePaths;
                for (UINT i = 0; i < count; ++i) {
                    TCHAR filePath[MAX_PATH];
                    if (DragQueryFileW(hDrop, i, filePath, MAX_PATH)) {
                        filePaths.append(QString::fromWCharArray(filePath));
                    }
                }
                DragFinish(hDrop);

                // 将文件路径传给 Backend（透過自由函數，繞過循環依賴）
                forwardNativeDrop(msg->hwnd, filePaths);
                if (result) *result = 0;
                return true; // 告诉系统我们处理完毕
            }
            // 【2025-05-07 移除】：攔截 WM_ERASEBKGND 在跨屏時會導致黑色殘影
            // （Qt 6 渲染管線已妥善處理透明背景，無需手動接管擦除）
            // case WM_ERASEBKGND: { ... }

            // 【新增】：手动接管鼠标的边缘命中测试，完美恢复边缘拖拽缩放功能
            case WM_NCHITTEST: {
                // 获取鼠标当前的屏幕坐标
                POINT pt;
                pt.x = (int)(short)LOWORD(msg->lParam);
                pt.y = (int)(short)HIWORD(msg->lParam);

                // 获取当前窗口的屏幕坐标
                RECT rc;
                GetWindowRect(msg->hwnd, &rc);

                // 转换为相对于窗口的局部坐标
                int x = pt.x - rc.left;
                int y = pt.y - rc.top;

                // 定义触发缩放的边缘宽度
                int bw = 8;

                bool left = x < bw;
                bool right = x >= (rc.right - rc.left) - bw;
                bool top = y < bw;
                bool bottom = y >= (rc.bottom - rc.top) - bw;

                // 告诉 Windows 鼠标当前悬停在哪个边缘
                if (top && left) { if (result) *result = HTTOPLEFT; return true; }
                if (top && right) { if (result) *result = HTTOPRIGHT; return true; }
                if (bottom && left) { if (result) *result = HTBOTTOMLEFT; return true; }
                if (bottom && right) { if (result) *result = HTBOTTOMRIGHT; return true; }
                if (left) { if (result) *result = HTLEFT; return true; }
                if (right) { if (result) *result = HTRIGHT; return true; }
                if (top) { if (result) *result = HTTOP; return true; }
                if (bottom) { if (result) *result = HTBOTTOM; return true; }

                // 如果不在边缘，放行让 Qt 自己处理
                return false;
            }

            case WM_NCCALCSIZE: {
                if (msg->wParam == TRUE) {
                    // 【终极修复】：绝对不要写 ncp->rgrc[0] = ncp->rgrc[1]; ！！
                    // 直接返回 0，告诉 Windows 我们的透明客户区要覆盖 100% 的窗口面积
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

                // ==========================================
                // 【新增】：告诉 Windows 原生拖拽缩放的最小界限
                // 根据你的 UI 设计，220x220 是个不错的下限，防止卡片被压扁
                // ==========================================
                mmi->ptMinTrackSize.x = 220;
                mmi->ptMinTrackSize.y = 220;

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
                // 【新增】：同步清理後端字典，防止野指针閃退（透過自由函數繞過循環依賴）
                forwardUnregisterHwnd(msg->hwnd);
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

// ==================== 获取系统原生文件图标 ====================
class FileIconProvider : public QQuickImageProvider {
public:
    FileIconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override {
        QFileInfo fileInfo(id);
        QFileIconProvider provider;
        
        QIcon icon = provider.icon(fileInfo);

        int width = 32;
        int height = 32;
        if (requestedSize.width() > 0) width = requestedSize.width();
        if (requestedSize.height() > 0) height = requestedSize.height();
        if (size) *size = QSize(width, height);

        if (icon.isNull()) {
            QImage empty(width, height, QImage::Format_ARGB32);
            empty.fill(Qt::transparent);
            return empty;
        }

        return icon.pixmap(width, height).toImage();
    }
};


class AppBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool trayAvailable READ isTrayAvailable CONSTANT)
private:
    QJsonObject m_config;
    QSystemTrayIcon *m_trayIcon = nullptr;
    QPointer<QQuickWindow> m_mainWindow;

    // +++ 1. 添加单例支持和窗口映射表 +++
    static AppBackend* s_instance;
    QMap<HWND, QString> m_hwndToTagId;
    QTimer *m_saveTimer;

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
        m_saveTimer->start(); // 防抖：1秒内多次调用僅觸發一次實際寫入
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
    static AppBackend* instance() { return s_instance; }

    // +++ 2. 新增一个信号，用于通知 QML 文件已就绪 +++
signals:
    void filesDroppedNative(const QString &tagId, const QStringList &fileUrls);
    void asyncFileMoveFinished(const QString &destPath, bool success);

public:
    // +++ 3. 新增供 QML 调用的注册函数 +++
    Q_INVOKABLE void registerTagWindowId(QQuickWindow* window, const QString& tagId) {
        if (!window) return;
        HWND hwnd = reinterpret_cast<HWND>(window->winId());
        m_hwndToTagId[hwnd] = tagId;

        // 【核心黑科技】：强行注销 Qt 默认的 OLE 高级拖拽，
        // 迫使 Windows 降级使用基础的 WM_DROPFILES，从而绕过桌面图标层的拦截！
        RevokeDragDrop(hwnd);
    }

    // +++ 4a. 新增：窗口銷毀時清理字典，防止野指標閃退 +++
    Q_INVOKABLE void unregisterTagWindowId(HWND hwnd) {
        m_hwndToTagId.remove(hwnd);
    }

    // +++ 4b. 新增底层处理器 +++
    void handleNativeDrop(HWND hwnd, const QStringList& paths) {
        if (m_hwndToTagId.contains(hwnd)) {
            QString tagId = m_hwndToTagId[hwnd];
            QStringList urls;
            for (const QString& path : paths) {
                // 转为 file:/// 格式以兼容你现有的移动逻辑
                urls.append("file:///" + QString(path).replace("\\", "/"));
            }
            emit filesDroppedNative(tagId, urls);
        }
    }

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

    // 【修改】：新增 bool isTagWindow = false 参数
    Q_INVOKABLE void initNativeWindow(QQuickWindow* window, bool isTagWindow = false) {
        if (!window) return;
        HWND hwnd = reinterpret_cast<HWND>(window->winId());

#ifdef Q_OS_WIN
        // 补充宏定义，防止旧版 MinGW/MSVC SDK 找不到这些常量
        #ifndef DWMWA_WINDOW_CORNER_PREFERENCE
        #define DWMWA_WINDOW_CORNER_PREFERENCE 33
        #endif
        #ifndef DWMWCP_DONOTROUND
        #define DWMWCP_DONOTROUND 1
        #endif

        // 將 HWND 註冊到原生事件過濾器（用於 WM_SHOWWINDOW 刷新）
        if (WinEventFilter::instance())
            WinEventFilter::instance()->addWindow(hwnd);

        LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);

        // ==========================================
        // 【核心修复】：样式隔离
        // ==========================================
        if (!isTagWindow) {
            // 主窗口：保留原生 DWM 特性（吸附、阴影等）
            style |= WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
        } else {
            // 贴纸窗口：作为桌面纯子窗口，绝对不能有 CAPTION 和 THICKFRAME
            // 强行剔除这些样式，防止缩放时暴露出原生蓝框
            style &= ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU);
        }
        SetWindowLongPtr(hwnd, GWL_STYLE, style);

        // 【新增 1】：明确告诉 QQuickWindow 你的物理底层必须是透明的
        window->setColor(Qt::transparent);

        // 【新增 2】：禁用 Windows 11 原生 DWM 圆角，防止和 QML 里的 radius 打架
        int cornerPreference = 1; // DWMWCP_DONOTROUND
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPreference, sizeof(cornerPreference));

        // 啟用持久場景圖與圖形資源：最小化/隱藏後不會釋放渲染緩衝，避免還原後變透明
        // 【2025-05-07 禁用】：跨屏時會導致黑色殘影（不同 GPU/DPI 間渲染緩衝未重建）
        // window->setPersistentSceneGraph(true);
        // window->setPersistentGraphics(true);

        // 【新增】：解除 UIPI 消息攔截，允許外部進程（如 Explorer）將文件拖入
        // WM_DROPFILES = 0x0233
        // WM_COPYDATA = 0x004A
        // 0x0049 是 WM_COPYGLOBALDATA，拖拽文件必備
        ChangeWindowMessageFilterEx(hwnd, WM_DROPFILES, MSGFLT_ALLOW, NULL);
        ChangeWindowMessageFilterEx(hwnd, WM_COPYDATA, MSGFLT_ALLOW, NULL);
        ChangeWindowMessageFilterEx(hwnd, 0x0049, MSGFLT_ALLOW, NULL);

        // 確保窗口支持接受文件拖放（原生層級）
        DragAcceptFiles(hwnd, TRUE);
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
        s_instance = this; // 绑定单例
        g_appBackend = this; // 也绑定 extern 全局指標
        loadConfig(); // 启动时加载配置

        // JSON 落盤防抖定時器：延遲 1 秒，單次觸發
        m_saveTimer = new QTimer(this);
        m_saveTimer->setSingleShot(true);
        m_saveTimer->setInterval(1000);
        connect(m_saveTimer, &QTimer::timeout, this, [this]() {
            QFile file(getConfigPath());
            if (file.open(QIODevice::WriteOnly)) {
                QJsonDocument doc(m_config);
                file.write(doc.toJson());
                file.close();
            }
        });
    }

    // ==================== 暴露给 QML 的接口 ====================

    // 1. 开机自启：写入/移除 Windows 注册表 Run 键
    Q_INVOKABLE void setAutoStart(bool enable) {
        QString appName = QCoreApplication::applicationName();
        QString appPath = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());

        QSettings reg("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", QSettings::NativeFormat);

        if (enable) {
            reg.setValue(appName, "\"" + appPath + "\" --autostart");
            qDebug() << "开机自启已启用:" << appPath << "--autostart";
        } else {
            reg.remove(appName);
            qDebug() << "开机自启已移除";
        }
    }

    // 1b. 读取当前真实的注册表自启状态
    Q_INVOKABLE bool isAutoStartEnabled() {
        QString appName = QCoreApplication::applicationName();
        QSettings reg("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", QSettings::NativeFormat);
        return reg.contains(appName);
    }

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
        qDebug() << "🟢 [后端探测] --- moveFileToTag 被调用 ---";
        qDebug() << "🟢 [后端探测] 接收到的原始 URL:" << fileUrl;
        qDebug() << "🟢 [后端探测] 目标文件夹路径:" << destFolder;

        QUrl url(fileUrl);
        if (!url.isLocalFile()) {
            qDebug() << "❌ [后端报错] 传入的 URL 不是本地文件！";
            return false;
        }

        QString sourcePath = url.toLocalFile();
        QFileInfo fileInfo(sourcePath);
        qDebug() << "🟢 [后端探测] 解析出的源文件绝对路径:" << sourcePath;
        qDebug() << "🟢 [后端探测] 源文件是否存在?" << fileInfo.exists();

        if (!fileInfo.exists()) {
            qDebug() << "❌ [后端报错] 找不到源文件，操作终止。";
            return false;
        }

        QDir dir(destFolder);
        if (!dir.exists()) {
            qDebug() << "🟢 [后端探测] 目标文件夹不存在，尝试创建...";
            bool mkDirSuccess = dir.mkpath(".");
            qDebug() << "🟢 [后端探测] 文件夹创建结果:" << mkDirSuccess;
        }

        QString destPath = dir.absoluteFilePath(fileInfo.fileName());
        qDebug() << "🟢 [后端探测] 准备移动到的目标路径:" << destPath;

        // 尝试重命名 (同一盘符)
        bool moveSuccess = QFile::rename(sourcePath, destPath);
        qDebug() << "🟢 [后端探测] QFile::rename 执行结果:" << moveSuccess;

        if (!moveSuccess) {
            qDebug() << "🟡 [后端警告] rename 失败，启动异步跨盘符复制（不阻塞 UI）...";
            // 在后台线程执行耗时的文件复制操作
            QtConcurrent::run([this, sourcePath, destPath]() {
                bool copyOk = QFile::copy(sourcePath, destPath);
                if (copyOk) {
                    QFile::remove(sourcePath); // 复制成功后删除源文件
                    // 回到主线程更新账本
                    QMetaObject::invokeMethod(this, [this, destPath, sourcePath]() {
                        QJsonObject ledger = m_config["fileLedger"].toObject();
                        ledger[destPath] = sourcePath;
                        m_config["fileLedger"] = ledger;
                        saveConfig();
                        qDebug() << "🟢 [异步] 跨盘符复制完成，账本已更新:" << destPath;
                    }, Qt::QueuedConnection);
                }
                emit asyncFileMoveFinished(destPath, copyOk);
            });
            // 乐观返回 true，QML 立即添加文件到列表
            qDebug() << "🟡 [异步] 跨盘符复制已提交后台线程，UI 不阻塞。";
            return true;
        }

        if (moveSuccess) {
            QJsonObject ledger = m_config["fileLedger"].toObject();
            ledger[destPath] = sourcePath;
            m_config["fileLedger"] = ledger;
            saveConfig();
            qDebug() << "🟢 [后端探测] 操作完成，账本已更新保存。";
            return true;
        }

        qDebug() << "❌ [后端报错] 文件移动最终宣告失败。";
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

    // --- 新增：复原单个文件到原本的位置 ---
    Q_INVOKABLE bool restoreSingleFile(const QString &tagFolder, const QString &fileName) {
        QDir dir(tagFolder);
        QString currentPath = dir.absoluteFilePath(fileName);
        QJsonObject ledger = m_config["fileLedger"].toObject();

        if (ledger.contains(currentPath)) {
            QString originalPath = ledger[currentPath].toString();

            bool moveSuccess = QFile::rename(currentPath, originalPath);
            if (!moveSuccess) {
                if (QFile::copy(currentPath, originalPath)) {
                    QFile::remove(currentPath);
                    moveSuccess = true;
                }
            }

            if (moveSuccess) {
                ledger.remove(currentPath);
                m_config["fileLedger"] = ledger;
                saveConfig();
                
                qDebug() << "🟢 单个文件已精准复原:" << originalPath;
                return true;
            }
        } else {
            qDebug() << "❌ 账本中找不到该文件的原始路径记录 (可能是手动复制入文件夹的):" << currentPath;
        }
        
        return false;
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

    // 新增：修改贴纸过滤规则
    Q_INVOKABLE void updateTagRules(const QString &tagId, const QString &allowedExts) {
        QJsonArray tags = m_config["tags"].toArray();
        for (int i = 0; i < tags.size(); ++i) {
            QJsonObject obj = tags[i].toObject();
            if (obj["id"].toString() == tagId) {
                obj["allowedExts"] = allowedExts;
                tags[i] = obj;
                break;
            }
        }
        m_config["tags"] = tags;
        saveConfig();
        qDebug() << "🟢 贴纸规则已更新:" << tagId << allowedExts;
    }

    // 8. 恢复显示：读取指定目录下的所有文件和文件夹
    Q_INVOKABLE QStringList getFilesInFolder(const QString &folderPath) {
        QStringList fileNames;
        QDir dir(folderPath);
        if (dir.exists()) {
            // 读取文件和文件夹，排除 '.' 和 '..' （当前目录和上级目录的隐藏标记）
            QFileInfoList fileList = dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QFileInfo &info : fileList) {
                fileNames.append(info.fileName());
            }
        }
        return fileNames;
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

        // 【修改】：Qt中统一使用免插件原生支持的 png 格式加载，彻底避免找不到 qico.dll 插件的bug
        QIcon appIcon = QIcon(":/assets/app_icon.png");
        
        // 若获取失败，优先回退到应用主窗口的默认图标（常由系统从 exe 中提供）
        if (appIcon.isNull()) {
            appIcon = QCoreApplication::instance() ? qApp->windowIcon() : QIcon();
        }
        
        // 保底措施（如果最终还是拿不到，才用色块）
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

// +++ 5. 在类外初始化静态成员 +++
AppBackend* AppBackend::s_instance = nullptr;
AppBackend* g_appBackend = nullptr;

// 转发函数定义（放在 AppBackend 之后，此时 g_appBackend 指向完整类型）
void forwardNativeDrop(HWND hwnd, const QStringList& filePaths) {
    if (g_appBackend) {
        g_appBackend->handleNativeDrop(hwnd, filePaths);
    }
}

void forwardUnregisterHwnd(HWND hwnd) {
    if (g_appBackend) {
        g_appBackend->unregisterTagWindowId(hwnd);
    }
}

// ======================================================================
// 主函数
// ======================================================================
int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif

    QApplication app(argc, argv);
    // 设置应用元数据 (在注册表和任务管理器中显示)
    app.setOrganizationName("SYSU CyberSec");
    app.setOrganizationDomain("sysu.edu.cn");
    app.setApplicationName("Desktop Organizer");
    // 【修改】：Qt中统一使用免插件原生支持的 png 格式
    app.setWindowIcon(QIcon(":/assets/app_icon.png"));

    // 判断是否是静默自启（随系统开机启动）
    bool isSilentBoot = app.arguments().contains("--autostart");

    QQmlApplicationEngine engine;

    // 注入自启标识给 QML（控制主窗口是否默认显示）
    engine.rootContext()->setContextProperty("isSilentBoot", isSilentBoot);

    // +++ 注册系统图标提供者 "fileicon" +++
    engine.addImageProvider(QLatin1String("fileicon"), new FileIconProvider);

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
