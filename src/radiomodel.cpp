// SPDX-License-Identifier: GPL-2.0-or-later
#include "radiomodel.h"

#include <QDir>
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
          QStringLiteral("https://icecast-qmusicnl-cdp.triple-it.nl/Joe_nl.mp3?aw_0_1st.playerId=redirect"),
          QStringLiteral("https://icecast-qmusicnl-cdp.triple-it.nl/Joe_nl_high.aac"),
          QStringLiteral("https://audio-streaming.joe.nl/Joe_nl.mp3")}},
        {QStringLiteral("Radio Veronica"), QStringLiteral("Rock en classics"), QStringLiteral("www.radioveronica.nl"), QStringLiteral("#3b2a7a"),
         {stw + QStringLiteral("VERONICA.mp3"), QStringLiteral("https://stream.radioveronica.nl/veronica")}},
    };
    fetchLogos();
}

int RadioModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_stations.size());
}

QVariant RadioModel::data(const QModelIndex &index, int role) const
{
    const int row = index.row();
    if (!index.isValid() || row < 0 || row >= m_stations.size()) {
        return {};
    }
    switch (role) {
    case NameRole:
        return m_stations.at(row).name;
    case IconRole:
        return iconAt(row);
    case AccentRole:
        return accentAt(row);
    case PathRole:
        return QStringLiteral("radio:") + QString::number(row);
    }
    return {};
}

QHash<int, QByteArray> RadioModel::roleNames() const
{
    return {{NameRole, "name"}, {IconRole, "iconSource"}, {AccentRole, "accent"}, {PathRole, "path"}};
}

QString RadioModel::nameAt(int row) const
{
    return row >= 0 && row < m_stations.size() ? m_stations.at(row).name : QString();
}

QString RadioModel::iconAt(int row) const
{
    const QString file = logoFile(row);
    if (!file.isEmpty() && QFile::exists(file)) {
        return QUrl::fromLocalFile(file).toString();
    }
    return QStringLiteral("glyph:") + QChar(0xE7F6); // radio-pictogram (Segoe Fluent Icons)
}

QString RadioModel::accentAt(int row) const
{
    return row >= 0 && row < m_stations.size() ? m_stations.at(row).accent : QStringLiteral("#22252b");
}

QString RadioModel::subtitleAt(int row) const
{
    return row >= 0 && row < m_stations.size() ? m_stations.at(row).slogan : QString();
}

QStringList RadioModel::streamsAt(int row) const
{
    return row >= 0 && row < m_stations.size() ? m_stations.at(row).streams : QStringList();
}

bool RadioModel::launch(int row)
{
    if (row < 0 || row >= m_stations.size()) {
        return false;
    }
    qInfo() << "Radio" << m_stations.at(row).name;
    Q_EMIT playRequested(row);
    return true;
}

QString RadioModel::logoFile(int row) const
{
    if (row < 0 || row >= m_stations.size()) {
        return {};
    }
    QString id = m_stations.at(row).name.toLower();
    id.replace(QLatin1Char(' '), QLatin1Char('-'));
    return m_dataDir + QStringLiteral("/images/radio-") + id + QStringLiteral(".png");
}

// Logo eenmalig ophalen (pictogram van de site van de zender) en lokaal bewaren
void RadioModel::fetchLogos()
{
    QDir().mkpath(m_dataDir + QStringLiteral("/images"));
    for (int row = 0; row < m_stations.size(); ++row) {
        const QString file = logoFile(row);
        if (QFile::exists(file)) {
            continue;
        }
        QUrl service(QStringLiteral("https://www.google.com/s2/favicons"));
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("sz"), QStringLiteral("128"));
        query.addQueryItem(QStringLiteral("domain"), m_stations.at(row).site);
        service.setQuery(query);
        QNetworkReply *reply = m_network.get(QNetworkRequest(service));
        connect(reply, &QNetworkReply::finished, this, [this, reply, file, row] {
            reply->deleteLater();
            QImage image;
            if (reply->error() != QNetworkReply::NoError || !image.loadFromData(reply->readAll()) || image.width() < 32) {
                qInfo() << "No radio logo for" << nameAt(row);
                return;
            }
            image.save(file, "PNG");
            Q_EMIT dataChanged(index(row), index(row), {IconRole});
            ++m_revision;
            Q_EMIT revisionChanged();
        });
    }
}
