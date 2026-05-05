cmake_minimum_required(VERSION 3.16)

project(Desktop_Tool VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOMOC ON)

# 1. 查找 Qt 库
find_package(Qt6 REQUIRED COMPONENTS Quick Widgets Svg)

# 2. Qt 标准项目设置
qt_standard_project_setup(REQUIRES 6.8)

# 3. 定义可执行文件目标 (只定义这一次)
# 物理路径已指向 src/
qt_add_executable(appDesktop_Tool
    src/main.cpp
    src/filehandler.h
    resources.qrc
    app.rc
)

# 4. 配置 QML 模块 (只定义这一次)
# 物理路径已指向 qml/
qt_add_qml_module(appDesktop_Tool
    URI Desktop_Tool
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        QML_FILES qml/DesktopTag.qml
)

# 5. 设置目标属性 (Windows/macOS 相关)
set_target_properties(appDesktop_Tool PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

# 6. 链接库
target_link_libraries(appDesktop_Tool
    PRIVATE Qt6::Quick Qt6::Widgets Qt6::Svg
    dwmapi
)

# 7. 安装设置 (GNU 标准路径)
include(GNUInstallDirs)
install(TARGETS appDesktop_Tool
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
set(CMAKE_AUTOMOC ON)
