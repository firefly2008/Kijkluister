// SPDX-License-Identifier: GPL-2.0-or-later
#include "parental.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QRandomGenerator>
#include <QRegularExpression>

Parental::Parental(QObject *parent)
    : QObject(parent)
{
}

QString Parental::hash(const QString &pin) const
{
    QString salt = m_settings.value(QStringLiteral("parental/salt")).toString();
    return QString::fromLatin1(QCryptographicHash::hash((salt + QLatin1Char(':') + pin).toUtf8(), QCryptographicHash::Sha256).toHex());
}

bool Parental::unlocked() const
{
    return QDateTime::currentSecsSinceEpoch() < m_unlockedUntil;
}

bool Parental::setPin(const QString &pin)
{
    static const QRegularExpression digits(QStringLiteral("^\\d{4}$"));
    if (!digits.match(pin).hasMatch()) {
        return false;
    }
    const bool first = !enabled();
    m_settings.setValue(QStringLiteral("parental/salt"), QString::number(QRandomGenerator::global()->generate64(), 36));
    m_settings.setValue(QStringLiteral("parental/pin"), hash(pin));
    if (first && !m_settings.contains(QStringLiteral("parental/locked"))) {
        m_settings.setValue(QStringLiteral("parental/locked"), QStringList{QStringLiteral("bigscreen:iptv"), QStringLiteral("bigscreen:movies"), QStringLiteral("bigscreen:shows")});
    }
    m_unlockedUntil = 0;
    qInfo() << "Parental: pin set";
    Q_EMIT changed();
    return true;
}

bool Parental::check(const QString &pin)
{
    if (!enabled()) {
        return true;
    }
    if (hash(pin) != m_settings.value(QStringLiteral("parental/pin")).toString()) {
        qInfo() << "Parental: wrong pin";
        return false;
    }
    m_unlockedUntil = QDateTime::currentSecsSinceEpoch() + 3600;
    qInfo() << "Parental: unlocked";
    Q_EMIT changed();
    return true;
}

bool Parental::disable(const QString &pin)
{
    if (!check(pin)) {
        return false;
    }
    m_settings.remove(QStringLiteral("parental/pin"));
    m_settings.remove(QStringLiteral("parental/salt"));
    qInfo() << "Parental: disabled";
    Q_EMIT changed();
    return true;
}

void Parental::lockNow()
{
    m_unlockedUntil = 0;
    Q_EMIT changed();
}

bool Parental::isLocked(const QString &path) const
{
    return !path.isEmpty() && locked().contains(path);
}

void Parental::setLocked(const QString &path, bool on)
{
    QStringList list = locked();
    list.removeAll(path);
    if (on) {
        list.append(path);
    }
    m_settings.setValue(QStringLiteral("parental/locked"), list);
    Q_EMIT changed();
}

bool Parental::isAdultChannel(const QString &group, const QString &name) const
{
    static const QRegularExpression adult(QStringLiteral("(?<!\\w)(xxx|adult|adults|18\\+|porn|erotic|erotiek|playboy|hustler|brazzers|private tv)(?!\\w)"),
                                          QRegularExpression::CaseInsensitiveOption);
    return adult.match(group).hasMatch() || adult.match(name).hasMatch();
}
