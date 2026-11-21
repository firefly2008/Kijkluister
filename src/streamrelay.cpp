// SPDX-License-Identifier: GPL-2.0-or-later
#include "streamrelay.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFileInfo>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QUdpSocket>

#include "components.h"

namespace {
quint16 freePort()
{
    QUdpSocket socket;
    if (socket.bind(QHostAddress::LocalHost, 0)) {
        return socket.localPort();
    }
    return quint16(49000 + QRandomGenerator::global()->bounded(2000));
}

QString findFfmpeg()
{
    if (Components *c = Components::instance()) {
        const QString fetched = c->executable(Components::Ffmpeg);
        if (!fetched.isEmpty()) {
            return fetched;
        }
    }
    const QString local = QCoreApplication::applicationDirPath() + QStringLiteral("/ffmpeg/ffmpeg.exe");
    if (QFileInfo::exists(local)) {
        return local;
    }
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
}
}

StreamRelay::StreamRelay(QObject *parent)
    : QObject(parent)
{
}

StreamRelay::~StreamRelay()
{
    stop();
}

bool StreamRelay::running() const
{
    return m_process && m_process->state() != QProcess::NotRunning;
}

QString StreamRelay::start(const QString &url)
{
    stop();
    const QString ffmpeg = findFfmpeg();
    if (ffmpeg.isEmpty() || url.isEmpty()) {
        return {};
    }
    const QString relay = QStringLiteral("udp://127.0.0.1:%1").arg(freePort());
    const QString target = relay + QStringLiteral("?pkt_size=1316&localport=") + QString::number(freePort());
    const QStringList args{
        QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"), QStringLiteral("warning"),
        QStringLiteral("-user_agent"), QStringLiteral("VLC/3.0.9 LibVLC/3.0.9"),
        QStringLiteral("-reconnect"), QStringLiteral("1"), QStringLiteral("-reconnect_streamed"), QStringLiteral("1"),
        QStringLiteral("-reconnect_delay_max"), QStringLiteral("10"),
        QStringLiteral("-rw_timeout"), QStringLiteral("20000000"),
        QStringLiteral("-i"), url,
        QStringLiteral("-map"), QStringLiteral("0:v?"), QStringLiteral("-map"), QStringLiteral("0:a?"),
        QStringLiteral("-c"), QStringLiteral("copy"),
        QStringLiteral("-f"), QStringLiteral("fifo"), QStringLiteral("-fifo_format"), QStringLiteral("mpegts"),
        QStringLiteral("-drop_pkts_on_overflow"), QStringLiteral("1"),
        QStringLiteral("-attempt_recovery"), QStringLiteral("1"), QStringLiteral("-recover_any_error"), QStringLiteral("1"),
        QStringLiteral("-recovery_wait_time"), QStringLiteral("1"),
        target,
    };
    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    m_process->start(ffmpeg, args);
    if (!m_process->waitForStarted(5000)) {
        qWarning() << "StreamRelay: ffmpeg did not start";
        stop();
        return {};
    }
    qInfo() << "StreamRelay: started";
    return relay + QStringLiteral("?overrun_nonfatal=1&fifo_size=1000000&timeout=15000000");
}

void StreamRelay::stop()
{
    if (!m_process) {
        return;
    }
    m_process->disconnect(this);
    if (m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(2000);
    }
    m_process->deleteLater();
    m_process = nullptr;
}
