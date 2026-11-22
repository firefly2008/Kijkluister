import json, re, subprocess, gzip, urllib.request
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Kijkluister-probe'
def get(url, timeout=60):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    r = urllib.request.urlopen(req, timeout=timeout)
    return r.status, r.geturl(), r.read()
print('=== URL-status')
for u in ['https://npo.nl/start/live', 'https://npo.nl/start/live?channel=npo-1', 'https://npo.nl/start/live/npo-1',
          'https://www.rtlxl.nl/live', 'https://www.rtlxl.nl/live/rtl4', 'https://www.rtlxl.nl/zenders', 'https://www.rtl.nl/rtlxl']:
    try:
        s, f, b = get(u, 25)
        print(u, '->', s, f, len(b))
    except Exception as e:
        print(u, '-> ERR', str(e)[:80])
print('=== NPO radio broadcasts')
for site in ['nporadio1.nl', 'nporadio2.nl', 'npo3fm.nl', 'nporadio4.nl', 'nporadio5.nl']:
    try:
        s, f, b = get('https://www.%s/api/broadcasts' % site, 25)
        items = json.loads(b).get('data', [])
        print(site, s, 'n=', len(items), 'keys=', sorted(items[0].keys()) if items else None)
        for it in items[:3]:
            print('   ', {k: str(v)[:50] for k, v in it.items() if k in ('title', 'startdatetime', 'enddatetime', 'presenters', 'broadcaster', 'description', 'channel', 'start', 'end')})
    except Exception as e:
        print(site, 'ERR', str(e)[:100])
print('=== tracks')
try:
    s, f, b = get('https://www.nporadio2.nl/api/tracks', 25)
    d = json.loads(b)['data']
    print(len(d), sorted(d[0].keys()))
    print({k: str(v)[:50] for k, v in d[0].items()})
except Exception as e:
    print('ERR', e)
print('=== epgshare NL1')
s, f, b = get('https://epgshare01.online/epgshare01/epg_ripper_NL1.xml.gz', 120)
x = gzip.decompress(b).decode('utf8')
ids = re.findall(r'<channel id="([^"]*)"', x)
print(len(ids), 'kanalen;', [i for i in ids if re.search('npo|rtl|3fm|radio', i, re.I)])
for c in ['RTL.4.nl', 'RTL.5.nl', 'RTL.7.nl', 'RTL.8.nl', 'RTL.Z.nl', 'NPO.1.nl', 'NPO.2.nl', 'NPO.3.nl']:
    p = re.findall(r'<programme start="(\d+)[^"]*" stop="(\d+)[^"]*" channel="%s">\s*<title[^>]*>([^<]*)' % re.escape(c), x)
    print(c, len(p), p[0] if p else None, p[-1] if p else None)
m = re.search(r'<programme[^>]*channel="RTL.4.nl">.*?</programme>', x, re.S)
print(m.group(0)[:600] if m else 'geen RTL4 programma')
print(re.findall(r'<channel id="RTL.4.nl">.*?</channel>', x, re.S)[:1])
