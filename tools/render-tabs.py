#!/usr/bin/env python3
"""Regenerate the tab strip on line 3 of every v2 page, from solution.yaml nav.

The strip is plain markdown so the pages read correctly on GitHub. Because it is
generated and diffed rather than hand-written, adding or removing a tab can
never leave six pages pointing at a nav that changed.

  tools/render-tabs.py           # write
  tools/render-tabs.py --check   # exit 1 if any strip is stale
"""
import glob, os, sys
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def strip(nav, cur):
    return ' · '.join('**%s**' % n['tab'] if n['file'] == cur
                      else '[%s](%s)' % (n['tab'], n['file']) for n in nav)


def main():
    check = '--check' in sys.argv
    stale = []
    for mp in sorted(glob.glob(os.path.join(ROOT, 'solutions', '*', 'solution.yaml'))):
        man = yaml.safe_load(open(mp)) or {}
        if man.get('layout') != 'v2':
            continue
        d = os.path.dirname(mp)
        nav = man.get('nav') or []
        for n in nav:
            p = os.path.join(d, n['file'])
            if not os.path.exists(p):
                continue
            lines = open(p).read().split('\n')
            want = strip(nav, n['file'])
            if len(lines) > 2 and lines[2] == want:
                continue
            stale.append('%s/%s' % (os.path.basename(d), n['file']))
            if not check:
                if len(lines) > 2:
                    lines[2] = want
                else:
                    lines += ['', want]
                open(p, 'w').write('\n'.join(lines))
    if check:
        if stale:
            sys.exit('stale tab strip in: %s — run tools/render-tabs.py' % ', '.join(stale[:8]))
        print('tab strips are up to date')
    else:
        print('rewrote %d tab strip(s)' % len(stale))


if __name__ == '__main__':
    main()
