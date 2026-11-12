// Lijst van geinstalleerde toepassingen (Startmenu-snelkoppelingen).
// Vervangt op Windows de KService/Kicker-app-lijst uit containments/homescreen.
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>

class AppModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles { NameRole = Qt::UserRole + 1, PathRole, IconRole };

    explicit AppModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_apps.size(); }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool launch(int row);
    Q_INVOKABLE bool openUri(const QString &uri);

Q_SIGNALS:
    void countChanged();

private:
    struct App {
        QString name;
        QString path;
    };
    QList<App> m_apps;
};
