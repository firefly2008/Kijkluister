// Lijst van geinstalleerde toepassingen (Startmenu-snelkoppelingen) plus de
// persoonlijke aanpassingen daarop: verborgen tegels, eigen pictogrammen en de
// achtergrond. Vervangt op Windows de KService/Kicker-lijst en de wallpaper-KCM.
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QSettings>
#include <QString>
#include <QUrl>
#include <QVariantMap>

class AppModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int hiddenCount READ hiddenCount NOTIFY countChanged)
    Q_PROPERTY(QString background READ background NOTIFY backgroundChanged)

public:
    enum Roles { NameRole = Qt::UserRole + 1, PathRole, IconRole, CustomIconRole };

    explicit AppModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_apps.size(); }
    int hiddenCount() const { return m_hidden.size(); }
    QString background() const { return m_background; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool launch(int row);
    Q_INVOKABLE bool openUri(const QString &uri);
    Q_INVOKABLE QString nameAt(int row) const;
    Q_INVOKABLE bool hasCustomIcon(int row) const;

    // Tegels aanpassen
    Q_INVOKABLE void hide(int row);
    Q_INVOKABLE void restoreHidden();
    Q_INVOKABLE bool setCustomIcon(int row, const QUrl &imageFile);
    Q_INVOKABLE void clearCustomIcon(int row);

    // Achtergrond
    Q_INVOKABLE bool setBackground(const QUrl &imageFile);
    Q_INVOKABLE void clearBackground();

Q_SIGNALS:
    void countChanged();
    void backgroundChanged();

private:
    struct App {
        QString name;
        QString path;
    };
    QString importImage(const QUrl &source, const QString &baseName);

    QList<App> m_apps;
    QStringList m_hidden;
    QVariantMap m_customIcons; // pad van snelkoppeling -> file-URL van eigen pictogram
    QString m_background;
    QSettings m_settings;
};
