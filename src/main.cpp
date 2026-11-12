// Bigscreen Host -- Fase 0/1 proof-of-concept (Optie A uit het migratieplan)
//
// Vervangt op Windows de combinatie van: startplasma-wayland (sessiestart),
// KWin (fullscreen containment + screenshots), envmanager (sessie-instellingen)
// en de XDG-portal-input-injectie uit inputhandler/. Draait als EEN proces,
// geen D-Bus, geen compositor-aanroepen.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#include <QCommandLineParser>
#include <QFile>
#include <QMutex>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QTextStream>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QQuickView>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <QtQml>

#include "appiconprovider.h"
#include "appmodel.h"
#include "gamepadnavigator.h"

#ifdef Q_OS_WIN
#include <windows.h>
#endif

#include "inputsystem.h"
#ifdef BIGSCREEN_HAVE_WIN32_INPUT
#include "win32inputsystem.h"
#else
#include "noopinputsystem.h"
#endif

namespace {

// De app is een GUI-programma zonder console: zonder logbestand verdwijnen alle
// foutmeldingen. Log staat in %LOCALAPPDATA%\\BigscreenHost\\bigscreen-host.log
QString g_logPath;
QMutex g_logMutex;

void logHandler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    static const char *names[] = {"DEBUG", "WARN", "CRIT", "FATAL", "INFO"};
    QMutexLocker lock(&g_logMutex);
    QFile f(g_logPath);
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream(&f) << QDateTime::currentDateTime().toString(Qt::ISODate) << " [" << names[type] << "] " << msg << "\n";
    }
}

void showFatal(const QString &text)
{
    qCritical().noquote() << text;
#ifdef Q_OS_WIN
    const QString full = text + QStringLiteral("\n\nLog: ") + g_logPath;
    MessageBoxW(nullptr, reinterpret_cast<LPCWSTR>(full.utf16()), L"Bigscreen Host", MB_OK | MB_ICONERROR);
#endif
}

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
    // Log zo vroeg mogelijk opzetten, nog voor QGuiApplication, zodat ook een
    // mislukte start van Qt zelf (platform-plugin, grafische backend) in het log komt.
    {
        QString base = qEnvironmentVariable("LOCALAPPDATA");
        if (base.isEmpty()) {
            base = QDir::tempPath();
        }
        const QString logDir = base + QStringLiteral("/BigscreenHost");
        QDir().mkpath(logDir);
        g_logPath = logDir + QStringLiteral("/bigscreen-host.log");
        QFile::remove(g_logPath);
        qInstallMessageHandler(logHandler);
        qInfo() << "main() reached; Qt" << qVersion();
    }

    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Bigscreen Host"));
    QGuiApplication::setOrganizationName(QStringLiteral("KDE"));

    qInfo() << "QGuiApplication created; platform" << QGuiApplication::platformName();

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

    // Gamepad-navigatie (SDL3) en de lijst met toepassingen voor de startpagina
    GamepadNavigator gamepad;
    AppModel appModel;

    auto inputSystem = createInputSystem();
    Q_UNUSED(inputSystem); // in dit skeleton nog niet aan QML-signalen gekoppeld

    const int screenIndex = parser.value(screenOption).toInt();
    const auto screens = QGuiApplication::screens();
    QScreen *targetScreen = (screenIndex >= 0 && screenIndex < screens.size())
        ? screens.at(screenIndex)
        : QGuiApplication::primaryScreen();

    QQuickView view;
    view.setFlags(Qt::FramelessWindowHint); // StaysOnTop bewust uit tijdens de PoC-fase
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setScreen(targetScreen);
    view.setGeometry(targetScreen->geometry());
    view.setColor(Qt::black);
    QObject::connect(view.engine(), &QQmlEngine::quit, &app, &QCoreApplication::quit);
    view.engine()->addImageProvider(QStringLiteral("appicon"), new AppIconProvider);
    view.rootContext()->setContextProperty(QStringLiteral("appModel"), &appModel);
    view.rootContext()->setContextProperty(QStringLiteral("gamepad"), &gamepad);
    // Alleen voor de geautomatiseerde test: opent bij het starten een menu
    view.rootContext()->setContextProperty(QStringLiteral("selfTest"), qEnvironmentVariable("BIGSCREEN_SELFTEST"));
    QObject::connect(&gamepad, &GamepadNavigator::homeRequested, &view, [&view] {
        view.showFullScreen();
        view.raise();
        view.requestActivate();
    });
    qInfo() << "Target screen" << targetScreen->name() << targetScreen->geometry();
    view.setSource(QUrl(QStringLiteral("qrc:/qt/qml/org/kde/plasma/bigscreen/host/Main.qml")));

    if (view.status() != QQuickView::Ready) {
        QString details = QStringLiteral("Main.qml kon niet geladen worden.");
        const auto errors = view.errors();
        for (const QQmlError &e : errors) {
            details += QStringLiteral("\n") + e.toString();
        }
        showFatal(details);
        return 1;
    }

    view.showFullScreen();
    view.raise();
    view.requestActivate();
    qInfo() << "Window shown" << view.geometry() << "visible" << view.isVisible();
    QObject::connect(view.engine(), &QQmlEngine::warnings, &view, [](const QList<QQmlError> &warnings) {
        for (const QQmlError &w : warnings) {
            qWarning().noquote() << "QML:" << w.toString();
        }
    });

    QObject::connect(&view, &QQuickWindow::sceneGraphError, &view, [](QQuickWindow::SceneGraphError, const QString &message) {
        showFatal(QStringLiteral("Grafische fout (scene graph): ") + message);
    });

    // takeScreenshot(&view) wordt in de echte app getriggerd door een QML-signaal
    // of controllerknop (zie Global::takeScreenshot() in het migratieplan),
    // niet hier op een vast moment -- de functie staat hierboven als referentie.

    return app.exec();
}
