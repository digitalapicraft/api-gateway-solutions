#!/usr/bin/env python3
"""Generate README.md and guides/choosing-a-solution.md from the manifests.

The library table used to be hand-maintained. It said "The thirteen solutions"
above fifteen rows — a heading and a table that had drifted apart with nothing
to notice. Generating both from solution.yaml makes that class of error
impossible; the editorial voice stays editable in tools/templates/.

  tools/render-index.py           # write
  tools/render-index.py --check   # exit 1 if either file is out of date
"""
import glob, os, re, sys
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMPL = os.path.join(ROOT, 'tools', 'templates', 'README.md.tmpl')

# The composition axis: the question each solution answers. Ordered so the
# page reads as a decision path rather than an alphabetical list.
AXES = [
 ('who-is-calling', 'Who is calling?',
  'Four answers, and you pick one. What decides it is what the caller can hold: '
  'a browser can hold a token but not a secret; a payment terminal can hold '
  'neither.'),
 ('how-much-can-they-call', 'How much can they call?',
  'Metering and quota. This needs identity resolved first, so it sits behind one '
  'of the answers above.'),
 ('what-shape-is-the-payload', 'What shape is the payload?',
  'Mediation — the caller wants one format and the backend speaks another.'),
 ('what-else-must-happen', 'What else must happen on the way?',
  'Enrichment, orchestration and fan-out: work the gateway does that the backend '
  'would otherwise repeat in every service.'),
 ('what-do-we-know-about-it', 'What do we know about the traffic?',
  'Attribution and redaction — who called, how often, and what must never reach '
  'a log.'),
 ('what-protocol-is-it', 'What protocol is it?',
  'Where the transport itself, not the payload, is the problem.'),
]


def load():
    out = []
    for mp in sorted(glob.glob(os.path.join(ROOT, 'solutions', '*', 'solution.yaml'))):
        man = yaml.safe_load(open(mp)) or {}
        s = man.get('solution') or {}
        out.append({
            'slug': s.get('slug') or os.path.basename(os.path.dirname(mp)),
            'title': s.get('title') or s.get('name'),
            'summary': (s.get('summary') or '').strip(),
            'category': s.get('category') or 'Uncategorised',
            'answers': man.get('answers'),
            'relations': man.get('relations') or {},
            'facts': man.get('facts') or {},
            'nav': man.get('nav') or [],
        })
    return out


def table(sols):
    L = ['| # | Solution | What it solves | Setup | Build it |',
         '|---|---|---|---|---|']
    for s in sols:
        num = s['slug'].split('-')[0]
        summary = re.sub(r'\s+', ' ', s['summary'])
        if len(summary) > 130:
            summary = summary[:127].rsplit(' ', 1)[0] + '…'
        install = next((n['file'] for n in s['nav'] if n['file'] == 'install.md'), None)
        build = ('[prompt](solutions/%s/install.md)' % s['slug']) if install else '—'
        L.append('| **%s** | [%s](solutions/%s/) | %s | %s | %s |'
                 % (num, s['title'], s['slug'], summary,
                    s['facts'].get('difficulty', '—'), build))
    return '\n'.join(L)


def composition(sols):
    by = {}
    for s in sols:
        by.setdefault(s['answers'], []).append(s)
    L = ['## Which one do you need?', '',
         'The library is organised by the question you are actually asking. '
         'The full decision path is in **[Choosing a solution](guides/choosing-a-solution.md)**.', '']
    for key, q, _blurb in AXES:
        group = by.get(key) or []
        if not group:
            continue
        L.append('- **%s** — %s' % (q, ' · '.join(
            '[%s](solutions/%s/)' % (g['title'], g['slug']) for g in group)))
    return '\n'.join(L)


def choosing(sols):
    by = {}
    for s in sols:
        by.setdefault(s['answers'], []).append(s)
    L = ['# Choosing a solution', '',
         'Start from the question you are asking, not from the plugin you think you need. '
         'This page is generated from the solutions themselves, so it always lists all of them.', '',
         '---', '']
    for key, q, blurb in AXES:
        group = by.get(key) or []
        if not group:
            continue
        L += ['## %s' % q, '', blurb, '']
        for g in group:
            L.append('### [%s](../solutions/%s/)' % (g['title'], g['slug']))
            L.append('')
            L.append(re.sub(r'\s+', ' ', g['summary']))
            L.append('')
            rel = g['relations']
            bits = []
            if rel.get('alternative_to'):
                bits.append('**Instead of:** ' + ' · '.join(
                    '[%s](../solutions/%s/)' % (x, x) for x in rel['alternative_to']))
            if rel.get('pairs_with'):
                bits.append('**Pairs with:** ' + ' · '.join(
                    '[%s](../solutions/%s/)' % (x, x) for x in rel['pairs_with']))
            if bits:
                L += [' · '.join(bits), '']
    L += ['---', '',
          '%d solutions in total. Every one was implemented and validated against a real '
          'gateway before it was published — see '
          '[Validation status](validation-status.md) for what each status means.' % len(sols), '']
    return '\n'.join(L)


def guides_list():
    out = []
    for p in sorted(glob.glob(os.path.join(ROOT, 'guides', '*.md'))):
        n = os.path.basename(p)
        if n == 'choosing-a-solution.md':
            continue
        title = (re.search(r'^# (.+)$', open(p).read(), re.M) or [None, n])[1]
        out.append('- **[%s](guides/%s)**' % (title, n))
    return '\n'.join(out)


def build():
    sols = load()
    t = open(TMPL).read()
    t = t.replace('{{SOLUTIONS_TABLE}}', table(sols))
    t = t.replace('{{COMPOSITION}}', composition(sols))
    t = t.replace('{{GUIDES_LIST}}', guides_list())
    return re.sub(r'\n{3,}', '\n\n', t).rstrip('\n') + '\n', choosing(sols)


if __name__ == '__main__':
    readme, choose = build()
    rp = os.path.join(ROOT, 'README.md')
    cp = os.path.join(ROOT, 'guides', 'choosing-a-solution.md')
    if '--check' in sys.argv:
        bad = [n for n, p, want in (('README.md', rp, readme), ('guides/choosing-a-solution.md', cp, choose))
               if not os.path.exists(p) or open(p).read() != want]
        if bad:
            sys.exit('out of date: %s — run tools/render-index.py' % ', '.join(bad))
        print('generated index pages are up to date')
    else:
        open(rp, 'w').write(readme)
        open(cp, 'w').write(choose)
        print('wrote README.md and guides/choosing-a-solution.md')
