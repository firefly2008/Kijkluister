// SPDX-License-Identifier: GPL-2.0-or-later
#include "radiomodel.h"
#include "paths.h"

#include <QCryptographicHash>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QSettings>
#include <QFile>
#include <QImage>
#include <QNetworkReply>
#include <QUrl>
#include <QUrlQuery>

RadioModel::RadioModel(const QString &dataDir, QObject *parent)
    : QAbstractListModel(parent)
    , m_dataDir(dataDir)
{
    // Volgorde: luistertijdaandeel NMO, januari-juni 2026. Per zender een reserve-adres:
    // gaat het eerste mis, dan probeert de speler het volgende.
    const QString stw = QStringLiteral("https://playerservices.streamtheworld.com/api/livestream-redirect/");
    m_stations = {
        {QStringLiteral("NPO Radio 2"), QStringLiteral("Grootste zender van Nederland"), QStringLiteral("www.nporadio2.nl"), QStringLiteral("#b3261e"),
         {QStringLiteral("https://icecast.omroep.nl/radio2-bb-mp3"), QStringLiteral("https://icecast.omroep.nl/radio2-sb-mp3")}},
        {QStringLiteral("Qmusic"), QStringLiteral("Hits en de Top 40"), QStringLiteral("qmusic.nl"), QStringLiteral("#b8231f"),
         {QStringLiteral("https://icecast-qmusicnl-cdp.triple-it.nl/Qmusic_nl_live.mp3"), QStringLiteral("https://stream.qmusic.nl/qmusic/mp3")}},
        {QStringLiteral("Radio 538"), QStringLiteral("Dance en hits"), QStringLiteral("www.538.nl"), QStringLiteral("#1e3f8a"),
         {stw + QStringLiteral("RADIO538.mp3"), stw + QStringLiteral("TLPSTR01.mp3")}},
        {QStringLiteral("Sky Radio"), QStringLiteral("Non-stop muziek"), QStringLiteral("www.skyradio.nl"), QStringLiteral("#0d5a9e"),
         {stw + QStringLiteral("SKYRADIO.mp3")}},
        {QStringLiteral("Radio 10"), QStringLiteral("Hits van toen"), QStringLiteral("www.radio10.nl"), QStringLiteral("#c2410c"),
         {stw + QStringLiteral("RADIO10.mp3")}},
        {QStringLiteral("JOE"), QStringLiteral("Hits van de jaren 80, 90 en nu"), QStringLiteral("joe.nl"), QStringLiteral("#8a1d3f"),
         {QStringLiteral("https://icecast-qmusicnl-cdp.triple-it.nl/Joe_nl.mp3"),
          QStringLiteral("https://icecast-qmusicnl-cdp.triple-it.nl/Joe_nl_high.aac"),
          QStringLiteral("https://icecast-qmusicnl-cdp.triple-it.nl/Joe_nl.mp3?aw_0_1st.playerId=redirect"),
          QStringLiteral("https://audio-streaming.joe.nl/Joe_nl.mp3")}},
        {QStringLiteral("Radio Veronica"), QStringLiteral("Rock en classics"), QStringLiteral("www.radioveronica.nl"), QStringLiteral("#3b2a7a"),
         {stw + QStringLiteral("VERONICA.mp3"), QStringLiteral("https://stream.radioveronica.nl/veronica")}},
    };
    loadCustom();
    rebuild();
    fetchLogos();
}

void RadioModel::loadCustom()
{
    const QJsonArray list = QJsonDocument::fromJson(QSettings(appSettingsFile(), QSettings::IniFormat).value(QStringLiteral("radio/custom")).toByteArray()).array();
    for (const QJsonValue &v : list) {
        const QJsonObject o = v.toObject();
        Station s;
        s.name = o.value(QStringLiteral("name")).toString();
        s.slogan = o.value(QStringLiteral("slogan")).toString();
        s.site = o.value(QStringLiteral("site")).toString();
        s.accent = o.value(QStringLiteral("accent")).toString(QStringLiteral("#2f3a4a"));
        s.streams = {o.value(QStringLiteral("url")).toString()};
        s.logoUrl = o.value(QStringLiteral("logo")).toString();
        s.custom = true;
        if (!s.name.isEmpty() && !s.streams.first().isEmpty()) {
            m_stations.append(s);
        }
    }
}

void RadioModel::saveCustom() const
{
    QJsonArray list;
    for (const Station &s : m_stations) {
        if (s.custom) {
            list.append(QJsonObject{{QStringLiteral("name"), s.name}, {QStringLiteral("slogan"), s.slogan}, {QStringLiteral("site"), s.site},
                                    {QStringLiteral("accent"), s.accent}, {QStringLiteral("url"), s.streams.value(0)},
                                    {QStringLiteral("logo"), s.logoUrl}});
        }
    }
    QSettings(appSettingsFile(), QSettings::IniFormat).setValue(QStringLiteral("radio/custom"), QJsonDocument(list).toJson(QJsonDocument::Compact));
}

void RadioModel::rebuild()
{
    const QStringList hidden = QSettings(appSettingsFile(), QSettings::IniFormat).value(QStringLiteral("radio/hidden")).toStringList();
    m_visible.clear();
    for (int i = 0; i < m_stations.size(); ++i) {
        if (!hidden.contains(m_stations.at(i).name)) {
            m_visible.append(i);
        }
    }
}

int RadioModel::hiddenCount() const
{
    return int(m_stations.size() - m_visible.size());
}

QString RadioModel::pathAt(int row) const
{
    return isAddTile(row) ? QStringLiteral("radio:add") : QStringLiteral("radio:") + nameAt(row);
}

int RadioModel::rowOfName(const QString &name) const
{
    for (int row = 0; row < count(); ++row) {
        if (st(row).name.compare(name, Qt::CaseInsensitive) == 0) {
            return row;
        }
    }
    return -1;
}

void RadioModel::remove(int row)
{
    if (row < 0 || row >= count()) {
        return;
    }
    beginResetModel();
    const int index = m_visible.at(row);
    if (m_stations.at(index).custom) {
        m_stations.removeAt(index);
        saveCustom();
    } else {
        QSettings settings(appSettingsFile(), QSettings::IniFormat);
        QStringList hidden = settings.value(QStringLiteral("radio/hidden")).toStringList();
        hidden.append(m_stations.at(index).name);
        settings.setValue(QStringLiteral("radio/hidden"), hidden);
    }
    rebuild();
    endResetModel();
    Q_EMIT countChanged();
    ++m_revision;
    Q_EMIT revisionChanged();
}

void RadioModel::restoreHidden()
{
    beginResetModel();
    QSettings(appSettingsFile(), QSettings::IniFormat).remove(QStringLiteral("radio/hidden"));
    rebuild();
    endResetModel();
    Q_EMIT countChanged();
}

void RadioModel::searchStations(const QString &query)
{
    const QString q = query.trimmed();
    if (q.isEmpty()) {
        m_results.clear();
        Q_EMIT resultsChanged();
        return;
    }
    QUrl url(QStringLiteral("https://all.api.radio-browser.info/json/stations/search"));
    QUrlQuery params;
    params.addQueryItem(QStringLiteral("name"), q);
    params.addQueryItem(QStringLiteral("limit"), QStringLiteral("40"));
    params.addQueryItem(QStringLiteral("hidebroken"), QStringLiteral("true"));
    params.addQueryItem(QStringLiteral("order"), QStringLiteral("clickcount"));
    params.addQueryItem(QStringLiteral("reverse"), QStringLiteral("true"));
    url.setQuery(params);
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Kijkluister"));
    m_searching = true;
    Q_EMIT resultsChanged();
    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, q] {
        reply->deleteLater();
        m_searching = false;
        m_results.clear();
        const QJsonArray list = QJsonDocument::fromJson(reply->readAll()).array();
        QSet<QString> seen;
        for (const QJsonValue &v : list) {
            const QJsonObject o = v.toObject();
            const QString streamUrl = o.value(QStringLiteral("url_resolved")).toString(o.value(QStringLiteral("url")).toString());
            const QString name = o.value(QStringLiteral("name")).toString().trimmed();
            if (streamUrl.isEmpty() || name.isEmpty() || seen.contains(name.toLower())) {
                continue;
            }
            seen.insert(name.toLower());
            QStringList detail{o.value(QStringLiteral("country")).toString()};
            const QString tags = o.value(QStringLiteral("tags")).toString().section(QLatin1Char(','), 0, 2).replace(QLatin1Char(','), QStringLiteral(", "));
            if (!tags.isEmpty()) {
                detail.append(tags);
            }
            detail.removeAll(QString());
            m_results.append(QVariantMap{
                {QStringLiteral("name"), name},
                {QStringLiteral("detail"), detail.join(QStringLiteral(" · "))},
                {QStringLiteral("url"), streamUrl},
                {QStringLiteral("logo"), o.value(QStringLiteral("favicon")).toString()},
                {QStringLiteral("site"), QUrl(o.value(QStringLiteral("homepage")).toString()).host()},
            });
        }
        qInfo() << "Radio search" << q << m_results.size();
        Q_EMIT resultsChanged();
    });
}

bool RadioModel::hasResult(int index) const
{
    if (index < 0 || index >= m_results.size()) {
        return false;
    }
    const QString url = m_results.at(index).toMap().value(QStringLiteral("url")).toString();
    for (const Station &s : m_stations) {
        if (s.streams.contains(url)) {
            return true;
        }
    }
    return false;
}

bool RadioModel::addResult(int index)
{
    if (index < 0 || index >= m_results.size() || hasResult(index)) {
        return false;
    }
    const QVariantMap r = m_results.at(index).toMap();
    Station s;
    s.name = r.value(QStringLiteral("name")).toString();
    s.slogan = r.value(QStringLiteral("detail")).toString();
    s.site = r.value(QStringLiteral("site")).toString();
    s.streams = {r.value(QStringLiteral("url")).toString()};
    s.logoUrl = r.value(QStringLiteral("logo")).toString();
    static const QStringList accents{QStringLiteral("#2f4a6b"), QStringLiteral("#5b2f6b"), QStringLiteral("#2f6b55"),
                                     QStringLiteral("#6b4a2f"), QStringLiteral("#6b2f3a"), QStringLiteral("#3a3f6b")};
    s.accent = accents.at(qHash(s.name) % accents.size());
    s.custom = true;
    beginResetModel();
    m_stations.append(s);
    rebuild();
    endResetModel();
    saveCustom();
    Q_EMIT countChanged();
    qInfo() << "Radio added" << s.name << s.streams.first();
    fetchLogos();
    return true;
}

int RadioModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : count() + 1;   // + tegel "Zender toevoegen"
}

QVariant RadioModel::data(const QModelIndex &index, int role) const
{
    const int row = index.row();
    if (!index.isValid() || row < 0 || row > count()) {
        return {};
    }
    switch (role) {
    case NameRole:
        return isAddTile(row) ? tr("Zender toevoegen") : st(row).name;
    case IconRole:
        return iconAt(row);
    case AccentRole:
        return accentAt(row);
    case PathRole:
        return pathAt(row);
    }
    return {};
}

QHash<int, QByteArray> RadioModel::roleNames() const
{
    return {{NameRole, "name"}, {IconRole, "iconSource"}, {AccentRole, "accent"}, {PathRole, "path"}};
}

QString RadioModel::nameAt(int row) const
{
    if (isAddTile(row)) {
        return tr("Zender toevoegen");
    }
    return row >= 0 && row < count() ? st(row).name : QString();
}

QString RadioModel::iconAt(int row) const
{
    if (isAddTile(row)) {
        return QStringLiteral("glyph:") + QChar(0xE710);   // plus
    }
    const QString file = logoFile(row);
    if (!file.isEmpty() && QFile::exists(file)) {
        return QUrl::fromLocalFile(file).toString();
    }
    return QStringLiteral("glyph:") + QChar(0xE7F6); // radio-pictogram (Segoe Fluent Icons)
}

QString RadioModel::accentAt(int row) const
{
    return row >= 0 && row < count() ? st(row).accent : QStringLiteral("#2b2e35");
}

QString RadioModel::subtitleAt(int row) const
{
    if (isAddTile(row)) {
        return tr("Zoek tussen ruim 40.000 zenders");
    }
    return row >= 0 && row < count() ? st(row).slogan : QString();
}

QStringList RadioModel::streamsAt(int row) const
{
    return row >= 0 && row < count() ? st(row).streams : QStringList();
}

bool RadioModel::launch(int row)
{
    if (isAddTile(row)) {
        Q_EMIT addRequested();
        return true;
    }
    if (row < 0 || row >= count()) {
        return false;
    }
    qInfo() << "Radio" << st(row).name;
    Q_EMIT playRequested(row);
    return true;
}

QString RadioModel::logoFile(int row) const
{
    if (row < 0 || row >= count()) {
        return {};
    }
    return logoFileFor(st(row));
}

QString RadioModel::logoFileFor(const Station &s) const
{
    QString id = s.name.toLower();
    if (s.custom) {
        id = QString::fromLatin1(QCryptographicHash::hash(s.streams.value(0).toUtf8(), QCryptographicHash::Md5).toHex().left(12));
    }
    id.replace(QLatin1Char(' '), QLatin1Char('-'));
    return m_dataDir + QStringLiteral("/images/radio-") + id + QStringLiteral(".png");
}

// Logo eenmalig ophalen (pictogram van de site van de zender) en lokaal bewaren
void RadioModel::fetchLogos()
{
    QDir().mkpath(m_dataDir + QStringLiteral("/images"));
    for (const Station &station : std::as_const(m_stations)) {
        const QString file = logoFileFor(station);
        if (QFile::exists(file)) {
            continue;
        }
        QUrl source;
        if (station.custom && station.logoUrl.startsWith(QLatin1String("http"))) {
            source = QUrl(station.logoUrl);
        } else if (!station.site.isEmpty()) {
            source = QUrl(QStringLiteral("https://www.google.com/s2/favicons"));
            QUrlQuery query;
            query.addQueryItem(QStringLiteral("sz"), QStringLiteral("128"));
            query.addQueryItem(QStringLiteral("domain"), station.site);
            source.setQuery(query);
        } else {
            continue;
        }
        QNetworkRequest request(source);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply *reply = m_network.get(request);
        const QString name = station.name;
        connect(reply, &QNetworkReply::finished, this, [this, reply, file, name] {
            reply->deleteLater();
            QImage image;
            if (reply->error() != QNetworkReply::NoError || !image.loadFromData(reply->readAll()) || image.width() < 32) {
                qInfo() << "No radio logo for" << name;
                return;
            }
            image.save(file, "PNG");
            const int row = rowOfName(name);
            if (row >= 0) {
                Q_EMIT dataChanged(index(row), index(row), {IconRole});
            }
            ++m_revision;
            Q_EMIT revisionChanged();
        });
    }
}
