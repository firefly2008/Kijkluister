// SPDX-License-Identifier: GPL-2.0-or-later
#include "remoteserver.h"
#include "homebridge.h"
#include "paths.h"
#include "thirdparty/qrcodegen.hpp"

#include <QDateTime>
#include <QDebug>
#include <QFileInfo>
#include <QImage>
#include <QNetworkInterface>
#include <QPainter>
#include <QRandomGenerator>
#include <QSettings>
#include <QTcpSocket>
#include <QUrlQuery>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#endif

namespace {
constexpr quint16 firstPort = 8642;

// Pagina voor de telefoon: groot, donker, één hand te bedienen
const char page[] = R"HTML(<!doctype html>
<html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta name="theme-color" content="#0b0c0f"><title>Kijkluister</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;user-select:none}
body{margin:0;background:#0b0c0f;color:#fff;font:16px system-ui,sans-serif;display:flex;flex-direction:column;align-items:center;padding:18px 14px 28px}
h1{font-size:20px;font-weight:600;margin:4px 0 16px;color:#d4d7dc}
.pad{display:grid;grid-template-columns:repeat(3,88px);grid-template-rows:repeat(3,88px);gap:10px;margin-bottom:18px}
button{border:0;border-radius:18px;background:#22262e;color:#fff;font-size:28px;touch-action:manipulation}
button:active{background:#3d6fb4}
.ok{background:#3d6fb4;font-size:22px;font-weight:600;border-radius:50%}
.row{display:grid;grid-template-columns:repeat(3,88px);gap:10px;margin-bottom:10px}
.row button{height:64px;font-size:17px}
.type{display:flex;gap:8px;width:284px;margin-top:12px}
input{flex:1;border:0;border-radius:14px;background:#22262e;color:#fff;font-size:18px;padding:14px;user-select:text}
.type button{font-size:16px;padding:0 16px;height:52px}
#s{height:20px;margin-top:12px;color:#8a8f98;font-size:14px}
</style></head><body>
<h1>Kijkluister</h1>
<div class="pad">
<span></span><button data-k="up">▲</button><span></span>
<button data-k="left">◀</button><button class="ok" data-k="ok">OK</button><button data-k="right">▶</button>
<span></span><button data-k="down">▼</button><span></span>
</div>
<div class="row"><button data-k="back">↩ Terug</button><button data-k="home">⌂ Home</button><button data-k="menu">☰ Menu</button></div>
<div class="row"><button data-k="voldown">🔉</button><button data-k="playpause">⏯</button><button data-k="volup">🔊</button></div>
<div class="row"><button data-k="mute">🔇</button><button data-k="search">🔍 Zoek</button><button data-k="backspace">⌫</button></div>
<div class="type"><input id="t" placeholder="Typen…" autocomplete="off"><button id="send">Stuur</button></div>
<div id="s"></div>
<script>
const c=new URLSearchParams(location.search).get('c')||'';const s=document.getElementById('s');
function send(path,body){fetch(path+'?c='+encodeURIComponent(c),{method:'POST',body:body||''}).then(r=>{s.textContent=r.ok?'':'Code klopt niet: scan de QR-code opnieuw'}).catch(()=>{s.textContent='Geen verbinding met Kijkluister'})}
document.querySelectorAll('[data-k]').forEach(b=>{let t=null;const k=b.dataset.k;
b.addEventListener('pointerdown',e=>{e.preventDefault();navigator.vibrate&&navigator.vibrate(12);send('/k',k);
if(['up','down','left','right','voldown','volup','backspace'].includes(k))t=setTimeout(function r(){send('/k',k);t=setTimeout(r,140)},450)});
['pointerup','pointerleave','pointercancel'].forEach(ev=>b.addEventListener(ev,()=>{clearTimeout(t);t=null}))});
const i=document.getElementById('t');function go(){if(i.value){send('/t',i.value);i.value=''}}
document.getElementById('send').onclick=go;i.addEventListener('keydown',e=>{if(e.key==='Enter')go()});
</script></body></html>)HTML";

#ifdef Q_OS_WIN
void sendKeys(std::initializer_list<WORD> keys)
{
    // Ingedrukt in volgorde, losgelaten in omgekeerde volgorde (voor combinaties zoals Alt+Links)
    QList<INPUT> inputs;
    for (WORD vk : keys) {
        INPUT in = {};
        in.type = INPUT_KEYBOARD;
        in.ki.wVk = vk;
        if (vk == VK_UP || vk == VK_DOWN || vk == VK_LEFT || vk == VK_RIGHT) {
            in.ki.dwFlags = KEYEVENTF_EXTENDEDKEY;
        }
        inputs.append(in);
    }
    for (auto it = keys.end(); it != keys.begin();) {
        --it;
        INPUT in = {};
        in.type = INPUT_KEYBOARD;
        in.ki.wVk = *it;
        in.ki.dwFlags = KEYEVENTF_KEYUP;
        if (*it == VK_UP || *it == VK_DOWN || *it == VK_LEFT || *it == VK_RIGHT) {
            in.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
        }
        inputs.append(in);
    }
    SendInput(UINT(inputs.size()), inputs.data(), sizeof(INPUT));
}

bool browserInFront()
{
    HWND w = GetForegroundWindow();
    DWORD pid = 0;
    GetWindowThreadProcessId(w, &pid);
    if (pid == GetCurrentProcessId()) {
        return false;
    }
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) {
        return false;
    }
    wchar_t path[MAX_PATH];
    DWORD size = MAX_PATH;
    QString exe;
    if (QueryFullProcessImageNameW(process, 0, path, &size)) {
        exe = QFileInfo(QString::fromWCharArray(path, int(size))).fileName().toLower();
    }
    CloseHandle(process);
    return exe == QLatin1String("msedge.exe") || exe == QLatin1String("chrome.exe");
}
#endif
} // namespace

RemoteServer::RemoteServer(const QString &dataDir, QObject *parent)
    : QObject(parent)
    , m_dataDir(dataDir)
{
    QSettings settings(appSettingsFile(), QSettings::IniFormat);
    m_code = settings.value(QStringLiteral("remote/code")).toString();
    if (m_code.isEmpty()) {
        newCode();
    }
    connect(&m_server, &QTcpServer::newConnection, this, [this] {
        while (QTcpSocket *socket = m_server.nextPendingConnection()) {
            connect(socket, &QTcpSocket::readyRead, this, [this, socket] { handle(socket); });
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        }
    });
    if (settings.value(QStringLiteral("remote/enabled"), false).toBool()) {
        setEnabled(true);
    }
}

void RemoteServer::setEnabled(bool on)
{
    if (on == m_enabled && on == listening()) {
        return;
    }
    m_enabled = on;
    QSettings(appSettingsFile(), QSettings::IniFormat).setValue(QStringLiteral("remote/enabled"), on);
    if (on) {
        start();
    } else {
        m_server.close();
        qInfo() << "Remote: off";
    }
    Q_EMIT changed();
}

void RemoteServer::start()
{
    if (m_server.isListening()) {
        return;
    }
    for (quint16 port = firstPort; port < firstPort + 10; ++port) {
        if (m_server.listen(QHostAddress::AnyIPv4, port)) {
            break;
        }
    }
    qInfo() << "Remote: listening" << m_server.isListening() << address();
    makeQr();
}

QString RemoteServer::address() const
{
    if (!m_server.isListening()) {
        return {};
    }
    // Adres op het thuisnetwerk (192.168.x.x heeft voorrang, daarna 10.x en 172.16-31.x)
    QString best;
    int bestScore = -1;
    for (const QNetworkInterface &nif : QNetworkInterface::allInterfaces()) {
        const auto flags = nif.flags();
        if (!(flags & QNetworkInterface::IsUp) || !(flags & QNetworkInterface::IsRunning) || (flags & QNetworkInterface::IsLoopBack)
            || nif.type() == QNetworkInterface::Virtual) {
            continue;
        }
        const QString name = nif.humanReadableName().toLower();
        const bool virtualAdapter = name.contains(QLatin1String("vethernet")) || name.contains(QLatin1String("virtualbox"))
                                    || name.contains(QLatin1String("vmware")) || name.contains(QLatin1String("wsl"));
        for (const QNetworkAddressEntry &e : nif.addressEntries()) {
            const QHostAddress a = e.ip();
            if (a.protocol() != QAbstractSocket::IPv4Protocol || a.isLoopback()) {
                continue;
            }
            const QString ip = a.toString();
            int score = ip.startsWith(QLatin1String("192.168.")) ? 3 : ip.startsWith(QLatin1String("10.")) ? 2
                      : a.isPrivateUse() ? 1 : 0;
            if (virtualAdapter) {
                score -= 2;
            }
            if (score > bestScore) {
                bestScore = score;
                best = ip;
            }
        }
    }
    if (best.isEmpty()) {
        best = QStringLiteral("127.0.0.1");
    }
    return QStringLiteral("http://%1:%2").arg(best).arg(m_server.serverPort());
}

int RemoteServer::clients() const
{
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    int n = 0;
    for (qint64 t : m_seen) {
        if (now - t < 120) {
            ++n;
        }
    }
    return n;
}

void RemoteServer::newCode()
{
    m_code = QString::number(QRandomGenerator::system()->bounded(1000, 10000));
    QSettings(appSettingsFile(), QSettings::IniFormat).setValue(QStringLiteral("remote/code"), m_code);
    m_seen.clear();
    makeQr();
    Q_EMIT changed();
    Q_EMIT clientsChanged();
}

void RemoteServer::makeQr()
{
    if (!m_server.isListening()) {
        return;
    }
    const QString url = address() + QStringLiteral("/?c=") + m_code;
    const qrcodegen::QrCode qr = qrcodegen::QrCode::encodeText(url.toUtf8().constData(), qrcodegen::QrCode::Ecc::MEDIUM);
    const int border = 2;
    const int scale = 12;
    const int size = (qr.getSize() + border * 2) * scale;
    QImage image(size, size, QImage::Format_RGB32);
    image.fill(Qt::white);
    QPainter p(&image);
    for (int y = 0; y < qr.getSize(); ++y) {
        for (int x = 0; x < qr.getSize(); ++x) {
            if (qr.getModule(x, y)) {
                p.fillRect((x + border) * scale, (y + border) * scale, scale, scale, Qt::black);
            }
        }
    }
    p.end();
    // Nieuwe bestandsnaam per code, zodat het scherm niet het oude plaatje uit de cache toont
    const QString file = m_dataDir + QStringLiteral("/remote-qr-%1.png").arg(m_code);
    image.save(file);
    m_qr = QUrl::fromLocalFile(file);
}

void RemoteServer::respond(QTcpSocket *socket, int status, const QByteArray &type, const QByteArray &body)
{
    const QByteArray reason = status == 200 ? "OK" : status == 403 ? "Forbidden" : status == 404 ? "Not Found" : "Bad Request";
    QByteArray head = "HTTP/1.1 " + QByteArray::number(status) + ' ' + reason + "\r\n";
    head += "Content-Type: " + type + "\r\nContent-Length: " + QByteArray::number(body.size())
            + "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
    socket->write(head + body);
    socket->disconnectFromHost();
}

void RemoteServer::handle(QTcpSocket *socket)
{
    QByteArray data = socket->property("buffer").toByteArray() + socket->readAll();
    if (data.size() > 64 * 1024) {
        socket->abort();
        return;
    }
    const int headerEnd = data.indexOf("\r\n\r\n");
    if (headerEnd < 0) {
        socket->setProperty("buffer", data);
        return;
    }
    const QList<QByteArray> lines = data.left(headerEnd).split('\n');
    const QList<QByteArray> request = lines.value(0).trimmed().split(' ');
    int length = 0;
    for (const QByteArray &line : lines) {
        if (line.toLower().startsWith("content-length:")) {
            length = line.mid(15).trimmed().toInt();
        }
    }
    if (data.size() < headerEnd + 4 + length) {
        socket->setProperty("buffer", data);
        return;
    }
    const QByteArray body = data.mid(headerEnd + 4, length);
    const QByteArray method = request.value(0);
    const QUrl url(QString::fromUtf8(request.value(1)));
    const QString path = url.path();
    const QString code = QUrlQuery(url).queryItemValue(QStringLiteral("c"));

    if (method == "GET" && (path == QLatin1String("/") || path == QLatin1String("/index.html"))) {
        QByteArray html(page);
        if (QSettings(appSettingsFile(), QSettings::IniFormat).value(QStringLiteral("global/language")).toString() == QLatin1String("en")) {
            const QList<QPair<QByteArray, QByteArray>> english = {
                {"lang=\"nl\"", "lang=\"en\""}, {"↩ Terug", "↩ Back"}, {"🔍 Zoek", "🔍 Search"},
                {"Typen…", "Type…"}, {">Stuur<", ">Send<"},
                {"Code klopt niet: scan de QR-code opnieuw", "Wrong code: scan the QR code again"},
                {"Geen verbinding met Kijkluister", "No connection to Kijkluister"}};
            for (const auto &pair : english) {
                html.replace(pair.first, pair.second);
            }
        }
        respond(socket, 200, "text/html; charset=utf-8", html);
        return;
    }
    if (method != "POST" || (path != QLatin1String("/k") && path != QLatin1String("/t"))) {
        respond(socket, 404, "text/plain", "niet gevonden");
        return;
    }
    if (code != m_code) {
        qInfo() << "Remote: wrong code from" << socket->peerAddress().toString();
        respond(socket, 403, "text/plain", "code klopt niet");
        return;
    }
    const QString ip = socket->peerAddress().toString();
    const bool isNew = !m_seen.contains(ip) || QDateTime::currentSecsSinceEpoch() - m_seen.value(ip) >= 120;
    m_seen.insert(ip, QDateTime::currentSecsSinceEpoch());
    if (isNew) {
        qInfo() << "Remote: phone connected" << ip;
        Q_EMIT clientsChanged();
    }
    if (path == QLatin1String("/t")) {
        typeText(QString::fromUtf8(body).left(200));
        respond(socket, 200, "text/plain", "ok");
    } else {
        const bool ok = command(QString::fromUtf8(body).trimmed());
        respond(socket, ok ? 200 : 400, "text/plain", ok ? "ok" : "onbekend");
    }
}

bool RemoteServer::command(const QString &key)
{
    Q_EMIT commandReceived(key);
#ifdef Q_OS_WIN
    if (key == QLatin1String("up")) sendKeys({VK_UP});
    else if (key == QLatin1String("down")) sendKeys({VK_DOWN});
    else if (key == QLatin1String("left")) sendKeys({VK_LEFT});
    else if (key == QLatin1String("right")) sendKeys({VK_RIGHT});
    else if (key == QLatin1String("ok")) sendKeys({VK_RETURN});
    else if (key == QLatin1String("back")) {
        // In een website: vorige pagina; in Kijkluister en spelers: Esc
        if (browserInFront()) sendKeys({VK_MENU, VK_LEFT});
        else sendKeys({VK_ESCAPE});
    } else if (key == QLatin1String("home")) {
        if (HomeBridge *home = HomeBridge::instance()) {
            QMetaObject::invokeMethod(home, &HomeBridge::goHome, Qt::QueuedConnection);
        }
    } else if (key == QLatin1String("menu")) sendKeys({VK_APPS});
    else if (key == QLatin1String("playpause")) sendKeys({VK_MEDIA_PLAY_PAUSE});
    else if (key == QLatin1String("volup")) sendKeys({VK_VOLUME_UP});
    else if (key == QLatin1String("voldown")) sendKeys({VK_VOLUME_DOWN});
    else if (key == QLatin1String("mute")) sendKeys({VK_VOLUME_MUTE});
    else if (key == QLatin1String("backspace")) sendKeys({VK_BACK});
    else if (key == QLatin1String("search")) sendKeys({VK_F3});
    else return false;
    qInfo() << "Remote:" << key;
    return true;
#else
    return !key.isEmpty();
#endif
}

void RemoteServer::typeText(const QString &text)
{
#ifdef Q_OS_WIN
    QList<INPUT> inputs;
    for (const QChar ch : text) {
        INPUT down = {};
        down.type = INPUT_KEYBOARD;
        down.ki.wScan = ch.unicode();
        down.ki.dwFlags = KEYEVENTF_UNICODE;
        INPUT up = down;
        up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
        inputs << down << up;
    }
    if (!inputs.isEmpty()) {
        SendInput(UINT(inputs.size()), inputs.data(), sizeof(INPUT));
    }
#endif
    qInfo() << "Remote: typed" << text.size() << "characters";
}
