// SPDX-License-Identifier: GPL-2.0-or-later
#include "recorder.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

#include "appmodel.h" // mpcHcPath()

namespace {
QString sanitize(QString name)
{
    static const QString forbidden = QStringLiteral("<>:\"/\\|?*");
    for (QChar &c : name) {
        if (forbidden.contains(c) || c.unicode() < 32) {
            c = QLatin1Char('_');
        }
    }
    return name.simplified().left(80);
}
}

Recorder::Recorder(const QString &dataDir, QObject *parent)
    : QObject(parent)
    , m_settings(dataDir + QStringLiteral("/settings.ini"), QSettings::IniFormat)
{
    m_folder = m_settings.value(QStringLiteral("recorder/folder")).toString();
    m_clock.setInterval(1000);
    connect(&m_clock, &QTimer::timeout, this, &Recorder::tick);
    m_retryTimer.setSingleShot(true);
    connect(&m_retryTimer, &QTimer::timeout, this, &Recorder::launch);
    m_endTimer.setSingleShot(true);
    connect(&m_endTimer, &QTimer::timeout, this, &Recorder::stop);
}

Recorder::~Recorder()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        // Afsluiten van Kijkluister: ffmpeg netjes laten eindigen
        m_process->write("q\n");
        m_process->closeWriteChannel();
        m_process->waitForFinished(5000);
        if (m_process->state() != QProcess::NotRunning) {
            m_process->kill();
        }
    }
}

QString Recorder::ffmpegPath() const
{
    const QString local = QCoreApplication::applicationDirPath() + QStringLiteral("/ffmpeg/ffmpeg.exe");
    if (QFileInfo::exists(local)) {
        return local;
    }
    const QString onPath = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    return onPath;
}

bool Recorder::available() const
{
    return !ffmpegPath().isEmpty();
}

QString Recorder::defaultFolder() const
{
    const QString videos = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    return QDir::toNativeSeparators((videos.isEmpty() ? QDir::homePath() : videos) + QStringLiteral("/Kijkluister opnames"));
}

void Recorder::setFolder(const QString &folder)
{
    const QString native = QDir::toNativeSeparators(folder.trimmed());
    if (native == m_folder) {
        return;
    }
    m_folder = native;
    m_settings.setValue(QStringLiteral("recorder/folder"), m_folder);
    m_settings.sync();
    Q_EMIT folderChanged();
    refresh();
}

QString Recorder::localPath(const QUrl &url) const
{
    return QDir::toNativeSeparators(url.isLocalFile() ? url.toLocalFile() : url.toString());
}

void Recorder::setStatus(const QString &status)
{
    m_status = status;
    Q_EMIT stateChanged();
}

bool Recorder::start(const QString &channel, const QString &url, int minutes)
{
    if (m_active) {
        setStatus(tr("Er loopt al een opname"));
        return false;
    }
    if (ffmpegPath().isEmpty()) {
        setStatus(tr("ffmpeg niet gevonden"));
        return false;
    }
    if (m_folder.isEmpty()) {
        setFolder(defaultFolder());
    }
    if (!QDir().mkpath(m_folder)) {
        setStatus(tr("Map %1 kan niet worden gemaakt").arg(m_folder));
        return false;
    }
    m_channel = channel;
    m_url = url;
    m_started = QDateTime::currentDateTime();
    m_endAt = minutes > 0 ? m_started.addSecs(minutes * 60) : QDateTime();
    m_retries = 0;
    m_part = 0;
    m_parts.clear();
    m_stopping = false;
    m_active = true;
    m_file = QDir::toNativeSeparators(m_folder + QLatin1Char('/') + sanitize(channel) + QStringLiteral(" - ")
                                      + m_started.toString(QStringLiteral("yyyy-MM-dd HH.mm.ss")) + QStringLiteral(".mp4"));
    if (minutes > 0) {
        m_endTimer.start(minutes * 60 * 1000);
    }
    m_clock.start();
    qInfo().noquote() << "Recorder: start" << channel << "->" << m_file << "minutes" << minutes;
    launch();
    return true;
}

void Recorder::launch()
{
    if (!m_active || m_stopping) {
        return;
    }
    delete m_process;
    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    connect(m_process, &QProcess::finished, this, &Recorder::onFinished);
    connect(m_process, &QProcess::readyReadStandardError, this, [this] {
        m_lastStderr += m_process->readAllStandardError();
        if (m_lastStderr.size() > 4000) {
            m_lastStderr = m_lastStderr.right(2000);
        }
    });
    // Na een onderbreking een nieuw deelbestand, zodat het eerste deel bruikbaar blijft
    QString target = m_file;
    if (m_part > 0) {
        target = m_file.left(m_file.size() - 4) + QStringLiteral(" (deel %1).mp4").arg(m_part + 1);
    }
    if (!m_parts.contains(target)) {
        m_parts << target;
    }
    // Zelfde opzet als IPTV-Recorder: niets hercoderen, alleen kopiëren naar MP4.
    // -movflags: ook een afspeelbaar bestand als de stroom onverwacht stopt.
    const QStringList args{
        QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"), QStringLiteral("warning"), QStringLiteral("-y"),
        QStringLiteral("-user_agent"), QStringLiteral("VLC/3.0.9 LibVLC/3.0.9"),
        QStringLiteral("-reconnect"), QStringLiteral("1"), QStringLiteral("-reconnect_streamed"), QStringLiteral("1"),
        QStringLiteral("-reconnect_delay_max"), QStringLiteral("10"),
        QStringLiteral("-rw_timeout"), QStringLiteral("20000000"),
        QStringLiteral("-i"), m_url,
        QStringLiteral("-map"), QStringLiteral("0:v?"), QStringLiteral("-map"), QStringLiteral("0:a?"),
        QStringLiteral("-c"), QStringLiteral("copy"),
        QStringLiteral("-bsf:a"), QStringLiteral("aac_adtstoasc"),
        QStringLiteral("-movflags"), QStringLiteral("+frag_keyframe+empty_moov+default_base_moof"),
        QStringLiteral("-f"), QStringLiteral("mp4"),
        target,
    };
    m_lastStderr.clear();
    setStatus(m_part > 0 ? tr("Opname hervat (deel %1)").arg(m_part + 1) : tr("Opname loopt"));
    m_process->start(ffmpegPath(), args);
    if (!m_process->waitForStarted(5000)) {
        qWarning() << "Recorder: ffmpeg did not start" << m_process->errorString();
        m_active = false;
        m_clock.stop();
        m_endTimer.stop();
        setStatus(tr("ffmpeg kon niet starten"));
        Q_EMIT finished(m_file, false);
    }
}

void Recorder::onFinished(int code, QProcess::ExitStatus status)
{
    Q_UNUSED(status)
    const QString err = QString::fromUtf8(m_lastStderr).simplified().right(300);
    qInfo().noquote() << "Recorder: ffmpeg exited" << code << (err.isEmpty() ? QString() : QStringLiteral("stderr: ") + err);
    refresh();
    if (!m_active) {
        return;
    }
    if (m_stopping || (m_endAt.isValid() && QDateTime::currentDateTime() >= m_endAt)) {
        m_active = false;
        m_stopping = false;
        m_clock.stop();
        m_endTimer.stop();
        setStatus(tr("Opname opgeslagen"));
        Q_EMIT finished(m_file, true);
        return;
    }
    // Stream viel weg: net als IPTV-Recorder opnieuw proberen, met korte tussenpozen
    ++m_retries;
    ++m_part;
    if (m_retries > 60) {
        m_active = false;
        m_clock.stop();
        m_endTimer.stop();
        setStatus(tr("Opname gestopt: de zender blijft wegvallen"));
        Q_EMIT finished(m_file, !m_parts.isEmpty());
        return;
    }
    setStatus(tr("Zender weggevallen, opnieuw proberen (%1)…").arg(m_retries));
    m_retryTimer.start(5000);
}

void Recorder::stop()
{
    if (!m_active) {
        return;
    }
    m_stopping = true;
    m_endTimer.stop();
    m_retryTimer.stop();
    if (m_process && m_process->state() != QProcess::NotRunning) {
        setStatus(tr("Opname afronden…"));
        m_process->write("q\n");   // netjes afsluiten, zoals IPTV-Recorder doet
        QTimer::singleShot(15000, this, [this] {
            if (m_process && m_process->state() != QProcess::NotRunning) {
                m_process->kill();
            }
        });
    } else {
        onFinished(0, QProcess::NormalExit);
    }
}

int Recorder::elapsedSeconds() const
{
    return m_active ? int(m_started.secsTo(QDateTime::currentDateTime())) : 0;
}

int Recorder::remainingSeconds() const
{
    return m_active && m_endAt.isValid() ? int(qMax<qint64>(0, QDateTime::currentDateTime().secsTo(m_endAt))) : -1;
}

qint64 Recorder::bytes() const
{
    qint64 total = 0;
    for (const QString &part : m_parts) {
        total += QFileInfo(part).size();
    }
    return total;
}

QVariantList Recorder::recordings() const
{
    QVariantList list;
    if (m_folder.isEmpty()) {
        return list;
    }
    const QFileInfoList files = QDir(m_folder).entryInfoList({QStringLiteral("*.mp4"), QStringLiteral("*.ts"), QStringLiteral("*.mkv")},
                                                            QDir::Files, QDir::Time);
    for (const QFileInfo &f : files) {
        list.append(QVariantMap{
            {QStringLiteral("name"), f.completeBaseName()},
            {QStringLiteral("path"), QDir::toNativeSeparators(f.absoluteFilePath())},
            {QStringLiteral("size"), f.size()},
            {QStringLiteral("date"), f.lastModified().toString(QStringLiteral("d MMM yyyy HH:mm"))},
            {QStringLiteral("busy"), m_active && m_parts.contains(QDir::toNativeSeparators(f.absoluteFilePath()))},
        });
    }
    return list;
}

void Recorder::refresh()
{
    Q_EMIT recordingsChanged();
}

void Recorder::openFolder()
{
    if (!m_folder.isEmpty()) {
        QDir().mkpath(m_folder);
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_folder));
    }
}

bool Recorder::play(const QString &path)
{
    const QString mpc = mpcHcPath();
    if (!mpc.isEmpty()) {
        return QProcess::startDetached(mpc, {path, QStringLiteral("/fullscreen")});
    }
    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

bool Recorder::remove(const QString &path)
{
    if (m_active && m_parts.contains(path)) {
        return false;
    }
    const bool ok = QFile::remove(path);
    refresh();
    return ok;
}
