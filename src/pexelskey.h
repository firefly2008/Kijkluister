// Pexels-sleutel voor "Achtergrond wijzigen → Gratis foto". Wordt bij het bouwen ingevuld vanuit het
// GitHub-geheim PEXELS_KEY (scripts/build-installer.ps1), versluierd; leeg = Openverse gebruiken.
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QByteArray>
#include <QString>

namespace PexelsKey {
inline QString key()
{
    static const int length = 0;
    static const unsigned char data[] = { 0 };
    static const unsigned char mask[] = { 0 };
    QByteArray out;
    for (int i = 0; i < length; ++i) {
        out.append(char(data[i] ^ mask[i]));
    }
    return QString::fromLatin1(out);
}
}
