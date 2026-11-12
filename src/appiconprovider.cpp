// SPDX-License-Identifier: GPL-2.0-or-later
#include "appiconprovider.h"

#include <QUrl>

#ifdef Q_OS_WIN
#include <windows.h>
#include <commctrl.h>
#include <commoncontrols.h>
#include <shellapi.h>
#include <shlobj.h>
#endif

AppIconProvider::AppIconProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage AppIconProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QImage image;
#ifdef Q_OS_WIN
    const QString path = QUrl::fromPercentEncoding(id.toLatin1());
    const HRESULT comInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    SHFILEINFOW info{};
    if (SHGetFileInfoW(reinterpret_cast<LPCWSTR>(path.utf16()), 0, &info, sizeof(info), SHGFI_SYSICONINDEX)) {
        // Grootste beschikbare formaat eerst (256 px), anders 48 px
        for (int listId : {SHIL_JUMBO, SHIL_EXTRALARGE}) {
            IImageList *list = nullptr;
            if (FAILED(SHGetImageList(listId, IID_IImageList, reinterpret_cast<void **>(&list))) || !list) {
                continue;
            }
            HICON icon = nullptr;
            if (SUCCEEDED(list->GetIcon(info.iIcon, ILD_TRANSPARENT, &icon)) && icon) {
                image = QImage::fromHICON(icon);
                DestroyIcon(icon);
            }
            list->Release();
            if (!image.isNull()) {
                break;
            }
        }
    }
    if (SUCCEEDED(comInit)) {
        CoUninitialize();
    }
#else
    Q_UNUSED(id);
#endif
    if (image.isNull()) {
        image = QImage(64, 64, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
    }
    if (requestedSize.isValid() && requestedSize.width() > 0 && requestedSize.height() > 0) {
        image = image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    if (size) {
        *size = image.size();
    }
    return image;
}
