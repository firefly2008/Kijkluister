// SPDX-License-Identifier: GPL-2.0-or-later
#include "appmodel.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>
#include <QDesktopServices>
#include <QDirIterator>
#include <QFileInfo>
#include <QImageReader>
#include <QSet>
#include <QStandardPaths>

#include <algorithm>

namespace {
QString dataDir()
{
    QString base = qEnvironmentVariable("LOCALAPPDATA");
    if (base.isEmpty()) {
        base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    }
    const QString dir = QDir::fromNativeSeparators(base) + QStringLiteral("/BigscreenHost");
    QDir().mkpath(dir);
    return dir;
}

void removeLocalFile(const QString &fileUrl)
{
    if (!fileUrl.isEmpty()) {
        QFile::remove(QUrl(fileUrl).toLocalFile());
    }
}
}

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_settings(dataDir() + QStringLiteral("/settings.ini"), QSettings::IniFormat)
{
    m_hidden = m_settings.value(QStringLiteral("hiddenApps")).toStringList();
    m_customIcons = m_settings.value(QStringLiteral("customIcons")).toMap();
    m_background = m_settings.value(QStringLiteral("background")).toString();
    refresh();
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_apps.size();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_apps.size()) {
        return {};
    }
    const App &app = m_apps.at(index.row());
    switch (role) {
    case NameRole:
        return app.name;
    case PathRole:
        return app.path;
    case IconRole: {
        const QString custom = m_customIcons.value(app.path).toString();
        if (!custom.isEmpty()) {
            return custom;
        }
        return QString(QStringLiteral("image://appicon/")
                       + QString::fromLatin1(QUrl::toPercentEncoding(app.path)));
    }
    case CustomIconRole:
        return m_customIcons.contains(app.path);
    }
    return {};
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    return {{NameRole, "name"}, {PathRole, "path"}, {IconRole, "iconSource"}, {CustomIconRole, "customIcon"}};
}

void AppModel::refresh()
{
    // Snelkoppelingen die geen toepassing zijn (verwijderprogramma's, handleidingen, ...)
    static const QStringList skipWords = {
        QStringLiteral("uninstall"), QStringLiteral("verwijder"), QStringLiteral("deinstall"),
        QStringLiteral("readme"), QStringLiteral("help"), QStringLiteral("website"),
        QStringLiteral("documentation"), QStringLiteral("documentatie"), QStringLiteral("license"),
        QStringLiteral("release notes"), QStringLiteral("manual"), QStringLiteral("handleiding"),
        QStringLiteral("bigscreen host"),
    };

    QList<App> apps;
    QSet<QString> seen;
    QStringList roots = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
#ifdef Q_OS_WIN
    // Qt geeft alleen het Startmenu van de gebruiker; de meeste programma's staan
    // in het gedeelde Startmenu onder ProgramData.
    const QString programData = qEnvironmentVariable("ProgramData");
    if (!programData.isEmpty()) {
        roots.append(QDir::fromNativeSeparators(programData) + QStringLiteral("/Microsoft/Windows/Start Menu/Programs"));
    }
#endif
    for (const QString &root : std::as_const(roots)) {
        QDirIterator it(root, {QStringLiteral("*.lnk")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo info(it.next());
            const QString name = info.completeBaseName();
            const QString key = name.toLower();
            const QString path = QDir::toNativeSeparators(info.absoluteFilePath());
            if (seen.contains(key) || m_hidden.contains(path)) {
                continue;
            }
            const bool skip = std::any_of(skipWords.begin(), skipWords.end(), [&key](const QString &word) {
                return key.contains(word);
            });
            if (skip) {
                continue;
            }
            seen.insert(key);
            apps.append({name, path});
        }
    }
    std::sort(apps.begin(), apps.end(), [](const App &a, const App &b) {
        return a.name.localeAwareCompare(b.name) < 0;
    });

    beginResetModel();
    m_apps = apps;
    endResetModel();
    Q_EMIT countChanged();
    qInfo() << "Apps found" << m_apps.size() << "hidden" << m_hidden.size() << "in" << roots;
}

bool AppModel::launch(int row)
{
    if (row < 0 || row >= m_apps.size()) {
        return false;
    }
    const App &app = m_apps.at(row);
    const bool ok = QDesktopServices::openUrl(QUrl::fromLocalFile(app.path));
    qInfo() << "Launch" << app.name << (ok ? "ok" : "FAILED");
    return ok;
}

bool AppModel::openUri(const QString &uri)
{
    const bool ok = QDesktopServices::openUrl(QUrl(uri));
    qInfo() << "Open" << uri << (ok ? "ok" : "FAILED");
    return ok;
}

QString AppModel::nameAt(int row) const
{
    return (row >= 0 && row < m_apps.size()) ? m_apps.at(row).name : QString();
}

bool AppModel::hasCustomIcon(int row) const
{
    return row >= 0 && row < m_apps.size() && m_customIcons.contains(m_apps.at(row).path);
}

void AppModel::hide(int row)
{
    if (row < 0 || row >= m_apps.size()) {
        return;
    }
    m_hidden.append(m_apps.at(row).path);
    m_settings.setValue(QStringLiteral("hiddenApps"), m_hidden);
    beginRemoveRows({}, row, row);
    m_apps.removeAt(row);
    endRemoveRows();
    Q_EMIT countChanged();
}

void AppModel::restoreHidden()
{
    m_hidden.clear();
    m_settings.setValue(QStringLiteral("hiddenApps"), m_hidden);
    refresh();
}

// Kopieert de gekozen afbeelding naar de eigen datamap, zodat het pictogram of de
// achtergrond blijft werken als het origineel verplaatst of gewist wordt.
QString AppModel::importImage(const QUrl &source, const QString &baseName)
{
    const QString sourcePath = source.isLocalFile() ? source.toLocalFile() : source.toString();
    const QFileInfo info(sourcePath);
    if (!info.isFile() || QImageReader(sourcePath).format().isEmpty()) {
        qWarning() << "Not a readable image:" << sourcePath;
        return {};
    }
    const QString dir = dataDir() + QStringLiteral("/images");
    QDir().mkpath(dir);
    // Tijdstempel in de naam: anders toont QML de oude afbeelding uit zijn cache
    const QString target = QStringLiteral("%1/%2-%3.%4")
                               .arg(dir, baseName)
                               .arg(QDateTime::currentMSecsSinceEpoch())
                               .arg(info.suffix().toLower());
    if (!QFile::copy(sourcePath, target)) {
        qWarning() << "Could not copy" << sourcePath << "to" << target;
        return {};
    }
    return QUrl::fromLocalFile(target).toString();
}

bool AppModel::setCustomIcon(int row, const QUrl &imageFile)
{
    if (row < 0 || row >= m_apps.size()) {
        return false;
    }
    const QString path = m_apps.at(row).path;
    const QString hash = QString::fromLatin1(
        QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Md5).toHex().left(12));
    const QString imported = importImage(imageFile, QStringLiteral("icon-") + hash);
    if (imported.isEmpty()) {
        return false;
    }
    removeLocalFile(m_customIcons.value(path).toString());
    m_customIcons.insert(path, imported);
    m_settings.setValue(QStringLiteral("customIcons"), m_customIcons);
    Q_EMIT dataChanged(index(row), index(row), {IconRole, CustomIconRole});
    return true;
}

void AppModel::clearCustomIcon(int row)
{
    if (!hasCustomIcon(row)) {
        return;
    }
    const QString path = m_apps.at(row).path;
    removeLocalFile(m_customIcons.take(path).toString());
    m_settings.setValue(QStringLiteral("customIcons"), m_customIcons);
    Q_EMIT dataChanged(index(row), index(row), {IconRole, CustomIconRole});
}

bool AppModel::setBackground(const QUrl &imageFile)
{
    const QString imported = importImage(imageFile, QStringLiteral("background"));
    if (imported.isEmpty()) {
        return false;
    }
    removeLocalFile(m_background);
    m_background = imported;
    m_settings.setValue(QStringLiteral("background"), m_background);
    Q_EMIT backgroundChanged();
    return true;
}

void AppModel::clearBackground()
{
    removeLocalFile(m_background);
    m_background.clear();
    m_settings.setValue(QStringLiteral("background"), m_background);
    Q_EMIT backgroundChanged();
}
