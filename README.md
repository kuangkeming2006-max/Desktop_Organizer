# Desktop Organizer 🗂️

Windows 桌面整理工具 — 將檔案拖入浮動貼紙，自動歸檔，並可一鍵還原。

基於 **Qt 6 / QML**，無邊框視窗但保留 Windows 11 原生 DWM 動畫（最大化、最小化、關閉、貼靠）。

## ✨ 功能特色

### 🏷️ 浮動貼紙管理
- 在主視窗點擊「新增貼紙」→ 自訂顏色、名稱、檔案件數過濾規則
- 每個貼紙是一個獨立的無邊框子視窗，**注入桌面 WorkerW 圖層**，不會被其他視窗遮擋
- 拖動/縮放後自動保存幾何位置（去抖 800ms），下次開機精準還原

### 📁 檔案拖放歸檔
- 從桌面或文件管理器直接拖入貼紙 → 自動複製/移動到分類資料夾
- 底層使用 `RevokeDragDrop` 強制降級為 `WM_DROPFILES`，**繞過桌面圖標層攔截**
- 跨磁碟區非同步複製（`QtConcurrent::run`），不卡 UI

### 📒 檔案帳本（File Ledger）
- 每次移動檔案時記錄「目前位置 → 原始位置」映射
- 刪除貼紙時自動掃描帳本，**將所有檔案還原回桌面原始路徑**
- 也支援單一檔案精準復原

### 🪟 Windows 11 原生動畫
- 無邊框（`WM_NCCALCSIZE` 消除標題欄）、保留 `WS_THICKFRAME` 觸發 DWM 動畫
- `WM_NCHITTEST` 邊緣縮放、`WM_NCACTIVATE` 保留原生最大化/最小化/關閉過渡
- `WM_GETMINMAXINFO` 限制最大尺寸在目前螢幕工作區、最小 220×220

### 🚀 開機自啟（Silent Boot）
- `HKCU\Run` 註冊表自啟動，附加 `--autostart` 參數
- 檢測到自啟參數時主視窗自動隱藏（`visible: !isSilentBoot`），不干擾用戶
- 設置中心提供一鍵開關，動態讀取註冊表真實狀態

### 🖼️ 系統原生檔案圖標
- 自訂 `QQuickImageProvider`（Image 類型）非同步載入 Windows 檔案總管圖標
- QML 側 `Image { asynchronous: true }` 避免 UI 卡頓

### 🌙 深色 / 淺色模式
- 設置中心即時切換，所有 UI 元件（卡片、文字、輸入框、按鈕）平滑過渡
- `Behavior on color` + `ColorAnimation` 動畫

### 🗑️ 全量重置
- 設置中心底部紅色危險區域 → 二次確認 Dialog
- 清除註冊表自啟 + 刪除 `%APPDATA%` 配置目錄 + 自動退出

### 🔔 系統托盤
- 關閉視窗 → 最小化到托盤，支援左鍵點擊還原、右鍵選單
- 托盤圖標使用內嵌 PNG（避免 `qico.dll` 依賴問題）

## 🚀 快速開始

### 前置需求

- [Qt 6.8+](https://www.qt.io/download)（含 `Qt Quick`、`Qt Widgets`、`Qt SVG`、`Qt Concurrent` 模組）
- CMake 3.16+
- C++17 編譯器（MinGW 或 MSVC，Windows SDK）

### 建置

```bash
# Release
cmake -B build/Release -DCMAKE_BUILD_TYPE=Release
cmake --build build/Release --parallel

# Debug
cmake -B build/Debug -DCMAKE_BUILD_TYPE=Debug
cmake --build build/Debug --parallel
```

或直接在 **Qt Creator** / **VS Code**（搭配 CMake 擴充）打開 `CMakeLists.txt` 建置。

## 🧩 專案結構

```
Desktop_Tool/
├── CMakeLists.txt              # CMake 建置（Qt6 Quick/Widgets/Svg/Concurrent）
├── app.rc                      # Windows 應用資源（版本資訊、圖標）
├── resources.qrc               # Qt 資源檔（app_icon.png）
├── README.md
├── src/
│   ├── main.cpp                # 主程式入口、AppBackend 後端、WinEventFilter、FileIconProvider
│   └── filehandler.h           # （舊版）檔案移動工具類別
├── qml/
│   ├── Main.qml                # 主視窗（側邊欄 + 設置中心 + 二次確認 Dialog）
│   └── DesktopTag.qml          # 貼紙子視窗元件（檔案網格、拖放、動畫）
└── assets/
    └── app_icon.png             # 應用程式圖標
```

## 🧠 技術細節

| 層級 | 技術 |
|------|------|
| UI 框架 | Qt 6 Quick (QML) + Qt Quick Controls |
| 圖形效果 | Qt Quick Effects (`MultiEffect`：陰影、模糊) |
| 後端邏輯 | C++17 (`AppBackend` : `QObject`) |
| 原生視窗 | `QAbstractNativeEventFilter` → `WM_NCCALCSIZE` / `WM_NCHITTEST` / `WM_NCDESTROY` / `WM_DROPFILES` |
| 桌面注入 | `FindWindow(Progman)` → `0x052C` → `WorkerW` → `SetParent` |
| 拖放繞過 | `RevokeDragDrop` + `ChangeWindowMessageFilterEx` + `DragAcceptFiles` |
| 非同步圖標 | `QQuickImageProvider::Image` + QML `asynchronous: true` |
| 非同步複製 | `QtConcurrent::run` + `QMetaObject::invokeMethod` 回主線程 |
| 配置儲存 | JSON (`%APPDATA%/SYSU_DesktopOrganizer/config.json`)，寫入防抖 1s |
| 開機自啟 | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| 建置系統 | CMake + Ninja / MinGW Makefiles |
| 視窗白名單 | `QSet<HWND>`，`WM_NCDESTROY` 時自動 GC |

### 跨螢幕黑色殘影修復（2025-05-07）

- 禁用 `setPersistentSceneGraph(true)` / `setPersistentGraphics(true)`
- 移除 `WM_ERASEBKGND` 處理常式
- 原因：不同 GPU/DPI 間渲染緩衝未重建導致

### DWM 無限循環修復

- `isRefreshingDwm` 布林鎖 + `Qt.callLater()` 延遲解鎖
- 防止 `onVisibilityChanged` + `setWindowPos` 形成事件風暴

## 📝 授權

本專案僅供個人學習與使用。
