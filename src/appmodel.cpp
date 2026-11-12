// SPDX-License-Identifier: GPL-2.0-or-later
#include "appmodel.h"

#include <QDebug>
#include <QDesktopServices>
#include <QDirIterator>
#include <QFileInfo>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
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
    case IconRole:
        return QString(QStringLiteral("image://appicon/")
                       + QString::fromLatin1(QUrl::toPercentEncoding(app.path)));
    }
    return {};
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    return {{NameRole, "name"}, {PathRole, "path"}, {IconRole, "iconSource"}};
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
    // Op Windows: Startmenu\Programma's van de gebruiker en van alle gebruikers
    const QStringList roots = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    for (const QString &root : roots) {
        QDirIterator it(root, {QStringLiteral("*.lnk")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo info(it.next());
            const QString name = info.completeBaseName();
            const QString key = name.toLower();
            if (seen.contains(key)) {
                continue;
            }
            const bool skip = std::any_of(skipWords.begin(), skipWords.end(), [&key](const QString &word) {
                return key.contains(word);
            });
            if (skip) {
                continue;
            }
            seen.insert(key);
            apps.append({name, QDir::toNativeSeparators(info.absoluteFilePath())});
        }
    }
    std::sort(apps.begin(), apps.end(), [](const App &a, const App &b) {
        return a.name.localeAwareCompare(b.name) < 0;
    });

    beginResetModel();
    m_apps = apps;
    endResetModel();
    Q_EMIT countChanged();
    qInfo() << "Apps found" << m_apps.size() << "in" << roots;
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
