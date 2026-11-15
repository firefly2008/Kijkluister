// SPDX-License-Identifier: GPL-2.0-or-later
#include "homebridge.h"

#include <QCursor>
#include <QDateTime>
#include <QFileInfo>
#include <QGuiApplication>
#include <QScreen>
#include <QWindow>

#ifdef Q_OS_WIN
#include <qt_windows.h>


namespace {
HomeBridge *g_bridge = nullptr;
HHOOK g_hook = nullptr;

LRESULT CALLBACK keyboardHook(int code, WPARAM wParam, LPARAM lParam)
{
    if (code == HC_ACTION && g_bridge) {
        const auto *info = reinterpret_cast<KBDLLHOOKSTRUCT *>(lParam);
        const bool down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
        bool swallow = false;
        g_bridge->keyEvent(info->vkCode, down, swallow);
        if (swallow) {
            return 1;
        }
    }
    return CallNextHookEx(g_hook, code, wParam, lParam);
}

QString processNameOf(HWND hwnd)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) {
        return {};
    }
    wchar_t path[MAX_PATH];
    DWORD size = MAX_PATH;
    QString name;
    if (QueryFullProcessImageNameW(process, 0, path, &size)) {
        name = QFileInfo(QString::fromWCharArray(path, int(size))).fileName().toLower();
    }
    CloseHandle(process);
    return name;
}
}
#endif

HomeBridge::HomeBridge(QWindow *main, QObject *parent)
    : QObject(parent)
    , m_main(main)
{
    m_poll.setInterval(250);
    connect(&m_poll, &QTimer::timeout, this, &HomeBridge::poll);
    m_escHold.setSingleShot(true);
    m_escHold.setInterval(1000);
    connect(&m_escHold, &QTimer::timeout, this, [this] {
        if (m_escDown && m_external) {
            qInfo() << "Home: Esc held";
            goHome();
        }
    });
#ifdef Q_OS_WIN
    g_bridge = this;
    g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardHook, GetModuleHandleW(nullptr), 0);
    qInfo() << "Home: keyboard hook" << (g_hook ? "installed" : "FAILED");
#endif
    connect(qApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (state == Qt::ApplicationActive && m_external) {
            m_external = false;
            setShowButton(false);
            m_poll.stop();
            Q_EMIT changed();
        }
    });
}

HomeBridge::~HomeBridge()
{
#ifdef Q_OS_WIN
    if (g_hook) {
        UnhookWindowsHookEx(g_hook);
    }
    g_bridge = nullptr;
#endif
}

void HomeBridge::externalLaunched()
{
    m_external = true;
    m_launchedAt = QDateTime::currentMSecsSinceEpoch();
    m_poll.start();
    Q_EMIT changed();
}

// Home-knop: de eerste 6 seconden na het openen, en zolang de muis bovenaan het scherm is
void HomeBridge::poll()
{
    if (!m_external) {
        return;
    }
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const QPoint pos = QCursor::pos();
    QScreen *screen = QGuiApplication::screenAt(pos);
    if (screen && pos.y() - screen->geometry().top() < screen->geometry().height() / 12) {
        m_lastNearTop = now;
    }
    setShowButton(now - m_launchedAt < 6000 || now - m_lastNearTop < 2500);
}

void HomeBridge::setShowButton(bool show)
{
    if (show != m_showButton) {
        m_showButton = show;
        Q_EMIT changed();
    }
}

void HomeBridge::keyEvent(unsigned long vk, bool down, bool &swallow)
{
#ifdef Q_OS_WIN
    if (vk == VK_BROWSER_HOME) {
        // Home-toets van afstandsbediening/toetsenbord: altijd naar Kijkluister (niet de startpagina van de browser)
        swallow = true;
        if (down) {
            qInfo() << "Home: home key";
            QMetaObject::invokeMethod(this, &HomeBridge::goHome, Qt::QueuedConnection);
        }
        return;
    }
    if (vk == VK_ESCAPE) {
        if (down && !m_escDown) {
            m_escDown = true;
            QMetaObject::invokeMethod(&m_escHold, qOverload<>(&QTimer::start), Qt::QueuedConnection);
        } else if (!down) {
            m_escDown = false;
            QMetaObject::invokeMethod(&m_escHold, &QTimer::stop, Qt::QueuedConnection);
        }
    }
#else
    Q_UNUSED(vk)
    Q_UNUSED(down)
    Q_UNUSED(swallow)
#endif
}

void HomeBridge::goHome()
{
#ifdef Q_OS_WIN
    HWND foreground = GetForegroundWindow();
    const HWND ours = m_main ? reinterpret_cast<HWND>(m_main->winId()) : nullptr;
    if (foreground && foreground != ours && m_external) {
        const QString exe = processNameOf(foreground);
        if (exe == QLatin1String("msedge.exe") || exe == QLatin1String("chrome.exe") || exe.startsWith(QLatin1String("mpc-hc"))) {
            qInfo() << "Home: closing" << exe;
            PostMessageW(foreground, WM_CLOSE, 0, 0);
        } else if (!exe.isEmpty() && exe != QLatin1String("explorer.exe")) {
            qInfo() << "Home: minimizing" << exe;
            ShowWindow(foreground, SW_MINIMIZE);
        }
    }
    if (ours) {
        // Naar voren halen, ook als Windows dat normaal tegenhoudt
        const DWORD fgThread = GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
        const DWORD ourThread = GetCurrentThreadId();
        if (fgThread != ourThread) {
            AttachThreadInput(fgThread, ourThread, TRUE);
        }
        ShowWindow(ours, SW_SHOW);
        SetForegroundWindow(ours);
        if (fgThread != ourThread) {
            AttachThreadInput(fgThread, ourThread, FALSE);
        }
    }
#endif
    m_external = false;
    setShowButton(false);
    m_poll.stop();
    Q_EMIT changed();
    Q_EMIT homeRequested();
}
