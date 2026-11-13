// SPDX-License-Identifier: GPL-2.0-or-later
#include "appmodel.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>
#include <QDesktopServices>
#include <QDirIterator>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>

#include <algorithm>

namespace {
QString dataDir()
{
    QString base = qEnvironmentVariable("LOCALAPPDATA");
    if (base.isEmpty()) {
        base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    }
    const QString dir = QDir::fromNativeSeparators(base) + QStringLiteral("/BigscreenHost");
    QDir().mkpath(dir);
    return dir;
}

void removeLocalFile(const QString &fileUrl)
{
    if (!fileUrl.isEmpty()) {
        QFile::remove(QUrl(fileUrl).toLocalFile());
    }
}
}

// Streamingdiensten die in Nederland te kijken zijn. Namen en adressen; het logo
// wordt bij de eerste start van de site zelf opgehaald (zie fetchFavicons).
struct WebDefault {
    const char *name;
    const char *url;
};
const WebDefault webDefaults[] = {
    {"Netflix", "https://www.netflix.com"},
    {"Disney+", "https://www.disneyplus.com"},
    {"Prime Video", "https://www.primevideo.com"},
    {"HBO Max", "https://www.hbomax.com"},
    {"Videoland", "https://www.videoland.com"},
    {"NPO Start", "https://npo.nl/start"},
    {"NLZIET", "https://app.nlziet.nl"},
    {"SkyShowtime", "https://www.skyshowtime.com"},
    {"Apple TV", "https://tv.apple.com/nl"},
    {"Viaplay", "https://viaplay.com/nl-nl"},
    {"YouTube", "https://www.youtube.com"},
    {"KIJK", "https://www.kijk.nl"},
    {"Ziggo GO", "https://www.ziggogo.tv"},
    {"KPN TV", "https://tv.kpn.com"},
    {"Odido TV", "https://tv.odido.nl"},
    {"Canal+", "https://www.canalplus.com/nl/"},
    {"Discovery+", "https://www.discoveryplus.com/nl"},
    {"Pathé Thuis", "https://www.pathe-thuis.nl"},
    {"Rakuten TV", "https://www.rakuten.tv/nl"},
    {"MUBI", "https://mubi.com/nl"},
    {"CineMember", "https://www.cinemember.nl"},
    {"Picl", "https://picl.nl"},
    {"Cinetree", "https://cinetree.nl"},
    {"Film1", "https://www.film1.nl"},
    {"Crunchyroll", "https://www.crunchyroll.com"},
    {"F1 TV", "https://f1tv.formula1.com"},
    {"ESPN", "https://www.espn.nl/watch/"},
    {"Twitch", "https://www.twitch.tv"},
    {"Plex", "https://app.plex.tv"},
};

AppModel::AppModel(Kind kind, QObject *parent)
    : QAbstractListModel(parent)
    , m_kind(kind)
    , m_settings(dataDir() + QStringLiteral("/settings.ini"), QSettings::IniFormat)
{
    m_hidden = m_settings.value(key("hiddenApps")).toStringList();
    m_customIcons = m_settings.value(key("customIcons")).toMap();
    m_background = m_settings.value(QStringLiteral("background")).toString();
    refresh();
}

QString AppModel::key(const char *name) const
{
    return (m_kind == Web ? QStringLiteral("web/") : QString()) + QLatin1String(name);
}

QList<AppModel::App> AppModel::customTiles() const
{
    QList<App> tiles;
    const QVariantList stored = m_settings.value(key("customTiles")).toList();
    for (const QVariant &entry : stored) {
        const QVariantMap map = entry.toMap();
        tiles.append({map.value(QStringLiteral("name")).toString(), map.value(QStringLiteral("target")).toString(), true});
    }
    return tiles;
}

void AppModel::saveCustomTiles(const QList<App> &tiles)
{
    QVariantList stored;
    for (const App &tile : tiles) {
        stored.append(QVariantMap{{QStringLiteral("name"), tile.name}, {QStringLiteral("target"), tile.path}});
    }
    m_settings.setValue(key("customTiles"), stored);
}

QString AppModel::faviconFile(const QString &url) const
{
    const QString hash = QString::fromLatin1(
        QCryptographicHash::hash(QUrl(url).host().toUtf8(), QCryptographicHash::Md5).toHex().left(12));
    return dataDir() + QStringLiteral("/images/site-") + hash + QStringLiteral(".png");
}

// Haalt per web-tegel eenmalig het pictogram van de site op en bewaart het lokaal.
void AppModel::fetchFavicons()
{
    QDir().mkpath(dataDir() + QStringLiteral("/images"));
    for (const App &tile : std::as_const(m_apps)) {
        const QString file = faviconFile(tile.path);
        if (QFile::exists(file) || m_customIcons.contains(tile.path)) {
            continue;
        }
        const QString target = tile.path;
        QUrl service(QStringLiteral("https://www.google.com/s2/favicons"));
        service.setQuery(QStringLiteral("sz=128&domain=") + QUrl(target).host());
        QNetworkReply *reply = m_network.get(QNetworkRequest(service));
        connect(reply, &QNetworkReply::finished, this, [this, reply, file, target] {
            reply->deleteLater();
            const QByteArray bytes = reply->readAll();
            QImage image;
            if (reply->error() != QNetworkReply::NoError || !image.loadFromData(bytes) || image.width() < 32) {
                qInfo() << "No site icon for" << target << reply->errorString();
                return;
            }
            image.save(file, "PNG");
            for (int row = 0; row < m_apps.size(); ++row) {
                if (m_apps.at(row).path == target) {
                    Q_EMIT dataChanged(index(row), index(row), {IconRole, AccentRole});
                }
            }
        });
    }
}

// Opent een site schermvullend in Edge (of Chrome) als app-venster zonder adresbalk.
// Een eigen ingebouwde webweergave valt af: Netflix e.d. vereisen DRM (Widevine/
// PlayReady) die alleen in de echte browsers zit. Eigen profielmap, zodat het
// venster altijd schermvullend start en inloggegevens bewaard blijven.
bool AppModel::launchWeb(const QString &url)
{
    QStringList candidates;
    const QString pf86 = qEnvironmentVariable("ProgramFiles(x86)");
    const QString pf = qEnvironmentVariable("ProgramFiles");
    const QString local = qEnvironmentVariable("LOCALAPPDATA");
    for (const QString &base : {pf86, pf}) {
        candidates << base + QStringLiteral("/Microsoft/Edge/Application/msedge.exe");
    }
    for (const QString &base : {pf, pf86, local}) {
        candidates << base + QStringLiteral("/Google/Chrome/Application/chrome.exe");
    }
    for (const QString &browser : std::as_const(candidates)) {
        if (!QFile::exists(browser)) {
            continue;
        }
        const QStringList args = {
            QStringLiteral("--app=") + url,
            QStringLiteral("--start-fullscreen"),
            QStringLiteral("--no-first-run"),
            QStringLiteral("--no-default-browser-check"),
            QStringLiteral("--user-data-dir=") + QDir::toNativeSeparators(dataDir() + QStringLiteral("/browser")),
        };
        if (QProcess::startDetached(browser, args)) {
            qInfo() << "Web tile" << url << "opened with" << browser;
            return true;
        }
    }
    qInfo() << "No Edge/Chrome found; opening" << url << "in default browser";
    return QDesktopServices::openUrl(QUrl(url));
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_apps.size();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_apps.size()) {
        return {};
    }
    const App &app = m_apps.at(index.row());
    switch (role) {
    case NameRole:
        return app.name;
    case PathRole:
        return app.path;
    case IconRole: {
        const QString custom = m_customIcons.value(app.path).toString();
        if (!custom.isEmpty()) {
            return custom;
        }
        if (m_kind == Web) {
            const QString file = faviconFile(app.path);
            return QFile::exists(file) ? QUrl::fromLocalFile(file).toString() : QString();
        }
        return QString(QStringLiteral("image://appicon/")
                       + QString::fromLatin1(QUrl::toPercentEncoding(app.path)));
    }
    case CustomIconRole:
        return m_customIcons.contains(app.path);
    case AccentRole:
        return accentFor(app);
    }
    return {};
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    return {{NameRole, "name"}, {PathRole, "path"}, {IconRole, "iconSource"}, {CustomIconRole, "customIcon"}, {AccentRole, "accent"}};
}

void AppModel::refresh()
{
    if (m_kind == Web) {
        QList<App> tiles;
        for (const WebDefault &entry : webDefaults) {
            tiles.append({QString::fromUtf8(entry.name), QString::fromUtf8(entry.url), false});
        }
        tiles.append(customTiles());
        tiles.erase(std::remove_if(tiles.begin(), tiles.end(), [this](const App &tile) {
            return m_hidden.contains(tile.path);
        }), tiles.end());
        beginResetModel();
        m_apps = tiles;
        endResetModel();
        Q_EMIT countChanged();
        qInfo() << "Web tiles" << m_apps.size() << "hidden" << m_hidden.size();
        fetchFavicons();
        return;
    }

    static const QStringList skipWords = {
        QStringLiteral("uninstall"), QStringLiteral("verwijder"), QStringLiteral("deinstall"),
        QStringLiteral("readme"), QStringLiteral("help"), QStringLiteral("website"),
        QStringLiteral("documentation"), QStringLiteral("documentatie"), QStringLiteral("license"),
        QStringLiteral("release notes"), QStringLiteral("manual"), QStringLiteral("handleiding"),
        QStringLiteral("bigscreen host"),
    };

    QList<App> apps;
    QSet<QString> seen;
    QStringList roots = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
#ifdef Q_OS_WIN
    // Qt geeft alleen het Startmenu van de gebruiker; de meeste programma's staan
    // in het gedeelde Startmenu onder ProgramData.
    const QString programData = qEnvironmentVariable("ProgramData");
    if (!programData.isEmpty()) {
        roots.append(QDir::fromNativeSeparators(programData) + QStringLiteral("/Microsoft/Windows/Start Menu/Programs"));
    }
#endif
    for (const QString &root : std::as_const(roots)) {
        QDirIterator it(root, {QStringLiteral("*.lnk")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo info(it.next());
            const QString name = info.completeBaseName();
            const QString key = name.toLower();
            const QString path = QDir::toNativeSeparators(info.absoluteFilePath());
            if (seen.contains(key) || m_hidden.contains(path)) {
                continue;
            }
            const bool skip = std::any_of(skipWords.begin(), skipWords.end(), [&key](const QString &word) {
                return key.contains(word);
            });
            if (skip) {
                continue;
            }
            seen.insert(key);
            apps.append({name, path, false});
        }
    }
    // Zelf toegevoegde programma's
    const QList<App> own = customTiles();
    for (const App &tile : own) {
        if (!m_hidden.contains(tile.path)) {
            apps.append(tile);
        }
    }
    std::sort(apps.begin(), apps.end(), [](const App &a, const App &b) {
        return a.name.localeAwareCompare(b.name) < 0;
    });

    beginResetModel();
    m_apps = apps;
    endResetModel();
    Q_EMIT countChanged();
    qInfo() << "Apps found" << m_apps.size() << "hidden" << m_hidden.size() << "in" << roots;
}

bool AppModel::launch(int row)
{
    if (row < 0 || row >= m_apps.size()) {
        return false;
    }
    const App &app = m_apps.at(row);
    const bool ok = m_kind == Web ? launchWeb(app.path) : QDesktopServices::openUrl(QUrl::fromLocalFile(app.path));
    qInfo() << "Launch" << app.name << (ok ? "ok" : "FAILED");
    return ok;
}

bool AppModel::openUri(const QString &uri)
{
    const bool ok = QDesktopServices::openUrl(QUrl(uri));
    qInfo() << "Open" << uri << (ok ? "ok" : "FAILED");
    return ok;
}

QString AppModel::nameAt(int row) const
{
    return (row >= 0 && row < m_apps.size()) ? m_apps.at(row).name : QString();
}

QString AppModel::iconAt(int row) const
{
    return data(index(row), IconRole).toString();
}

QColor AppModel::accentAt(int row) const
{
    return (row >= 0 && row < m_apps.size()) ? accentFor(m_apps.at(row)) : QColor(QStringLiteral("#22252b"));
}

// Achtergrondkleur van een tegel: de overheersende kleur van het logo, zo donker
// gemaakt dat witte tekst erop leesbaar blijft. Toepassingen krijgen neutraal grijs.
QColor AppModel::accentFor(const App &app) const
{
    if (m_kind != Web) {
        return QColor(QStringLiteral("#22252b"));
    }
    QString file = QUrl(m_customIcons.value(app.path).toString()).toLocalFile();
    if (file.isEmpty()) {
        file = faviconFile(app.path);
    }
    const auto cached = m_accentCache.constFind(file);
    if (cached != m_accentCache.constEnd()) {
        return *cached;
    }

    // Zonder logo: vaste kleur per naam
    QColor result = QColor::fromHslF(((app.name.size() * 47 + app.name.at(0).unicode() * 13) % 360) / 360.0, 0.45, 0.32);
    const QImage image = QImage(file).scaled(24, 24, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                             .convertToFormat(QImage::Format_ARGB32);
    if (!image.isNull()) {
        // Gemiddelde van de pixels, gewogen naar verzadiging: een rood logo op wit
        // geeft rood, geen roze. Is alles grijs/zwart/wit, dan blijft het donkergrijs.
        double r = 0, g = 0, b = 0, weight = 0;
        for (int y = 0; y < image.height(); ++y) {
            for (int x = 0; x < image.width(); ++x) {
                const QColor pixel = QColor::fromRgba(image.pixel(x, y));
                if (pixel.alpha() < 128) {
                    continue;
                }
                const double w = pixel.hslSaturationF() * (1.0 - qAbs(pixel.lightnessF() - 0.5) * 2.0);
                r += pixel.redF() * w;
                g += pixel.greenF() * w;
                b += pixel.blueF() * w;
                weight += w;
            }
        }
        if (weight > 8.0) {
            const QColor mean = QColor::fromRgbF(r / weight, g / weight, b / weight);
            result = QColor::fromHslF(qMax(0.0f, mean.hslHueF()), qMin(0.75f, mean.hslSaturationF()),
                                      qBound(0.22f, mean.lightnessF(), 0.36f));
        } else {
            result = QColor(QStringLiteral("#2a2d33"));
        }
        m_accentCache.insert(file, result);
    }
    return result;
}

bool AppModel::hasCustomIcon(int row) const
{
    return row >= 0 && row < m_apps.size() && m_customIcons.contains(m_apps.at(row).path);
}

void AppModel::hide(int row)
{
    if (row < 0 || row >= m_apps.size()) {
        return;
    }
    const App tile = m_apps.at(row);
    if (tile.custom) {
        // Zelf toegevoegde tegel: echt weggooien in plaats van verbergen
        QList<App> own = customTiles();
        own.erase(std::remove_if(own.begin(), own.end(), [&tile](const App &t) { return t.path == tile.path; }), own.end());
        saveCustomTiles(own);
    } else {
        m_hidden.append(tile.path);
        m_settings.setValue(key("hiddenApps"), m_hidden);
    }
    beginRemoveRows({}, row, row);
    m_apps.removeAt(row);
    endRemoveRows();
    Q_EMIT countChanged();
}

bool AppModel::addTile(const QString &name, const QString &target)
{
    QString cleanName = name.trimmed();
    QString cleanTarget = target.trimmed();
    if (cleanTarget.startsWith(QLatin1Char('"')) && cleanTarget.endsWith(QLatin1Char('"'))) {
        cleanTarget = cleanTarget.mid(1, cleanTarget.size() - 2);
    }
    if (cleanTarget.isEmpty()) {
        return false;
    }
    if (m_kind == Web) {
        if (!cleanTarget.contains(QStringLiteral("://"))) {
            cleanTarget.prepend(QStringLiteral("https://"));
        }
        const QUrl url(cleanTarget);
        if (!url.isValid() || url.host().isEmpty()) {
            return false;
        }
        if (cleanName.isEmpty()) {
            cleanName = url.host();
        }
    } else {
        if (cleanTarget.startsWith(QStringLiteral("file:"))) {
            cleanTarget = QUrl(cleanTarget).toLocalFile();
        }
        const QFileInfo info(cleanTarget);
        if (!info.isFile()) {
            return false;
        }
        cleanTarget = QDir::toNativeSeparators(info.absoluteFilePath());
        if (cleanName.isEmpty()) {
            cleanName = info.completeBaseName();
        }
    }
    QList<App> own = customTiles();
    for (const App &tile : std::as_const(own)) {
        if (tile.path == cleanTarget) {
            return false;
        }
    }
    own.append({cleanName, cleanTarget, true});
    saveCustomTiles(own);
    m_hidden.removeAll(cleanTarget);
    m_settings.setValue(key("hiddenApps"), m_hidden);
    refresh();
    qInfo() << "Tile added" << cleanName << cleanTarget;
    return true;
}

void AppModel::restoreHidden()
{
    m_hidden.clear();
    m_settings.setValue(key("hiddenApps"), m_hidden);
    refresh();
}

// Kopieert de gekozen afbeelding naar de eigen datamap, zodat het pictogram of de
// achtergrond blijft werken als het origineel verplaatst of gewist wordt.
QString AppModel::importImage(const QUrl &source, const QString &baseName)
{
    const QString sourcePath = source.isLocalFile() ? source.toLocalFile() : source.toString();
    const QFileInfo info(sourcePath);
    if (!info.isFile() || QImageReader(sourcePath).format().isEmpty()) {
        qWarning() << "Not a readable image:" << sourcePath;
        return {};
    }
    const QString dir = dataDir() + QStringLiteral("/images");
    QDir().mkpath(dir);
    // Tijdstempel in de naam: anders toont QML de oude afbeelding uit zijn cache
    const QString target = QStringLiteral("%1/%2-%3.%4")
                               .arg(dir, baseName)
                               .arg(QDateTime::currentMSecsSinceEpoch())
                               .arg(info.suffix().toLower());
    if (!QFile::copy(sourcePath, target)) {
        qWarning() << "Could not copy" << sourcePath << "to" << target;
        return {};
    }
    return QUrl::fromLocalFile(target).toString();
}

bool AppModel::setCustomIcon(int row, const QUrl &imageFile)
{
    if (row < 0 || row >= m_apps.size()) {
        return false;
    }
    const QString path = m_apps.at(row).path;
    const QString hash = QString::fromLatin1(
        QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Md5).toHex().left(12));
    const QString imported = importImage(imageFile, QStringLiteral("icon-") + hash);
    if (imported.isEmpty()) {
        return false;
    }
    removeLocalFile(m_customIcons.value(path).toString());
    m_customIcons.insert(path, imported);
    m_settings.setValue(key("customIcons"), m_customIcons);
    Q_EMIT dataChanged(index(row), index(row), {IconRole, CustomIconRole, AccentRole});
    return true;
}

void AppModel::clearCustomIcon(int row)
{
    if (!hasCustomIcon(row)) {
        return;
    }
    const QString path = m_apps.at(row).path;
    removeLocalFile(m_customIcons.take(path).toString());
    m_settings.setValue(key("customIcons"), m_customIcons);
    Q_EMIT dataChanged(index(row), index(row), {IconRole, CustomIconRole, AccentRole});
}

bool AppModel::setBackground(const QUrl &imageFile)
{
    const QString imported = importImage(imageFile, QStringLiteral("background"));
    if (imported.isEmpty()) {
        return false;
    }
    removeLocalFile(m_background);
    m_background = imported;
    m_settings.setValue(QStringLiteral("background"), m_background);
    Q_EMIT backgroundChanged();
    return true;
}

void AppModel::clearBackground()
{
    removeLocalFile(m_background);
    m_background.clear();
    m_settings.setValue(QStringLiteral("background"), m_background);
    Q_EMIT backgroundChanged();
}
