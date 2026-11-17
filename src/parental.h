// Kinderslot: tegels (apps, Live tv, Films, Series) en zendergroepen voor volwassenen
// alleen openen met een eigen pincode. Na het juiste getal blijft alles een uur open.
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QObject>
#include "paths.h"
#include <QSettings>
#include <QStringList>

class Parental : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
    Q_PROPERTY(bool unlocked READ unlocked NOTIFY changed)
    Q_PROPERTY(QStringList locked READ locked NOTIFY changed)

public:
    explicit Parental(QObject *parent = nullptr);

    bool enabled() const { return !m_settings.value(QStringLiteral("parental/pin")).toString().isEmpty(); }
    bool unlocked() const;
    QStringList locked() const { return m_settings.value(QStringLiteral("parental/locked")).toStringList(); }

    // Seconden dat de pincode niet geprobeerd kan worden (na 5 foute pogingen)
    Q_INVOKABLE int waitSeconds() const;
    // Pincode instellen (4 cijfers). Bestaande tegels Live tv/Films/Series worden standaard vergrendeld.
    Q_INVOKABLE bool setPin(const QString &pin);
    Q_INVOKABLE bool check(const QString &pin);     // goed: een uur ontgrendeld
    Q_INVOKABLE bool disable(const QString &pin);   // kinderslot helemaal uit
    Q_INVOKABLE void lockNow();
    Q_INVOKABLE bool isLocked(const QString &path) const;    // vraagt deze tegel om de pincode?
    // Kinderprofiel: vergrendelde tegels vragen altijd de pincode (ook binnen het uur)
    Q_INVOKABLE bool needsPin(const QString &path) const { return enabled() && (m_kids || !unlocked()) && isLocked(path); }
    void setKids(bool kids) { m_kids = kids; }
    Q_INVOKABLE void setLocked(const QString &path, bool on);
    // Zendergroep of zendernaam voor volwassenen (altijd vergrendeld als het kinderslot aan staat)
    Q_INVOKABLE bool isAdultChannel(const QString &group, const QString &name) const;

Q_SIGNALS:
    void changed();

private:
    QString hash(const QString &pin) const;
    QSettings m_settings{appSettingsFile(), QSettings::IniFormat};
    qint64 m_unlockedUntil = 0;
    bool m_kids = false;
};
