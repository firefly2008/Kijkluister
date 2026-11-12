// Bigscreen Host -- Fase 0/1 proof-of-concept (Optie A uit het migratieplan)
//
// Vervangt op Windows de combinatie van: startplasma-wayland (sessiestart),
// KWin (fullscreen containment + screenshots), envmanager (sessie-instellingen)
// en de XDG-portal-input-injectie uit inputhandler/. Draait als EEN proces,
// geen D-Bus, geen compositor-aanroepen.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#include <QCommandLineParser>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QQuickView>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <QtQml>

#include <SDL3/SDL.h>

#include "inputsystem.h"
#ifdef BIGSCREEN_HAVE_WIN32_INPUT
#include "win32inputsystem.h"
#else
#include "noopinputsystem.h"
#endif

namespace {

std::unique_ptr<InputSystem> createInputSystem()
{
#ifdef BIGSCREEN_HAVE_WIN32_INPUT
    auto system = std::make_unique<Win32InputSystem>();
#else
    auto system = std::make_unique<NoopInputSystem>();
#endif
    if (!system->init()) {
        qWarning() << "Input system could not be initialized; input injection will be disabled.";
    }
    return system;
}

// Vervangt Global::takeScreenshot() (components/bigscreenplugin/global.cpp),
// dat op Linux org.kde.KWin.ScreenShot2 over D-Bus aanriep. Hier heeft het
// Host-proces zelf het venster in handen, dus is dat niet meer nodig.
[[maybe_unused]] void takeScreenshot(QQuickWindow *window)
{
    if (!window) {
        qWarning() << "Could not take screenshot: no window";
        return;
    }

    const QImage result = window->grabWindow();

    const QString dir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation)
        + QStringLiteral("/Screenshots");
    QDir().mkpath(dir);

    const QString path = dir + QStringLiteral("/Screenshot_%1.png")
        .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_hhmmss")));

    if (!result.save(path)) {
        qWarning() << "Screenshot failed, could not save to" << path;
    } else {
        qInfo() << "Screenshot saved to" << path;
    }
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Bigscreen Host"));
    QGuiApplication::setOrganizationName(QStringLiteral("KDE"));

    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("Plasma Bigscreen Windows-host (PoC skeleton, Optie A)"));
    parser.addHelpOption();
    QCommandLineOption screenOption(
        QStringList{QStringLiteral("screen")},
        QStringLiteral("Index van de monitor om fullscreen op te openen (bv. de HDMI-tv-uitgang)."),
        QStringLiteral("index"),
        QStringLiteral("-1"));
    parser.addOption(screenOption);
    parser.process(app);

    // SDL3 init: alleen het gamepad-subsysteem, zoals inputhandler/sdlcontroller.cpp
    // dat al cross-platform deed -- dit stuk hoeft nauwelijks aangepast te worden.
    if (!SDL_Init(SDL_INIT_GAMEPAD)) {
        qWarning() << "SDL_Init(SDL_INIT_GAMEPAD) failed:" << SDL_GetError();
    }

    auto inputSystem = createInputSystem();
    Q_UNUSED(inputSystem); // in dit skeleton nog niet aan QML-signalen gekoppeld

    const int screenIndex = parser.value(screenOption).toInt();
    const auto screens = QGuiApplication::screens();
    QScreen *targetScreen = (screenIndex >= 0 && screenIndex < screens.size())
        ? screens.at(screenIndex)
        : QGuiApplication::primaryScreen();

    QQuickView view;
    view.setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setScreen(targetScreen);
    view.setGeometry(targetScreen->geometry());
    view.setColor(Qt::black);
    view.setSource(QUrl(QStringLiteral("qrc:/qt/qml/org/kde/plasma/bigscreen/host/Main.qml")));

    if (view.status() == QQuickView::Error) {
        qCritical() << "Could not load Main.qml";
        return 1;
    }

    view.showFullScreen();

    QObject::connect(&view, &QQuickWindow::sceneGraphError, &view, [](QQuickWindow::SceneGraphError, const QString &message) {
        qWarning() << "Scene graph error:" << message;
    });

    QObject::connect(&app, &QGuiApplication::lastWindowClosed, [] {
        SDL_Quit();
    });

    // takeScreenshot(&view) wordt in de echte app getriggerd door een QML-signaal
    // of controllerknop (zie Global::takeScreenshot() in het migratieplan),
    // niet hier op een vast moment -- de functie staat hierboven als referentie.

    return app.exec();
}
