// Ingebouwde TMDB-sleutel van de eigenaar (alleen lezen), niet als leesbare tekst in het programma.
// Wordt bij het bouwen ingevuld uit het GitHub-geheim TMDB_TOKEN (scripts/build-installer.ps1).
// Vergrendeld: bekijken of wijzigen kan pas na de pincode (alleen de hash staat hier).
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QByteArray>
#include <QCryptographicHash>
#include <QString>

namespace BuiltinKey {
inline QString token()
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

inline bool pinMatches(const QString &pin)
{
    const QByteArray hash = QCryptographicHash::hash(QByteArray("kijkluister:") + pin.trimmed().toUtf8(), QCryptographicHash::Sha256).toHex();
    return hash == "eb72e994b4edc207c7e226e0a6624d4ff1ac83f756c6795f0b242bdb9ea16dfa";
}
}
