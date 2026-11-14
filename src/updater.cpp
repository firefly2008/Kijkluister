// SPDX-License-Identifier: GPL-2.0-or-later
#include "updater.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QVersionNumber>

#ifndef KIJKLUISTER_VERSION
#define KIJKLUISTER_VERSION "0.0.0"
#endif

Updater::Updater(QObject *parent)
    : QObject(parent)
{
}

QString Updater::current() const
{
    return QStringLiteral(KIJKLUISTER_VERSION);
}

QString Updater::repo() const
{
    return m_settings.value(QStringLiteral("update/repo"), QStringLiteral("firefly2008/bigscreen-host-windows")).toString();
}

int Updater::compare(const QString &a, const QString &b)
{
    return QVersionNumber::compare(QVersionNumber::fromString(a), QVersionNumber::fromString(b));
}

bool Updater::updateAvailable() const
{
    return !m_latest.isEmpty() && m_asset.isValid() && compare(m_latest, current()) > 0;
}

bool Updater::shouldOffer() const
{
    return updateAvailable() && m_settings.value(QStringLiteral("update/dismissed")).toString() != m_latest;
}

void Updater::dismiss()
{
    m_settings.setValue(QStringLiteral("update/dismissed"), m_latest);
}

void Updater::setStatus(const QString &status, bool busy)
{
    m_status = status;
    m_busy = busy;
    Q_EMIT changed();
}

void Updater::check(bool manual)
{
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const qint64 last = m_settings.value(QStringLiteral("update/lastCheck")).toLongLong();
    if (m_busy) {
        return;
    }
    if (!manual && last > 0 && now - last < 7 * 24 * 3600) {
        // Wel de laatst gevonden versie onthouden, zodat de melding na een herstart blijft
        m_latest = m_settings.value(QStringLiteral("update/latest")).toString();
        m_asset = m_settings.value(QStringLiteral("update/asset")).toUrl();
        m_notes = m_settings.value(QStringLiteral("update/notes")).toString();
        Q_EMIT changed();
        Q_EMIT checked(false);
        return;
    }
    setStatus(tr("Zoeken naar een nieuwe versie…"), true);
    QNetworkRequest request(QUrl(QStringLiteral("https://api.github.com/repos/%1/releases/latest").arg(repo())));
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Kijkluister/") + current());
    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, manual, now] {
        reply->deleteLater();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
        if (reply->error() != QNetworkReply::NoError || o.isEmpty()) {
            qInfo() << "Update check failed" << http << reply->errorString();
            setStatus(http == 404 ? tr("Bijwerken kan nu niet: de downloadplek op GitHub is niet openbaar.")
                                  : tr("Zoeken naar een nieuwe versie lukte niet. Is er internet?"), false);
            Q_EMIT checked(manual);
            return;
        }
        m_settings.setValue(QStringLiteral("update/lastCheck"), now);
        m_latest = o.value(QStringLiteral("tag_name")).toString();
        if (m_latest.startsWith(QLatin1Char('v'))) {
            m_latest.remove(0, 1);
        }
        m_notes = o.value(QStringLiteral("body")).toString().left(600);
        m_asset = QUrl();
        for (const QJsonValue &v : o.value(QStringLiteral("assets")).toArray()) {
            const QString name = v.toObject().value(QStringLiteral("name")).toString();
            if (name.endsWith(QLatin1String("-x64-setup.exe"), Qt::CaseInsensitive)) {
                m_asset = QUrl(v.toObject().value(QStringLiteral("browser_download_url")).toString());
            }
        }
        m_settings.setValue(QStringLiteral("update/latest"), m_latest);
        m_settings.setValue(QStringLiteral("update/asset"), m_asset);
        m_settings.setValue(QStringLiteral("update/notes"), m_notes);
        qInfo() << "Update check: current" << current() << "latest" << m_latest;
        setStatus(updateAvailable() ? tr("Kijkluister %1 is er.").arg(m_latest)
                                    : tr("Je hebt de nieuwste versie (%1).").arg(current()), false);
        Q_EMIT checked(manual);
    });
}

void Updater::install()
{
    if (!updateAvailable() || m_busy) {
        return;
    }
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    const QString file = QDir(dir).filePath(QStringLiteral("Kijkluister-%1-x64-setup.exe").arg(m_latest));
    m_progress = 0;
    setStatus(tr("Kijkluister %1 ophalen…").arg(m_latest), true);
    QNetworkRequest request(m_asset);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_network.get(request);
    auto *out = new QFile(file, reply);
    if (!out->open(QIODevice::WriteOnly)) {
        reply->abort();
        setStatus(tr("Kon de nieuwe versie niet opslaan."), false);
        return;
    }
    connect(reply, &QNetworkReply::readyRead, this, [reply, out] { out->write(reply->readAll()); });
    connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        m_progress = total > 0 ? double(got) / total : 0;
        Q_EMIT changed();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, out, file] {
        reply->deleteLater();
        out->write(reply->readAll());
        out->close();
        if (reply->error() != QNetworkReply::NoError || out->size() < 1000000) {
            qInfo() << "Update download failed" << reply->errorString();
            QFile::remove(file);
            setStatus(tr("Ophalen lukte niet. Probeer het later nog eens."), false);
            return;
        }
        qInfo() << "Update downloaded" << file;
        setStatus(tr("Bijwerken… Kijkluister start zo opnieuw."), true);
        // Installer stil laten lopen; /relaunch=1 start Kijkluister daarna weer (zie bigscreen-host.iss)
        if (QProcess::startDetached(file, {QStringLiteral("/SILENT"), QStringLiteral("/SUPPRESSMSGBOXES"),
                                           QStringLiteral("/NORESTART"), QStringLiteral("/relaunch=1")})) {
            QTimer::singleShot(800, qApp, &QCoreApplication::quit);
        } else {
            setStatus(tr("De installer kon niet starten."), false);
        }
    });
}
