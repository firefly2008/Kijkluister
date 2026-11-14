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
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    enum Roles { NameRole = Qt::UserRole + 1, IconRole, AccentRole, PathRole };

    explicit RadioModel(const QString &dataDir, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_stations.size()); }
    int revision() const { return m_revision; }

    Q_INVOKABLE QString nameAt(int row) const;
    Q_INVOKABLE QString iconAt(int row) const;
    Q_INVOKABLE QString accentAt(int row) const;
    Q_INVOKABLE QString subtitleAt(int row) const;
    Q_INVOKABLE QStringList streamsAt(int row) const;
    Q_INVOKABLE bool hasCustomIcon(int) const { return false; }
    Q_INVOKABLE void move(int, int) {}
    // Vraagt de speler om deze zender te starten (playRequested)
    Q_INVOKABLE bool launch(int row);

Q_SIGNALS:
    void revisionChanged();
    void playRequested(int row);

private:
    struct Station {
        QString name;
        QString slogan;
        QString site;      // voor het logo
        QString accent;
        QStringList streams;
    };
    QString logoFile(int row) const;
    void fetchLogos();

    QString m_dataDir;
    QList<Station> m_stations;
    QNetworkAccessManager m_network;
    int m_revision = 0;
};
