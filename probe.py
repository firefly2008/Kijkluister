import re, urllib.request
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Kijkluister-probe'
def get(url):
    r = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=30)
    return r.status, r.geturl(), r.read().decode('utf8', 'replace')
s, f, h = get('https://www.rtl.nl/')
links = sorted(set(re.findall(r'href="([^"]*)"', h)))
print(len(links), 'links')
print([l for l in links if re.search(r'live|zender|rtl4|rtl-4|kijk|tv-gids|gids', l, re.I)][:60])
print(re.findall(r'https?://[^"\\ ]*(?:live|rtlxl)[^"\\ ]*', h)[:40])
for u in ['https://www.rtl.nl/live', 'https://www.rtl.nl/kijken/live', 'https://www.rtl.nl/video/live', 'https://www.rtl.nl/zenders/rtl4',
          'https://www.rtl.nl/live/rtl4', 'https://www.rtl.nl/zenders', 'https://www.rtlxl.nl/', 'https://rtlxl.nl/live']:
    try:
        s, f, h2 = get(u)
        print(u, '->', s, f, len(h2))
    except Exception as e:
        print(u, '-> ERR', str(e)[:60])
