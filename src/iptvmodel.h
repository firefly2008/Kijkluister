// Live tv (IPTV): zenders uit M3U-afspeellijsten (link of bestand) en Xtream
// Codes-accounts, met groepen, favorieten en zoeken.
//
// Gebaseerd op open-tv van Fredolx (https://github.com/Fredolx/open-tv, GPL-2.0):
// dezelfde manier van M3U-regels lezen (tvg-name, tvg-id, tvg-logo, group-title,
// naam na de komma) en dezelfde Xtream-aanroepen (player_api.php, get_live_categories,
// get_live_streams, stream-adres server/live/gebruiker/wachtwoord/id.ts).
// open-tv speelt af met mpv; hier gebeurt dat in Bigscreen zelf (Qt Multimedia).
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QColor>
#include <QNetworkAccessManager>
#include <QSet>
#include <QSettings>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

class IptvModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY channelsChanged)
    Q_PROPERTY(QStringList groups READ groups NOTIFY channelsChanged)
    Q_PROPERTY(QString group READ group WRITE setGroup NOTIFY filterChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY filterChanged)
    Q_PROPERTY(QVariantList sources READ sources NOTIFY sourcesChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)

public:
    enum Roles { NameRole = Qt::UserRole + 1, IconRole, AccentRole, GroupRole, UrlRole, FavoriteRole, NumberRole };

    IptvModel(const QString &dataDir, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_visible.size(); }
    int totalCount() const { return m_all.size(); }
    QStringList groups() const { return m_groups; }
    QString group() const { return m_group; }
    void setGroup(const QString &group);
    QString search() const { return m_search; }
    void setSearch(const QString &search);
    QVariantList sources() const { return m_sources; }
    bool busy() const { return m_busy; }
    QString status() const { return m_status; }

    // type: "m3u-url", "m3u-file" of "xtream"
    Q_INVOKABLE bool addSource(const QString &type, const QString &name, const QString &url,
                               const QString &user, const QString &password);
    Q_INVOKABLE void removeSource(int index);
    Q_INVOKABLE void reload();
    Q_INVOKABLE void toggleFavorite(int row);
    Q_INVOKABLE bool isFavorite(int row) const;
    Q_INVOKABLE QVariantMap channelAt(int row) const;
    Q_INVOKABLE bool openExternal(int row);
    Q_INVOKABLE QString localPath(const QUrl &url) const;

Q_SIGNALS:
    void countChanged();
    void channelsChanged();
    void filterChanged();
    void sourcesChanged();
    void statusChanged();

private:
    struct Channel {
        QString name;
        QString logo;
        QString group;
        QString url;
    };

    void loadNext();
    void finishLoading();
    void parseM3u(const QByteArray &data);
    void loadXtream(const QVariantMap &source);
    void applyFilter();
    void rebuildGroups();
    void saveCache() const;
    void loadCache();
    void setStatus(const QString &status, bool busy);
    QString sourceLabel(const QVariantMap &source) const;

    QString m_dataDir;
    QSettings m_settings;
    QNetworkAccessManager m_network;
    QVariantList m_sources;
    QList<Channel> m_all;
    QList<Channel> m_loading;
    QList<int> m_visible;
    QStringList m_groups;
    QSet<QString> m_favorites;
    QString m_group;
    QString m_search;
    int m_loadIndex = -1;
    QStringList m_errors;
    bool m_busy = false;
    QString m_status;
};
