// Radio: de zeven populairste Nederlandse radiozenders (NMO luisteronderzoek, 1e helft 2026).
// Zelfde rollen en functies als AppModel, zodat de rij op het startscherm gewoon werkt.
// Afspelen gebeurt in Kijkluister zelf (RadioPlayer.qml, Qt Multimedia).
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QStringList>

class RadioModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)            // zenders (zonder de tegel "Zender toevoegen")
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY resultsChanged)
    Q_PROPERTY(int hiddenCount READ hiddenCount NOTIFY countChanged)

public:
    enum Roles { NameRole = Qt::UserRole + 1, IconRole, AccentRole, PathRole };

    explicit RadioModel(const QString &dataDir, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_visible.size()); }
    QVariantList results() const { return m_results; }
    bool searching() const { return m_searching; }
    int hiddenCount() const;
    int revision() const { return m_revision; }

    Q_INVOKABLE QString nameAt(int row) const;
    Q_INVOKABLE QString iconAt(int row) const;
    Q_INVOKABLE QString accentAt(int row) const;
    Q_INVOKABLE QString subtitleAt(int row) const;
    Q_INVOKABLE QStringList streamsAt(int row) const;
    Q_INVOKABLE bool hasCustomIcon(int) const { return false; }
    Q_INVOKABLE void move(int, int) {}
    // Vraagt de speler om deze zender te starten (playRequested); laatste tegel: addRequested
    Q_INVOKABLE bool launch(int row);
    Q_INVOKABLE bool isAddTile(int row) const { return row == count(); }
    Q_INVOKABLE QString pathAt(int row) const;
    Q_INVOKABLE int rowOfName(const QString &name) const;
    // Zoeken in Radio Browser (radio-browser.info, ruim 40.000 zenders)
    Q_INVOKABLE void searchStations(const QString &query);
    Q_INVOKABLE bool addResult(int index);
    Q_INVOKABLE bool hasResult(int index) const;
    Q_INVOKABLE void remove(int row);
    Q_INVOKABLE void restoreHidden();

Q_SIGNALS:
    void revisionChanged();
    void countChanged();
    void resultsChanged();
    void playRequested(int row);
    void addRequested();

private:
    struct Station {
        QString name;
        QString slogan;
        QString site;      // voor het logo
        QString accent;
        QStringList streams;
        bool custom = false;
        QString logoUrl;     // eigen zender: logo uit Radio Browser
    };
    const Station &st(int row) const { return m_stations.at(m_visible.at(row)); }
    QString logoFile(int row) const;
    QString logoFileFor(const Station &s) const;
    void fetchLogos();
    void loadCustom();
    void saveCustom() const;
    void rebuild();

    QString m_dataDir;
    QList<Station> m_stations;
    QList<int> m_visible;
    QVariantList m_results;
    bool m_searching = false;
    QNetworkAccessManager m_network;
    int m_revision = 0;
};
