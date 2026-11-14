// SPDX-License-Identifier: GPL-2.0-or-later
#include "artframe.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QUrlQuery>

#include <algorithm>
#include <memory>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {
enum Source { Chicago, Met, NatureCommons, Pexels, Mix };

// Uitgelichte foto's van Wikimedia Commons (door de gemeenschap gekozen als de allerbeste)
const char *const commonsCategories[] = {
    "Featured pictures of landscapes",
    "Featured pictures of coasts",
    "Featured pictures of islands",
    "Featured pictures of volcanoes",
    "Featured pictures of natural phenomena",
    "Featured pictures of snow",
    "Featured pictures of reflections",
    "Featured pictures of birds",
    "Featured pictures of mammals",
};

const char *const pexelsQueries[] = {
    "nature landscape", "mountains", "forest", "ocean", "lake", "waterfall", "autumn", "aurora", "desert", "wildlife",
};

QString stripHtml(QString text)
{
    text.remove(QRegularExpression(QStringLiteral("<[^>]*>")));
    text.replace(QStringLiteral("&amp;"), QStringLiteral("&"));
    text.replace(QStringLiteral("&nbsp;"), QStringLiteral(" "));
    text.replace(QStringLiteral("&quot;"), QStringLiteral("\""));
    text.replace(QStringLiteral("&#039;"), QStringLiteral("'"));
    return text.simplified();
}

int randomInt(int max)
{
    return max <= 0 ? 0 : int(QRandomGenerator::global()->bounded(max));
}
}

ArtFrame::ArtFrame(QObject *parent)
    : QObject(parent)
{
    m_source = qBound(0, m_settings.value(QStringLiteral("frame/source"), 0).toInt(), int(Mix));
    m_interval = qBound(1, m_settings.value(QStringLiteral("frame/interval"), 5).toInt(), 120);
    m_showInfo = m_settings.value(QStringLiteral("frame/showInfo"), true).toBool();
    m_fill = m_settings.value(QStringLiteral("frame/fill"), true).toBool();
    m_pexelsKey = m_settings.value(QStringLiteral("frame/pexelsKey")).toString();
}

QStringList ArtFrame::sources() const
{
    return {
        tr("Schilderijen – Art Institute of Chicago"),
        tr("Topstukken – The Met, New York"),
        tr("Natuurfoto's – Wikimedia Commons"),
        tr("Natuurfoto's – Pexels (eigen sleutel)"),
        tr("Afwisselend kunst en natuur"),
    };
}

void ArtFrame::save()
{
    m_settings.setValue(QStringLiteral("frame/source"), m_source);
    m_settings.setValue(QStringLiteral("frame/interval"), m_interval);
    m_settings.setValue(QStringLiteral("frame/showInfo"), m_showInfo);
    m_settings.setValue(QStringLiteral("frame/fill"), m_fill);
    m_settings.setValue(QStringLiteral("frame/pexelsKey"), m_pexelsKey);
    Q_EMIT settingsChanged();
}

void ArtFrame::setSource(int source)
{
    source = qBound(0, source, int(Mix));
    if (source == m_source) {
        return;
    }
    m_source = source;
    save();
    // Nieuwe bron: wachtrij leeg en meteen iets nieuws laten zien
    ++m_generation;
    m_queue.clear();
    m_busy = false;
    m_retries = 0;
    next();
}

void ArtFrame::setInterval(int minutes)
{
    m_interval = qBound(1, minutes, 120);
    save();
}

void ArtFrame::setShowInfo(bool show)
{
    m_showInfo = show;
    save();
}

void ArtFrame::setFill(bool fill)
{
    m_fill = fill;
    save();
}

void ArtFrame::setPexelsKey(const QString &key)
{
    m_pexelsKey = key.trimmed();
    save();
    if (m_source == Pexels) {
        ++m_generation;
        m_queue.clear();
        m_busy = false;
        next();
    }
}

void ArtFrame::setStatus(const QString &status, bool busy)
{
    m_status = status;
    m_busy = busy;
    Q_EMIT statusChanged();
}

void ArtFrame::keepAwake(bool on)
{
#ifdef Q_OS_WIN
    SetThreadExecutionState(on ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED) : ES_CONTINUOUS);
#else
    Q_UNUSED(on)
#endif
}

void ArtFrame::start()
{
    if (m_position < 0) {
        next();
    }
}

void ArtFrame::next()
{
    if (m_position + 1 < m_history.size()) {
        ++m_position;
        Q_EMIT currentChanged();
        return;
    }
    if (!m_queue.isEmpty()) {
        showNextCandidate();
    } else {
        m_waiting = true; // laten zien zodra er iets binnen is
    }
    if (m_queue.size() < 3 && !m_busy) {
        fetchBatch();
    }
}

void ArtFrame::previous()
{
    if (m_position > 0) {
        --m_position;
        Q_EMIT currentChanged();
    }
}

void ArtFrame::showNextCandidate()
{
    m_history.append(m_queue.takeFirst());
    while (m_history.size() > 50) {
        m_history.removeFirst();
    }
    m_position = m_history.size() - 1;
    Q_EMIT currentChanged();
}

void ArtFrame::addCandidates(QList<QVariantMap> items)
{
    // Door elkaar, zodat het niet steeds dezelfde volgorde is
    for (int i = items.size() - 1; i > 0; --i) {
        items.swapItemsAt(i, randomInt(i + 1));
    }
    m_queue.append(items);
    if (m_queue.isEmpty()) {
        // Deze zoekopdracht leverde niets bruikbaars op: nog een paar keer een andere proberen
        if (++m_retries <= 4) {
            fetchBatch();
        } else {
            setStatus(tr("Geen afbeeldingen gevonden. Controleer de internetverbinding."), false);
        }
        return;
    }
    m_retries = 0;
    setStatus(QString(), false);
    if (m_waiting) {
        m_waiting = false;
        showNextCandidate();
    }
}

void ArtFrame::get(const QUrl &url, const Callback &callback, const QByteArray &auth)
{
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("Kijkluister/3.8 (https://github.com/firefly2008/bigscreen-host-windows)"));
    request.setRawHeader("AIC-User-Agent", "Kijkluister (https://github.com/firefly2008/bigscreen-host-windows)");
    if (!auth.isEmpty()) {
        request.setRawHeader("Authorization", auth);
    }
    request.setTransferTimeout(30000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_network.get(request);
    const int generation = m_generation;
    connect(reply, &QNetworkReply::finished, this, [this, reply, callback, generation] {
        reply->deleteLater();
        if (generation != m_generation) {
            return; // intussen andere bron gekozen
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning().noquote() << "Frame: request failed" << reply->url().host() << status << reply->errorString();
        }
        callback(reply->readAll(), status);
    });
}

void ArtFrame::fetchBatch()
{
    setStatus(tr("Afbeeldingen zoeken…"), true);
    int source = m_source;
    if (source == Mix) {
        const int choices[] = {Chicago, Met, NatureCommons};
        source = choices[randomInt(3)];
    }
    switch (source) {
    case Chicago:
        fetchChicago();
        break;
    case Met:
        fetchMet();
        break;
    case NatureCommons:
        fetchCommons();
        break;
    case Pexels:
        fetchPexels();
        break;
    }
}

// Art Institute of Chicago: vrije (public domain) schilderijen, liggend formaat
void ArtFrame::fetchChicago()
{
    const char *const terms[] = {"landscape", "impressionism", "sea", "garden", "river", "still life", "city", "winter", "flowers", "portrait"};
    QUrl url(QStringLiteral("https://api.artic.edu/api/v1/artworks/search"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("q"), QString::fromLatin1(terms[randomInt(10)]));
    query.addQueryItem(QStringLiteral("query[term][is_public_domain]"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("fields"), QStringLiteral("id,title,artist_display,date_display,image_id,classification_title,thumbnail"));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("100"));
    query.addQueryItem(QStringLiteral("page"), QString::number(1 + randomInt(3)));
    url.setQuery(query);
    get(url, [this](const QByteArray &data, int) {
        const QJsonObject root = QJsonDocument::fromJson(data).object();
        QString iiif = root.value(QStringLiteral("config")).toObject().value(QStringLiteral("iiif_url")).toString();
        if (iiif.isEmpty()) {
            iiif = QStringLiteral("https://www.artic.edu/iiif/2");
        }
        QList<QVariantMap> items;
        for (const QJsonValue &v : root.value(QStringLiteral("data")).toArray()) {
            const QJsonObject o = v.toObject();
            const QString imageId = o.value(QStringLiteral("image_id")).toString();
            const QString kind = o.value(QStringLiteral("classification_title")).toString();
            const QJsonObject thumb = o.value(QStringLiteral("thumbnail")).toObject();
            const double w = thumb.value(QStringLiteral("width")).toDouble();
            const double h = thumb.value(QStringLiteral("height")).toDouble();
            if (imageId.isEmpty() || !kind.contains(QLatin1String("painting")) || h <= 0 || w / h < 1.05) {
                continue; // alleen liggende schilderijen passen mooi op een tv
            }
            items.append({
                {QStringLiteral("image"), QStringLiteral("%1/%2/full/1686,/0/default.jpg").arg(iiif, imageId)},
                {QStringLiteral("title"), o.value(QStringLiteral("title")).toString()},
                {QStringLiteral("subtitle"), o.value(QStringLiteral("artist_display")).toString().section(QLatin1Char('\n'), 0, 0)
                                                 + QStringLiteral(", ") + o.value(QStringLiteral("date_display")).toString()},
                {QStringLiteral("credit"), tr("Art Institute of Chicago · publiek domein")},
            });
        }
        qInfo() << "Frame: Chicago gave" << items.size() << "paintings";
        addCandidates(items);
    });
}

// The Met: uitgelichte schilderijen met open toegang
void ArtFrame::fetchMet()
{
    if (!m_metIds.isEmpty()) {
        fetchMetObject();
        return;
    }
    QUrl url(QStringLiteral("https://collectionapi.metmuseum.org/public/collection/v1/search"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("isHighlight"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("hasImages"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("medium"), QStringLiteral("Paintings"));
    query.addQueryItem(QStringLiteral("q"), QStringLiteral("painting"));
    url.setQuery(query);
    get(url, [this](const QByteArray &data, int) {
        for (const QJsonValue &v : QJsonDocument::fromJson(data).object().value(QStringLiteral("objectIDs")).toArray()) {
            m_metIds.append(v.toInt());
        }
        qInfo() << "Frame: Met gave" << m_metIds.size() << "objects";
        if (m_metIds.isEmpty()) {
            setStatus(tr("The Met is niet bereikbaar"), false);
            return;
        }
        fetchMetObject();
    });
}

void ArtFrame::fetchMetObject()
{
    // Per object een aanvraag; een paar tegelijk ophalen is genoeg voor de wachtrij
    auto pending = std::make_shared<int>(4);
    auto found = std::make_shared<QList<QVariantMap>>();
    for (int i = 0; i < 4; ++i) {
        const int id = m_metIds.at(randomInt(m_metIds.size()));
        get(QUrl(QStringLiteral("https://collectionapi.metmuseum.org/public/collection/v1/objects/%1").arg(id)),
            [this, pending, found](const QByteArray &data, int) {
                const QJsonObject o = QJsonDocument::fromJson(data).object();
                const QString image = o.value(QStringLiteral("primaryImage")).toString();
                if (!image.isEmpty() && o.value(QStringLiteral("isPublicDomain")).toBool()) {
                    QString subtitle = o.value(QStringLiteral("artistDisplayName")).toString();
                    const QString date = o.value(QStringLiteral("objectDate")).toString();
                    if (!date.isEmpty()) {
                        subtitle += (subtitle.isEmpty() ? QString() : QStringLiteral(", ")) + date;
                    }
                    found->append({
                        {QStringLiteral("image"), image},
                        {QStringLiteral("title"), o.value(QStringLiteral("title")).toString()},
                        {QStringLiteral("subtitle"), subtitle},
                        {QStringLiteral("credit"), tr("The Metropolitan Museum of Art · open access")},
                    });
                }
                if (--*pending == 0) {
                    addCandidates(*found);
                }
            });
    }
}

// Wikimedia Commons: uitgelichte natuurfoto's (Featured pictures), liggend formaat
void ArtFrame::fetchCommons()
{
    const QString category = QString::fromLatin1(commonsCategories[randomInt(int(std::size(commonsCategories)))]);
    QUrl url(QStringLiteral("https://commons.wikimedia.org/w/api.php"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("action"), QStringLiteral("query"));
    query.addQueryItem(QStringLiteral("format"), QStringLiteral("json"));
    query.addQueryItem(QStringLiteral("generator"), QStringLiteral("categorymembers"));
    query.addQueryItem(QStringLiteral("gcmtitle"), QStringLiteral("Category:") + category);
    query.addQueryItem(QStringLiteral("gcmtype"), QStringLiteral("file"));
    query.addQueryItem(QStringLiteral("gcmlimit"), QStringLiteral("100"));
    query.addQueryItem(QStringLiteral("gcmsort"), QStringLiteral("timestamp"));
    query.addQueryItem(QStringLiteral("gcmdir"), randomInt(2) ? QStringLiteral("desc") : QStringLiteral("asc"));
    query.addQueryItem(QStringLiteral("prop"), QStringLiteral("imageinfo"));
    query.addQueryItem(QStringLiteral("iiprop"), QStringLiteral("url|size|extmetadata"));
    query.addQueryItem(QStringLiteral("iiurlwidth"), QStringLiteral("1920"));
    query.addQueryItem(QStringLiteral("iiextmetadatafilter"), QStringLiteral("Artist|ObjectName|LicenseShortName"));
    url.setQuery(query);
    get(url, [this](const QByteArray &data, int) {
        const QJsonObject pages = QJsonDocument::fromJson(data).object().value(QStringLiteral("query")).toObject()
                                      .value(QStringLiteral("pages")).toObject();
        QList<QVariantMap> items;
        for (const QJsonValue &page : pages) {
            const QJsonObject info = page.toObject().value(QStringLiteral("imageinfo")).toArray().first().toObject();
            const double w = info.value(QStringLiteral("width")).toDouble();
            const double h = info.value(QStringLiteral("height")).toDouble();
            const QString thumb = info.value(QStringLiteral("thumburl")).toString();
            const QString mime = thumb.section(QLatin1Char('.'), -1).toLower();
            if (thumb.isEmpty() || h <= 0 || w / h < 1.25 || (mime != QLatin1String("jpg") && mime != QLatin1String("jpeg"))) {
                continue;
            }
            const QJsonObject meta = info.value(QStringLiteral("extmetadata")).toObject();
            auto field = [&meta](const char *name) {
                return stripHtml(meta.value(QLatin1String(name)).toObject().value(QStringLiteral("value")).toString());
            };
            QString title = field("ObjectName");
            if (title.isEmpty()) {
                title = page.toObject().value(QStringLiteral("title")).toString().section(QLatin1Char(':'), 1).section(QLatin1Char('.'), 0, -2);
            }
            items.append({
                {QStringLiteral("image"), thumb},
                {QStringLiteral("title"), title},
                {QStringLiteral("subtitle"), field("Artist").left(80)},
                {QStringLiteral("credit"), tr("Wikimedia Commons · %1").arg(field("LicenseShortName"))},
            });
        }
        qInfo() << "Frame: Commons gave" << items.size() << "photos";
        addCandidates(items);
    });
}

// Pexels: gratis foto's, met een eigen (gratis) API-sleutel van pexels.com/api
void ArtFrame::fetchPexels()
{
    if (m_pexelsKey.isEmpty()) {
        setStatus(tr("Vul in Instellingen een gratis Pexels-sleutel in (pexels.com/api)"), false);
        return;
    }
    QUrl url(QStringLiteral("https://api.pexels.com/v1/search"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("query"), QString::fromLatin1(pexelsQueries[randomInt(int(std::size(pexelsQueries)))]));
    query.addQueryItem(QStringLiteral("orientation"), QStringLiteral("landscape"));
    query.addQueryItem(QStringLiteral("size"), QStringLiteral("large"));
    query.addQueryItem(QStringLiteral("per_page"), QStringLiteral("40"));
    query.addQueryItem(QStringLiteral("page"), QString::number(1 + randomInt(5)));
    url.setQuery(query);
    get(url, [this](const QByteArray &data, int status) {
        if (status == 401 || status == 403) {
            setStatus(tr("Pexels-sleutel klopt niet"), false);
            return;
        }
        QList<QVariantMap> items;
        for (const QJsonValue &v : QJsonDocument::fromJson(data).object().value(QStringLiteral("photos")).toArray()) {
            const QJsonObject o = v.toObject();
            const QString original = o.value(QStringLiteral("src")).toObject().value(QStringLiteral("original")).toString();
            if (original.isEmpty()) {
                continue;
            }
            items.append({
                {QStringLiteral("image"), original + QStringLiteral("?auto=compress&cs=tinysrgb&w=1920")},
                {QStringLiteral("title"), o.value(QStringLiteral("alt")).toString()},
                {QStringLiteral("subtitle"), tr("Foto: %1").arg(o.value(QStringLiteral("photographer")).toString())},
                {QStringLiteral("credit"), tr("Foto's van Pexels")},
            });
        }
        qInfo() << "Frame: Pexels gave" << items.size() << "photos";
        addCandidates(items);
    }, m_pexelsKey.toUtf8());
}
