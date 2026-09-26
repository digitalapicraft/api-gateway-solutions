#!/usr/bin/env python3
"""Render each Overview's facts table from solution.yaml.

The table used to be hand-maintained in the markdown, which meant it could
disagree with the manifest and nothing would notice. It is generated now, between
two markers, so the manifest is the only place the numbers live.

  tools/render-facts.py           # write
  tools/render-facts.py --check   # exit 1 if any table is out of date
"""
import glob, os, re, sys
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEGIN, END = '<!-- facts:begin -->', '<!-- facts:end -->'


def table(man):
    f = man.get('facts') or {}
    nav = {n['file'] for n in (man.get('nav') or [])}
    rows = [('Setup time', f.get('setup_time', '—')),
            ('Difficulty', f.get('difficulty', '—')),
            ('Needs', ' · '.join(f.get('needs') or []) or '—')]
    pl = f.get('plugins') or []
    rows.append(('Plugins', ' · '.join('`%s`' % p for p in pl) if pl else 'None — this one deploys nothing'))
    build = []
    if 'agent' in (f.get('build_with') or []) and 'install.md' in nav:
        build.append('**[the Agent](install.md)** — recommended')
    if 'openapi-import' in (f.get('build_with') or []):
        build.append('or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml)')
    if build:
        rows.append(('Build it with', ' · '.join(build)))
    out = [BEGIN, '', '| | |', '|---|---|']
    out += ['| **%s** | %s |' % (k, v) for k, v in rows]
    out += ['', END]
    return '\n'.join(out)


def main():
    check = '--check' in sys.argv
    stale = []
    for mp in sorted(glob.glob(os.path.join(ROOT, 'solutions', '*', 'solution.yaml'))):
        d = os.path.dirname(mp)
        rp = os.path.join(d, 'readme.md')
        if not os.path.exists(rp):
            continue
        man = yaml.safe_load(open(mp)) or {}
        if man.get('layout') != 'v2':
            continue
        t = open(rp).read()
        new = table(man)
        if BEGIN in t and END in t:
            t2 = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END), lambda _: new, t, flags=re.S)
        else:
            # first run: drop whatever remains of the old hand-written table and
            # insert the generated one after the thesis, before the first heading.
            t2 = re.sub(r'\n\|[^\n]*\n(\|[^\n]*\n)*', '\n', t, count=1)
            m = re.search(r'(?m)^## ', t2)
            at = m.start() if m else len(t2)
            t2 = t2[:at] + new + '\n\n' + t2[at:]
        t2 = re.sub(r'\n{3,}', '\n\n', t2)
        if t2 != t:
            stale.append(os.path.basename(d))
            if not check:
                open(rp, 'w').write(t2)
    if check:
        if stale:
            sys.exit('facts table out of date in: %s — run tools/render-facts.py' % ', '.join(stale))
        print('facts tables are up to date')
    else:
        print('rendered facts table in %d solution(s)' % len(stale))


if __name__ == '__main__':
    main()
