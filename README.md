# Desktop Organizer

Windows 桌面整理工具。將檔案拖入浮動貼紙即可自動歸檔，也支援一鍵還原。

基於 Qt 6 / QML 開發。採用無邊框視窗設計，同時保留 Windows 11 原生的最大化、最小化、關閉及視窗貼靠動畫。

## 功能

### 浮動貼紙管理
- 在主視窗點擊「新增貼紙」，自訂顏色、名稱、檔案過濾規則
- 每個貼紙是一個獨立的無邊框子視窗，會附加到桌面圖層（WorkerW），不會被一般應用程式視窗遮擋
- 拖動與縮放後自動儲存位置（800ms 去抖），下次開啟時還原

### 檔案拖放歸檔
- 直接將檔案從桌面或檔案總管拖入貼紙，程式會自動複製或移動到對應的分類資料夾
- 使用 `RevokeDragDrop` 切換為 `WM_DROPFILES` 協定，避免桌面圖示層攔截拖放
- 跨磁碟區複製在背景執行緒進行（`QtConcurrent::run`），不阻塞 UI

### 檔案帳本（File Ledger）
- 每次移動檔案時記錄「目前位置 → 原始位置」的對應關係
- 刪除貼紙時根據帳本將所有檔案移回桌面原始位置
- 也支援單一檔案復原

### Windows 11 原生視窗行為
- `WM_NCCALCSIZE` 消除標題欄，保留 `WS_THICKFRAME` 以維持 DWM 動畫
- `WM_NCHITTEST` 處理邊緣縮放
- `WM_GETMINMAXINFO` 限制最大尺寸為目前螢幕工作區，最小 220×220

### 開機自啟
- 透過 `HKCU\Run` 註冊表設定開機啟動，附加 `--autostart` 參數
- 偵測到 `--autostart` 時主視窗自動隱藏，不干擾使用者
- 設定中心提供開關，動態讀取註冊表實際狀態

### 系統原生檔案圖示
- 自行實作 `QQuickImageProvider`，以 `Image` 類型非同步載入 Windows 檔案總管的圖示
- QML 端加上 `asynchronous: true`，避免 UI 卡頓

### 深色 / 淺色模式
- 設定中心即時切換，UI 元件的顏色切換帶有 `ColorAnimation` 過渡動畫

### 重置功能
- 設定中心底部提供重置按鈕，按下後彈出二次確認對話框
- 清除開機自啟註冊表、刪除 `%APPDATA%` 下的設定檔、自動退出程式

### 系統托盤
- 關閉視窗時最小化到系統托盤，支援左鍵還原、右鍵選單
- 托盤圖示使用內嵌 PNG（避免依賴 `qico.dll`）

## 快速開始

### 前置需求

- Qt 6.8+（需安裝 Quick、Widgets、Svg、Concurrent 模組）
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

或在 Qt Creator / VS Code（搭配 CMake 擴充）中直接開啟 `CMakeLists.txt` 建置。

## 專案結構

```
Desktop_Tool/
├── CMakeLists.txt              # CMake 建置設定
├── app.rc                      # Windows 資源檔（版本資訊、圖示）
├── resources.qrc               # Qt 資源檔
├── README.md
├── src/
│   ├── main.cpp                # 主程式、AppBackend、WinEventFilter、FileIconProvider
│   └── filehandler.h           # 檔案移動工具（舊版）
├── qml/
│   ├── Main.qml                # 主視窗（側邊欄、設定頁、重置對話框）
│   └── DesktopTag.qml          # 貼紙子視窗（檔案網格、拖放、動畫）
└── assets/
    └── app_icon.png             # 應用程式圖示
```

## 技術細節

| 項目 | 使用技術 |
|------|----------|
| UI 框架 | Qt 6 Quick + Qt Quick Controls |
| 圖形效果 | Qt Quick Effects（MultiEffect：陰影、模糊） |
| 後端邏輯 | C++17，AppBackend 繼承 QObject |
| 原生視窗處理 | QAbstractNativeEventFilter，攔截 WM_NCCALCSIZE / WM_NCHITTEST / WM_NCDESTROY / WM_DROPFILES |
| 桌面嵌入 | 透過 FindWindow(Progman) → 0x052C → WorkerW → SetParent 達成 |
| 拖放相容性 | RevokeDragDrop + ChangeWindowMessageFilterEx + DragAcceptFiles |
| 檔案圖示載入 | QQuickImageProvider::Image + QML asynchronous: true |
| 跨碟複製 | QtConcurrent::run + QMetaObject::invokeMethod 回主執行緒 |
| 設定儲存 | JSON，存放於 %APPDATA%/SYSU_DesktopOrganizer/config.json，寫入去抖 1s |
| 開機自啟 | HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run |
| 建置系統 | CMake + Ninja / MinGW Makefiles |
| 視窗管理 | QSet<HWND> 白名單，WM_NCDESTROY 時自動清除 |

### 跨螢幕黑色殘影處理

- 關閉 `setPersistentSceneGraph(true)` 與 `setPersistentGraphics(true)`
- 移除 `WM_ERASEBKGND` 處理常式
- 原因：不同 GPU 或 DPI 之間渲染緩衝未正確重建

### DWM 無限循環處理

- 加入 `isRefreshingDwm` 旗標搭配 `Qt.callLater()` 延遲解鎖
- 避免 `onVisibilityChanged` 與 `SetWindowPos` 互相觸發形成迴圈

## 授權

僅供個人學習與使用。
