# Desktop Organizer 🗂️

一個基於 **Qt 6 / QML** 的 Windows 桌面整理工具，採用無邊框設計並保留 Windows 11 原生視窗動畫。

## ✨ 功能特色

- **🏷️ 貼紙標籤管理** — 創建自定義顏色的貼紙標籤，快速分類桌面檔案
- **📁 檔案拖放歸檔** — 將檔案拖入對應貼紙，自動移動至指定目錄並記錄原始位置
- **♻️ 一鍵還原** — 刪除貼紙時，根據帳本自動將所有檔案移回桌面原始位置
- **🌙 深色/淺色模式** — 支援即時切換，所有 UI 元件平滑過渡
- **🪟 Windows 11 原生動畫** — 無邊框視窗搭配 DWM 原生最大/最小化/關閉動畫
- **⚙️ JSON 配置持久化** — 貼紙列表、檔案帳本（File Ledger）自動儲存於 `%APPDATA%`

## 📸 畫面預覽

> （待補截圖）

## 🚀 快速開始

### 前置需求

- [Qt 6.8+](https://www.qt.io/download)（含 `Qt Quick` 模組）
- CMake 3.16+
- C++17 編譯器（MinGW 或 MSVC）

### 建置

```bash
# 使用 CMake
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel

# 執行
./build/Desktop_Tool/appDesktop_Tool.exe
```

或直接在 **Qt Creator** / **VS Code** 中打開 `CMakeLists.txt` 建置執行。

## 🧩 專案結構

```
Desktop_Tool/
├── CMakeLists.txt          # CMake 建置配置
├── .gitignore
├── README.md
├── src/
│   ├── main.cpp            # 主程式入口 + AppBackend 後端邏輯
│   └── filehandler.h       # 檔案移動工具類別
└── qml/
    ├── Main.qml            # 主視窗 UI（側邊欄、內容區、深淺色切換）
    └── DesktopTag.qml      # 貼紙標籤子視窗元件
```

## 🛠️ 技術堆疊

| 層級 | 技術 |
|------|------|
| UI 框架 | Qt 6 Quick (QML) |
| 圖形效果 | Qt Quick Effects (MultiEffect) |
| 後端邏輯 | C++17 (QObject 派生類別) |
| 配置儲存 | JSON (`%APPDATA%/SYSU_DesktopOrganizer/config.json`) |
| 建置系統 | CMake + Ninja |

## 📝 授權

本專案僅供個人學習與使用。
