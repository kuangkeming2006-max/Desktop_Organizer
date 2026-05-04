#ifndef FILEHANDLER_H
#define FILEHANDLER_H

#include <QObject>
#include <QUrl>
#include <QList>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDebug>

class FileHandler : public QObject {
    Q_OBJECT
public:
    explicit FileHandler(QObject *parent = nullptr) : QObject(parent) {}

    /**
     * @brief 核心分类函数：将文件移动到桌面指定的分类文件夹
     * @param urls 从 QML 传来的文件 URL 列表
     * @param categoryName 分类名称（例如 "PDF", "Images"）
     * @return 是否全部移动成功
     */
    Q_INVOKABLE bool moveFiles(const QList<QUrl> &urls, const QString &categoryName) {
        if (urls.isEmpty() || categoryName.isEmpty()) return false;

        // 1. 获取 Windows 桌面路径
        QString desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        QString targetDirPath = desktopPath + "/" + categoryName;

        // 2. 检查并创建目标文件夹 (如果不存在)
        QDir dir(targetDirPath);
        if (!dir.exists()) {
            if (!dir.mkpath(".")) {
                qWarning() << "无法创建目标文件夹:" << targetDirPath;
                return false;
            }
        }

        bool allSuccess = true;

        // 3. 遍历并移动文件
        for (const QUrl &url : urls) {
            // 将 QML 的 URL (file:///C:/...) 转换为本地路径 (C:/...)
            QString oldPath = url.toLocalFile();

            // 路径安全校验
            if (oldPath.isEmpty() || !QFile::exists(oldPath)) {
                qWarning() << "无效的文件路径:" << oldPath;
                allSuccess = false;
                continue;
            }

            QFileInfo fileInfo(oldPath);
            QString newPath = targetDirPath + "/" + fileInfo.fileName();

            // 如果目标位置已有同名文件，先尝试删除（或者你可以改为重命名逻辑）
            if (QFile::exists(newPath)) {
                QFile::remove(newPath);
            }

            // 执行移动操作
            if (QFile::rename(oldPath, newPath)) {
                qDebug() << "成功移动:" << fileInfo.fileName() << " -> " << categoryName;
            } else {
                qWarning() << "移动失败:" << oldPath;
                allSuccess = false;
            }
        }

        return allSuccess;
    }
};

#endif // FILEHANDLER_H
