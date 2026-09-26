#!/usr/bin/env python3
"""Generate plugins/readme.md — which plugin is used by which solution.

Reads only committed, public data: every solution.yaml, every
gateway/api-spec.yaml, and plugins/plugins-snapshot.json. CI can therefore
regenerate and diff it with no access to anything private.

  tools/build-plugin-index.py           # write the file
  tools/build-plugin-index.py --check   # exit 1 if the file is out of date
"""
import json
import os
import sys

try:
    import yaml
except ImportError:
    sys.exit('PyYAML is required (pip install pyyaml)')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'plugins', 'readme.md')
SNAP = os.path.join(ROOT, 'plugins', 'plugins-snapshot.json')


def spec_plugins(sol):
    p = os.path.join(sol, 'gateway', 'api-spec.yaml')
    if not os.path.exists(p):
        return set()
    doc = yaml.safe_load(open(p)) or {}
    names = set((doc.get('x-helix-gateway') or {}).get('plugins') or {})
    for _path, ops in (doc.get('paths') or {}).items():
        if isinstance(ops, dict):
            for _m, op in ops.items():
                if isinstance(op, dict):
                    names |= set((op.get('x-helix-gateway') or {}).get('plugins') or {})
    return names


def build():
    snap = json.load(open(SNAP))
    known = snap['plugins']
    soldir = os.path.join(ROOT, 'solutions')
    used = {}       # plugin -> [(slug, title, role)]
    errs = []

    for slug in sorted(os.listdir(soldir)):
        man_p = os.path.join(soldir, slug, 'solution.yaml')
        if not os.path.exists(man_p):
            continue
        man = yaml.safe_load(open(man_p)) or {}
        s = man.get('solution') or {}
        title = s.get('title') or s.get('name') or slug
        impl = (man.get('implementation') or {})
        declared = impl.get('plugins')

        if declared is None:                       # v1 package: fall back to the spec
            for n in sorted(spec_plugins(os.path.join(soldir, slug))):
                used.setdefault(n, []).append((slug, title, None))
            continue

        names = {p['name'] for p in declared if isinstance(p, dict) and p.get('name')}
        actual = spec_plugins(os.path.join(soldir, slug))
        if names != actual:
            errs.append('%s: manifest plugins %s != api-spec plugins %s'
                        % (slug, sorted(names), sorted(actual)))
        for p in declared:
            used.setdefault(p['name'], []).append((slug, title, p.get('role')))

    unknown = sorted(set(used) - set(known))
    for u in unknown:
        errs.append('%s is used by a solution but is not in plugins-snapshot.json' % u)
    if errs:
        for e in errs:
            print('  %s' % e, file=sys.stderr)
        sys.exit('plugin index cannot be generated from inconsistent data')

    by_cat = {}
    for name in sorted(used):
        by_cat.setdefault(known[name]['category'], []).append(name)

    L = []
    L.append('# Plugin index')
    L.append('')
    L.append('Every plugin these solutions configure, what each solution uses it *for*, and')
    L.append('a link to its field reference.')
    L.append('')
    L.append('This page is generated from each solution\'s manifest and its OpenAPI document,')
    L.append('so it cannot claim a plugin a solution does not actually configure. It is an')
    L.append('index, not a reference — field-by-field documentation lives in the plugin')
    L.append('reference each row links to.')
    L.append('')
    L.append('**%d of %d plugins are covered by a solution.**' % (len(used), snap['plugin_count']))
    L.append('')
    L.append('---')
    L.append('')
    for cat in sorted(by_cat):
        L.append('## %s' % cat)
        L.append('')
        L.append('| Plugin | Used by | What it does there | Reference |')
        L.append('|---|---|---|---|')
        for name in by_cat[cat]:
            entries = used[name]
            slugs = ' · '.join('[%s](../solutions/%s/)' % (sl, sl)
                               for sl, _t, _r in dict.fromkeys(
                                   (e[0], e[1], None) for e in entries))
            roles = [r for _s, _t, r in entries if r]
            what = ' · '.join(dict.fromkeys(r.strip().rstrip('.').split('\n')[0]
                                            for r in roles)) if roles else '—'
            if len(what) > 190:
                what = what[:187].rsplit(' ', 1)[0] + '…'
            L.append('| `%s` | %s | %s | [reference ↗](%s) |'
                     % (name, slugs, what, known[name]['docs_url']))
        L.append('')

    rest = sorted(set(known) - set(used))
    L.append('---')
    L.append('')
    L.append('## Not yet covered by a solution')
    L.append('')
    L.append('%d plugins exist that no solution here uses yet. This is the backlog, stated' % len(rest))
    L.append('honestly rather than hidden.')
    L.append('')
    L.append('<details>')
    L.append('<summary>Show all %d</summary>' % len(rest))
    L.append('')
    cur = None
    for n in sorted(rest, key=lambda x: (known[x]['category'], x)):
        c = known[n]['category']
        if c != cur:
            L.append('')
            L.append('**%s** — ' % c + ', '.join(
                '[`%s`](%s)' % (m, known[m]['docs_url'])
                for m in sorted(x for x in rest if known[x]['category'] == c)))
            cur = c
    L.append('')
    L.append('</details>')
    L.append('')
    return '\n'.join(L)


if __name__ == '__main__':
    text = build()
    if '--check' in sys.argv:
        cur = open(OUT).read() if os.path.exists(OUT) else ''
        if cur != text:
            sys.exit('plugins/readme.md is out of date — run tools/build-plugin-index.py')
        print('plugin index is up to date')
    else:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        open(OUT, 'w').write(text)
        print('wrote plugins/readme.md')
