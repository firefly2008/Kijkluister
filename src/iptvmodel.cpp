// SPDX-License-Identifier: GPL-2.0-or-later
#include "iptvmodel.h"
#include "appmodel.h"

#include <QDebug>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QUrlQuery>

namespace {

const QString favoritesGroup = QStringLiteral("Favorieten");
const QString allGroup = QStringLiteral("Alle zenders");
const QString otherGroup = QStringLiteral("Overig");

// Zelfde kenmerken als open-tv (src-tauri/src/m3u.rs)
const QRegularExpression nameAttr(QStringLiteral(R"re(tvg-name="([^"]*)")re"));
const QRegularExpression idAttr(QStringLiteral(R"re(tvg-id="([^"]*)")re"));
const QRegularExpression logoAttr(QStringLiteral(R"re(tvg-logo="([^"]*)")re"));
const QRegularExpression groupAttr(QStringLiteral(R"re(group-title="([^"]*)")re"));

QString capture(const QRegularExpression &re, const QString &line)
{
    return re.match(line).captured(1).trimmed();
}

QString serverUrl(QString url)
{
    url = url.trimmed();
    if (!url.contains(QStringLiteral("://"))) {
        url.prepend(QStringLiteral("http://"));
    }
    while (url.endsWith(QLatin1Char('/'))) {
        url.chop(1);
    }
    // Iemand plakt soms het hele player_api-adres: alleen de server bewaren
    const int api = url.indexOf(QStringLiteral("/player_api.php"));
    if (api > 0) {
        url = url.left(api);
    }
    return url;
}

QNetworkRequest request(const QUrl &url)
{
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Kijkluister"));
    req.setTransferTimeout(60000);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    return req;
}

} // namespace

IptvModel::IptvModel(const QString &dataDir, QObject *parent)
    : QAbstractListModel(parent)
    , m_dataDir(dataDir)
    , m_settings(dataDir + QStringLiteral("/settings.ini"), QSettings::IniFormat)
{
    m_sources = m_settings.value(QStringLiteral("iptv/sources")).toList();
    const QStringList favorites = m_settings.value(QStringLiteral("iptv/favorites")).toStringList();
    m_favorites = QSet<QString>(favorites.begin(), favorites.end());
    m_group = m_favorites.isEmpty() ? allGroup : favoritesGroup;
    loadCache();
    rebuildGroups();
    applyFilter();
    setStatus(m_all.isEmpty() ? QString() : tr("%1 zenders").arg(m_all.size()), false);
}

int IptvModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_visible.size();
}

QVariant IptvModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visible.size()) {
        return {};
    }
    const Channel &c = m_all.at(m_visible.at(index.row()));
    switch (role) {
    case NameRole:
        return m_favorites.contains(c.url) ? QStringLiteral("★ ") + c.name : c.name;
    case IconRole:
        return c.logo;
    case AccentRole:
        return QColor(QStringLiteral("#22252b"));
    case GroupRole:
        return c.group;
    case UrlRole:
        return c.url;
    case FavoriteRole:
        return m_favorites.contains(c.url);
    case NumberRole:
        return index.row() + 1;
    }
    return {};
}

QHash<int, QByteArray> IptvModel::roleNames() const
{
    return {{NameRole, "name"}, {IconRole, "iconSource"}, {AccentRole, "accent"}, {GroupRole, "group"},
            {UrlRole, "url"}, {FavoriteRole, "favorite"}, {NumberRole, "number"}};
}

void IptvModel::setGroup(const QString &group)
{
    if (group == m_group) {
        return;
    }
    m_group = group;
    applyFilter();
    Q_EMIT filterChanged();
}

void IptvModel::setSearch(const QString &search)
{
    if (search == m_search) {
        return;
    }
    m_search = search;
    applyFilter();
    Q_EMIT filterChanged();
}

void IptvModel::applyFilter()
{
    const QString needle = m_search.trimmed();
    QList<int> visible;
    for (int i = 0; i < m_all.size(); ++i) {
        const Channel &c = m_all.at(i);
        if (!needle.isEmpty()) {
            // Zoeken gaat altijd over alle zenders
            if (!c.name.contains(needle, Qt::CaseInsensitive)) {
                continue;
            }
        } else if (m_group == favoritesGroup) {
            if (!m_favorites.contains(c.url)) {
                continue;
            }
        } else if (m_group != allGroup && c.group != m_group) {
            continue;
        }
        visible.append(i);
    }
    beginResetModel();
    m_visible = visible;
    endResetModel();
    Q_EMIT countChanged();
}

void IptvModel::rebuildGroups()
{
    QStringList groups{favoritesGroup, allGroup};
    QSet<QString> seen;
    for (const Channel &c : std::as_const(m_all)) {
        if (!seen.contains(c.group)) {
            seen.insert(c.group);
            groups.append(c.group); // volgorde van de aanbieder aanhouden
        }
    }
    m_groups = groups;
    if (!m_groups.contains(m_group)) {
        m_group = allGroup;
    }
}

bool IptvModel::addSource(const QString &type, const QString &name, const QString &url, const QString &user, const QString &password)
{
    QString target = url.trimmed();
    if (type == QLatin1String("m3u-file") && target.startsWith(QLatin1String("file:"))) {
        target = QUrl(target).toLocalFile();
    }
    if (target.isEmpty() || (type == QLatin1String("xtream") && (user.trimmed().isEmpty() || password.isEmpty()))) {
        return false;
    }
    if (type == QLatin1String("m3u-url") && !target.contains(QStringLiteral("://"))) {
        target.prepend(QStringLiteral("http://"));
    }
    if (type == QLatin1String("m3u-file") && !QFileInfo::exists(target)) {
        return false;
    }
    if (type == QLatin1String("xtream")) {
        target = serverUrl(target);
    }
    QVariantMap source{
        {QStringLiteral("type"), type},
        {QStringLiteral("name"), name.trimmed()},
        {QStringLiteral("url"), target},
        {QStringLiteral("user"), user.trimmed()},
        {QStringLiteral("password"), password},
    };
    if (source.value(QStringLiteral("name")).toString().isEmpty()) {
        source[QStringLiteral("name")] = sourceLabel(source);
    }
    m_sources.append(source);
    m_settings.setValue(QStringLiteral("iptv/sources"), m_sources);
    m_settings.sync();
    Q_EMIT sourcesChanged();
    reload();
    return true;
}

void IptvModel::removeSource(int index)
{
    if (index < 0 || index >= m_sources.size()) {
        return;
    }
    m_sources.removeAt(index);
    m_settings.setValue(QStringLiteral("iptv/sources"), m_sources);
    Q_EMIT sourcesChanged();
    reload();
}

QString IptvModel::sourceLabel(const QVariantMap &source) const
{
    const QString type = source.value(QStringLiteral("type")).toString();
    const QString url = source.value(QStringLiteral("url")).toString();
    if (type == QLatin1String("m3u-file")) {
        return QFileInfo(url).completeBaseName();
    }
    return QUrl(url).host();
}

void IptvModel::reload()
{
    if (m_busy) {
        return;
    }
    m_loading.clear();
    m_errors.clear();
    m_loadIndex = -1;
    if (m_sources.isEmpty()) {
        finishLoading();
        return;
    }
    setStatus(tr("Zenders laden…"), true);
    loadNext();
}

void IptvModel::loadNext()
{
    ++m_loadIndex;
    if (m_loadIndex >= m_sources.size()) {
        finishLoading();
        return;
    }
    const QVariantMap source = m_sources.at(m_loadIndex).toMap();
    const QString type = source.value(QStringLiteral("type")).toString();
    const QString name = source.value(QStringLiteral("name")).toString();
    setStatus(tr("Zenders laden: %1").arg(name), true);

    if (type == QLatin1String("xtream")) {
        loadXtream(source);
        return;
    }
    if (type == QLatin1String("m3u-file")) {
        QFile file(source.value(QStringLiteral("url")).toString());
        if (file.open(QIODevice::ReadOnly)) {
            parseM3u(file.readAll());
        } else {
            m_errors << tr("%1: bestand niet te openen").arg(name);
        }
        QMetaObject::invokeMethod(this, &IptvModel::loadNext, Qt::QueuedConnection);
        return;
    }
    QNetworkReply *reply = m_network.get(request(QUrl(source.value(QStringLiteral("url")).toString())));
    connect(reply, &QNetworkReply::finished, this, [this, reply, name] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            m_errors << tr("%1: %2").arg(name, reply->errorString());
            qWarning().noquote() << "IPTV load failed" << name << reply->errorString();
        } else {
            parseM3u(reply->readAll());
        }
        loadNext();
    });
}

// Leest een M3U-lijst zoals open-tv: #EXTINF-regel met kenmerken, daarna het adres
void IptvModel::parseM3u(const QByteArray &data)
{
    const int before = m_loading.size();
    QString info;
    QString extGroup;
    const QList<QByteArray> lines = data.split('\n');
    for (const QByteArray &raw : lines) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (line.isEmpty()) {
            continue;
        }
        if (line.startsWith(QLatin1String("#EXTINF"), Qt::CaseInsensitive)) {
            info = line;
            extGroup.clear();
            continue;
        }
        if (line.startsWith(QLatin1String("#EXTGRP:"), Qt::CaseInsensitive)) {
            extGroup = line.mid(8).trimmed();
            continue;
        }
        if (line.startsWith(QLatin1Char('#')) || info.isEmpty()) {
            continue;
        }
        QString name = capture(nameAttr, info);
        if (name.isEmpty()) {
            // Naam na de komma, voorbij alle kenmerken (die zelf komma's kunnen bevatten)
            const int lastQuote = info.lastIndexOf(QLatin1Char('"'));
            const int comma = info.indexOf(QLatin1Char(','), lastQuote < 0 ? 0 : lastQuote);
            if (comma >= 0) {
                name = info.mid(comma + 1).trimmed();
            }
        }
        if (name.isEmpty()) {
            name = capture(idAttr, info);
        }
        QString group = capture(groupAttr, info);
        if (group.isEmpty()) {
            group = extGroup.isEmpty() ? otherGroup : extGroup;
        }
        if (!name.isEmpty()) {
            m_loading.append({name, capture(logoAttr, info), group, line});
        }
        info.clear();
    }
    qInfo() << "IPTV: M3U gave" << (m_loading.size() - before) << "channels";
}

void IptvModel::loadXtream(const QVariantMap &source)
{
    const QString server = source.value(QStringLiteral("url")).toString();
    const QString user = source.value(QStringLiteral("user")).toString();
    const QString password = source.value(QStringLiteral("password")).toString();
    const QString name = source.value(QStringLiteral("name")).toString();
    auto apiUrl = [server, user, password](const QString &action) {
        QUrl url(server + QStringLiteral("/player_api.php"));
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("username"), user);
        query.addQueryItem(QStringLiteral("password"), password);
        query.addQueryItem(QStringLiteral("action"), action);
        url.setQuery(query);
        return url;
    };

    QNetworkReply *categories = m_network.get(request(apiUrl(QStringLiteral("get_live_categories"))));
    connect(categories, &QNetworkReply::finished, this, [=, this] {
        categories->deleteLater();
        const QJsonDocument doc = QJsonDocument::fromJson(categories->readAll());
        if (categories->error() != QNetworkReply::NoError || !doc.isArray()) {
            m_errors << tr("%1: inloggen mislukt of server niet bereikbaar").arg(name);
            loadNext();
            return;
        }
        QHash<QString, QString> categoryNames;
        for (const QJsonValue &v : doc.array()) {
            const QJsonObject o = v.toObject();
            categoryNames.insert(o.value(QStringLiteral("category_id")).toVariant().toString(),
                                 o.value(QStringLiteral("category_name")).toString());
        }
        QNetworkReply *streams = m_network.get(request(apiUrl(QStringLiteral("get_live_streams"))));
        connect(streams, &QNetworkReply::finished, this, [=, this] {
            streams->deleteLater();
            const QJsonDocument list = QJsonDocument::fromJson(streams->readAll());
            if (streams->error() != QNetworkReply::NoError || !list.isArray()) {
                m_errors << tr("%1: zenderlijst niet op te halen").arg(name);
                loadNext();
                return;
            }
            for (const QJsonValue &v : list.array()) {
                const QJsonObject o = v.toObject();
                const QString id = o.value(QStringLiteral("stream_id")).toVariant().toString();
                const QString channelName = o.value(QStringLiteral("name")).toString().trimmed();
                if (id.isEmpty() || channelName.isEmpty()) {
                    continue;
                }
                QString group = categoryNames.value(o.value(QStringLiteral("category_id")).toVariant().toString());
                m_loading.append({
                    channelName,
                    o.value(QStringLiteral("stream_icon")).toString(),
                    group.isEmpty() ? otherGroup : group,
                    QStringLiteral("%1/live/%2/%3/%4.ts").arg(server, user, password, id),
                });
            }
            qInfo() << "IPTV: Xtream gave" << list.array().size() << "channels";
            loadNext();
        });
    });
}

void IptvModel::finishLoading()
{
    // Zijn alle bronnen mislukt, dan de vorige lijst houden
    if (!m_loading.isEmpty() || m_errors.isEmpty()) {
        m_all = m_loading;
        saveCache();
    }
    m_loading.clear();
    rebuildGroups();
    applyFilter();
    Q_EMIT channelsChanged();
    Q_EMIT filterChanged();
    QString text = m_sources.isEmpty() ? QString() : tr("%1 zenders").arg(m_all.size());
    if (!m_errors.isEmpty()) {
        text += (text.isEmpty() ? QString() : QStringLiteral("  ·  ")) + m_errors.join(QStringLiteral("  ·  "));
    }
    setStatus(text, false);
}

void IptvModel::toggleFavorite(int row)
{
    if (row < 0 || row >= m_visible.size()) {
        return;
    }
    const QString url = m_all.at(m_visible.at(row)).url;
    if (m_favorites.contains(url)) {
        m_favorites.remove(url);
    } else {
        m_favorites.insert(url);
    }
    m_settings.setValue(QStringLiteral("iptv/favorites"), QStringList(m_favorites.begin(), m_favorites.end()));
    if (m_group == favoritesGroup && m_search.isEmpty()) {
        applyFilter();
    } else {
        Q_EMIT dataChanged(index(row), index(row), {NameRole, FavoriteRole});
    }
}

bool IptvModel::isFavorite(int row) const
{
    return row >= 0 && row < m_visible.size() && m_favorites.contains(m_all.at(m_visible.at(row)).url);
}

QVariantMap IptvModel::channelAt(int row) const
{
    if (row < 0 || row >= m_visible.size()) {
        return {};
    }
    const Channel &c = m_all.at(m_visible.at(row));
    return {{QStringLiteral("name"), c.name}, {QStringLiteral("logo"), c.logo}, {QStringLiteral("group"), c.group},
            {QStringLiteral("url"), c.url}, {QStringLiteral("number"), row + 1}};
}

bool IptvModel::openExternal(int row)
{
    const QString url = channelAt(row).value(QStringLiteral("url")).toString();
    if (url.isEmpty()) {
        return false;
    }
    const QString mpc = mpcHcPath();
    if (QFile::exists(mpc) && QProcess::startDetached(mpc, {url, QStringLiteral("/fullscreen"), QStringLiteral("/play")})) {
        return true;
    }
    return QDesktopServices::openUrl(QUrl(url));
}

QString IptvModel::localPath(const QUrl &url) const
{
    return QDir::toNativeSeparators(url.isLocalFile() ? url.toLocalFile() : url.toString());
}

void IptvModel::saveCache() const
{
    QJsonArray array;
    for (const Channel &c : m_all) {
        array.append(QJsonArray{c.name, c.logo, c.group, c.url});
    }
    QFile file(m_dataDir + QStringLiteral("/iptv-channels.json"));
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(array).toJson(QJsonDocument::Compact));
    }
}

void IptvModel::loadCache()
{
    QFile file(m_dataDir + QStringLiteral("/iptv-channels.json"));
    if (m_sources.isEmpty() || !file.open(QIODevice::ReadOnly)) {
        return;
    }
    for (const QJsonValue &v : QJsonDocument::fromJson(file.readAll()).array()) {
        const QJsonArray a = v.toArray();
        if (a.size() == 4) {
            m_all.append({a.at(0).toString(), a.at(1).toString(), a.at(2).toString(), a.at(3).toString()});
        }
    }
}

void IptvModel::setStatus(const QString &status, bool busy)
{
    m_status = status;
    m_busy = busy;
    Q_EMIT statusChanged();
}
