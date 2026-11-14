// SPDX-License-Identifier: GPL-2.0-or-later
#include "mpcplayer.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>

#include <SDL3/SDL.h>

#include "appmodel.h" // mpcHcPath(): een eventueel zelf geïnstalleerde MPC-HC

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {
MpcPlayer *s_instance = nullptr;

QString bundledDir()
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/mpc-hc");
}

bool copyTree(const QString &from, const QString &to)
{
    QDir().mkpath(to);
    QDirIterator it(from, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString src = it.next();
        const QString dst = to + src.mid(from.size());
        if (it.fileInfo().isDir()) {
            QDir().mkpath(dst);
        } else {
            QFile::remove(dst);
            if (!QFile::copy(src, dst)) {
                qWarning() << "MPC-HC: copy failed" << dst;
                return false;
            }
        }
    }
    return true;
}
}

MpcPlayer::MpcPlayer(const QString &dataDir, QObject *parent)
    : QObject(parent)
    , m_dataDir(dataDir)
    , m_portableDir(dataDir + QStringLiteral("/mpc-hc"))
{
    s_instance = this;
}

MpcPlayer::~MpcPlayer()
{
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

MpcPlayer *MpcPlayer::instance()
{
    return s_instance;
}

bool MpcPlayer::bundled() const
{
    return QFileInfo::exists(bundledDir() + QStringLiteral("/mpc-hc64.exe"));
}

bool MpcPlayer::running() const
{
    return m_process && m_process->state() != QProcess::NotRunning;
}

// De meegeleverde MPC-HC staat in Program Files (alleen-lezen). MPC-HC bewaart zijn instellingen
// (onder andere waar je gebleven was) in mpc-hc64.ini naast het programma, dus we zetten een
// kopie in de eigen datamap. Na een update van Kijkluister wordt die kopie vernieuwd.
bool MpcPlayer::preparePortable()
{
    const QString src = bundledDir();
    const QFileInfo srcExe(src + QStringLiteral("/mpc-hc64.exe"));
    if (!srcExe.exists()) {
        return false;
    }
    const QString stamp = QString::number(srcExe.size()) + QLatin1Char('-') + QString::number(srcExe.lastModified().toSecsSinceEpoch());
    QFile stampFile(m_portableDir + QStringLiteral("/kijkluister-versie.txt"));
    if (stampFile.open(QIODevice::ReadOnly) && QString::fromUtf8(stampFile.readAll()).trimmed() == stamp
        && QFileInfo::exists(m_portableDir + QStringLiteral("/mpc-hc64.exe"))) {
        return true;
    }
    stampFile.close();
    qInfo() << "MPC-HC: preparing portable copy in" << m_portableDir;
    // Instellingen van de gebruiker bewaren bij een update
    const QString ini = m_portableDir + QStringLiteral("/mpc-hc64.ini");
    QByteArray oldIni;
    if (QFile f(ini); f.open(QIODevice::ReadOnly)) {
        oldIni = f.readAll();
    }
    if (!copyTree(src, m_portableDir)) {
        return false;
    }
    if (!oldIni.isEmpty() && oldIni.contains("InterfaceLanguage")) {
        QFile f(ini);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.write(oldIni);
        }
    } else {
        // Eerste keer: Nederlands, schermvullend, onthouden waar je was, geen updatevraag
        // (namen uit MPC-HC SettingsDefines.h; alles in de sectie [Settings])
        QFile f(ini);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.write("[Settings]\r\n"
                    "InterfaceLanguage=1043\r\n"
                    "LaunchFullScreen=1\r\n"
                    "RememberFilePos=1\r\n"
                    "UpdaterAutoCheck=0\r\n");
        }
    }
    if (QFile out(m_portableDir + QStringLiteral("/kijkluister-versie.txt")); out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        out.write(stamp.toUtf8());
    }
    return true;
}

QString MpcPlayer::executable()
{
    if (preparePortable()) {
        return QDir::toNativeSeparators(m_portableDir + QStringLiteral("/mpc-hc64.exe"));
    }
    const QString installed = mpcHcPath();
    return QFileInfo::exists(installed) ? installed : QString();
}

bool MpcPlayer::play(const QStringList &files, bool closeAtEnd)
{
    if (files.isEmpty()) {
        return false;
    }
    const QString exe = executable();
    if (exe.isEmpty()) {
        return false;
    }
    if (running()) {
        // Nieuwe keuze: het lopende venster netjes sluiten, MPC-HC onthoudt de positie
        m_process->terminate();
        m_process->waitForFinished(3000);
    }
    QStringList args;
    for (const QString &f : files) {
        args << QDir::toNativeSeparators(f);
    }
    // /new: altijd een eigen venster dat bij Kijkluister hoort; /fullscreen /play;
    // bij een film na afloop sluiten, bij een serie de volgende aflevering laten spelen
    args << QStringLiteral("/new") << QStringLiteral("/fullscreen") << QStringLiteral("/play");
    if (closeAtEnd) {
        args << QStringLiteral("/close");
    }
    delete m_process;
    m_process = new QProcess(this);
    connect(m_process, &QProcess::finished, this, [this](int code) {
        qInfo() << "MPC-HC: closed" << code;
        Q_EMIT runningChanged();
        Q_EMIT finished();
    });
    m_process->setProgram(exe);
    m_process->setArguments(args);
    m_process->start();
    if (!m_process->waitForStarted(5000)) {
        qWarning() << "MPC-HC: could not start" << exe << m_process->errorString();
        return false;
    }
    qInfo().noquote() << "MPC-HC: playing" << files.size() << "file(s), first" << files.first();
#ifdef Q_OS_WIN
    AllowSetForegroundWindow(DWORD(m_process->processId()));
#endif
    Q_EMIT runningChanged();
    return true;
}

void MpcPlayer::sendVirtualKey(unsigned short vk, bool pressed, bool alt)
{
#ifdef Q_OS_WIN
    INPUT inputs[2] = {};
    int n = 0;
    if (alt && pressed) {
        inputs[n].type = INPUT_KEYBOARD;
        inputs[n].ki.wVk = VK_MENU;
        ++n;
    }
    inputs[n].type = INPUT_KEYBOARD;
    inputs[n].ki.wVk = vk;
    inputs[n].ki.dwFlags = pressed ? 0 : KEYEVENTF_KEYUP;
    ++n;
    SendInput(UINT(n), inputs, sizeof(INPUT));
    if (alt && !pressed) {
        INPUT up = {};
        up.type = INPUT_KEYBOARD;
        up.ki.wVk = VK_MENU;
        up.ki.dwFlags = KEYEVENTF_KEYUP;
        SendInput(1, &up, sizeof(INPUT));
    }
#else
    Q_UNUSED(vk) Q_UNUSED(pressed) Q_UNUSED(alt)
#endif
}

// Standaardtoetsen van MPC-HC: spatie pauze, ←/→ spoelen, ↑/↓ volume,
// PageUp/PageDown vorige/volgende in de lijst, Alt+X afsluiten
bool MpcPlayer::handleButton(int sdlButton, bool pressed)
{
#ifdef Q_OS_WIN
    if (!running()) {
        return false;
    }
    // Alleen als MPC-HC zelf voorop staat (anders bedient de controller iets anders)
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    if (pid != DWORD(m_process->processId())) {
        return false;
    }
    switch (sdlButton) {
    case SDL_GAMEPAD_BUTTON_SOUTH: sendVirtualKey(VK_SPACE, pressed); return true;           // A: pauze/verder
    case SDL_GAMEPAD_BUTTON_EAST: sendVirtualKey('X', pressed, true); return true;           // B: stoppen
    case SDL_GAMEPAD_BUTTON_DPAD_LEFT: sendVirtualKey(VK_LEFT, pressed); return true;        // terugspoelen
    case SDL_GAMEPAD_BUTTON_DPAD_RIGHT: sendVirtualKey(VK_RIGHT, pressed); return true;      // vooruitspoelen
    case SDL_GAMEPAD_BUTTON_DPAD_UP: sendVirtualKey(VK_UP, pressed); return true;            // harder
    case SDL_GAMEPAD_BUTTON_DPAD_DOWN: sendVirtualKey(VK_DOWN, pressed); return true;        // zachter
    case SDL_GAMEPAD_BUTTON_LEFT_SHOULDER: sendVirtualKey(VK_PRIOR, pressed); return true;   // vorige aflevering
    case SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER: sendVirtualKey(VK_NEXT, pressed); return true;   // volgende aflevering
    case SDL_GAMEPAD_BUTTON_NORTH: sendVirtualKey('S', pressed); return true;                // Y: ondertitels wisselen
    case SDL_GAMEPAD_BUTTON_WEST: sendVirtualKey('A', pressed); return true;                 // X: audiospoor wisselen
    default: return false;
    }
#else
    Q_UNUSED(sdlButton) Q_UNUSED(pressed)
    return false;
#endif
}
