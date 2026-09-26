#!/usr/bin/env python3
"""Page-level checks for a v2 (tabbed) solution package.

solution_schema.py owns the manifest — required fields, nav/file agreement,
the manifest-to-spec plugin parity, relations. This owns the markdown: that
every page announces itself correctly, that the Overview stays a landing page,
that the changelog is machine-readable, and that no site-generator syntax has
leaked into files that must also read raw on GitHub.

Usage: v2_pages.py <solution-dir>
Exit 0 when every check passes, 1 otherwise.
"""
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write('v2_pages: PyYAML is required (pip install pyyaml)\n')
    sys.exit(2)

# Measured against all 15 solutions after every principled section move was made
# (request-flow walkthroughs to How it works, framing sections likewise). Twelve
# land between 81 and 196 lines. Three — 03-soap-to-rest, 06-hmac-auth and
# 12-key-value-map — land at 210-211 because their Gotchas, Limitations and
# caveat sections are genuinely longer, and the only way under 200 would be to
# delete content or to push it somewhere it does not belong. 220 keeps the cap
# doing its real job (stopping the Overview reassembling into the 400-line page
# the tabs replace) without forcing an arbitrary cut on the densest packages.
OVERVIEW_MAX = 220

# A published page must render identically on GitHub and on the site. These are
# the constructs that do not: MDX imports and components, Docusaurus/MkDocs
# admonitions, pymdownx content tabs, Jinja. Line-leading only, so prose that
# merely mentions one is fine.
SITE_SYNTAX = re.compile(r'^(import\s|<Tabs|</?TabItem|:::|=== "|\{%\s|\{\{<)')

CL_HEADING = re.compile(r'^## (\d+\.\d+\.\d+) — (\d{4}-\d{2}-\d{2})$')
CL_BULLET = re.compile(r'^- \*\*(Breaking|Feature|Fix|Docs)\*\* — ')
CL_BULLET_MAX = 400

# Private provenance must not ride into a public changelog. These are the shapes
# it actually takes in this workspace's records.
BANNED = [
    (re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'), 'a UUID'),
    (re.compile(r'\S+@\S+\.\S+'), 'an email address'),
    (re.compile(r'(?i)\b(verification|addendum|verified by|dry-run passed on|this session)\b'),
     'a private provenance phrase'),
]


def strip_for(nav, current):
    return ' · '.join('**%s**' % n['tab'] if n['file'] == current
                      else '[%s](%s)' % (n['tab'], n['file']) for n in nav)


def check_changelog(path, man, errs):
    lines = open(path).read().split('\n')
    entries = []
    for i, ln in enumerate(lines):
        if ln.startswith('## '):
            m = CL_HEADING.match(ln)
            if not m:
                errs.append('changelog.md:%d heading must be "## MAJOR.MINOR.PATCH — YYYY-MM-DD", got %r'
                            % (i + 1, ln))
            else:
                entries.append((m.group(1), m.group(2), i + 1))
        elif ln.startswith('- '):
            if not CL_BULLET.match(ln):
                errs.append('changelog.md:%d bullet must open "- **Breaking|Feature|Fix|Docs** — "' % (i + 1))
            elif len(ln) > CL_BULLET_MAX:
                errs.append('changelog.md:%d bullet is %d chars; cap is %d — a changelog entry is a '
                            'summary, not a narrative' % (i + 1, len(ln), CL_BULLET_MAX))

    body = '\n'.join(lines)
    for rx, what in BANNED:
        m = rx.search(body)
        if m:
            errs.append('changelog.md contains %s (%r) — public history is written from public '
                        'commits, never from private records' % (what, m.group(0)[:40]))

    if not entries:
        errs.append('changelog.md has no version entries')
        return

    def key(v):
        return tuple(int(x) for x in v.split('.'))

    for (a, _, _), (b, _, ln) in zip(entries, entries[1:]):
        if key(a) <= key(b):
            errs.append('changelog.md:%d versions must descend: %s follows %s' % (ln, b, a))

    s = man.get('solution', {})
    if entries[0][0] != str(s.get('version')):
        errs.append('changelog.md top entry is %s but solution.version is %s'
                    % (entries[0][0], s.get('version')))
    if entries[0][1] != str(s.get('updated')):
        errs.append('changelog.md top entry is dated %s but solution.updated is %s'
                    % (entries[0][1], s.get('updated')))
    if entries[-1][1] != str(s.get('released')):
        errs.append('changelog.md oldest entry is dated %s but solution.released is %s'
                    % (entries[-1][1], s.get('released')))


def main(d):
    errs = []
    man = yaml.safe_load(open(os.path.join(d, 'solution.yaml')))
    nav = man.get('nav') or []

    for n in nav:
        p = os.path.join(d, n['file'])
        if not os.path.exists(p):
            continue                      # solution_schema.py reports the absence
        lines = open(p).read().split('\n')

        if not lines[0].startswith('# '):
            errs.append('%s must open with an H1' % n['file'])
        elif n['file'] != 'readme.md' and n['tab'].lower() not in lines[0].lower():
            errs.append('%s: H1 %r does not name its tab %r — GitHub and the site would '
                        'disagree on the page title' % (n['file'], lines[0][2:][:50], n['tab']))

        want = strip_for(nav, n['file'])
        got = lines[2] if len(lines) > 2 else ''
        if got != want:
            errs.append('%s:3 tab strip is stale. Expected:\n         %s\n       got:\n         %s'
                        % (n['file'], want, got or '(blank)'))

        for i, ln in enumerate(lines):
            if SITE_SYNTAX.match(ln):
                errs.append('%s:%d site-generator syntax (%r) — pages must read raw on GitHub'
                            % (n['file'], i + 1, ln[:32]))
                break

    ov = os.path.join(d, 'readme.md')
    if os.path.exists(ov):
        n = len(open(ov).read().rstrip('\n').split('\n'))
        if n > OVERVIEW_MAX:
            errs.append('readme.md is %d lines; the Overview cap is %d. Without the cap it '
                        'reassembles into the single long page the tabs exist to replace.'
                        % (n, OVERVIEW_MAX))

    cl = os.path.join(d, 'changelog.md')
    if os.path.exists(cl):
        check_changelog(cl, man, errs)

    for e in errs:
        print('       %s' % e)
    return 1 if errs else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
