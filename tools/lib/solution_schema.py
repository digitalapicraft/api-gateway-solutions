#!/usr/bin/env python3
"""Validate a v2 solution manifest.

A v2 package declares `layout: v2` in solution.yaml. That manifest is the
navigation and metadata spine: it drives the tab strip, the gate's required-file
list, the generated root README, the composition page and the plugin index.

Usage:
    solution_schema.py <solution-dir> [--no-files]

--no-files skips the checks that require the tab files to exist, so a manifest
can be validated before the package is split.

Exit 0 when every check passes, 1 otherwise. A v1 package (no `layout:` key)
exits 0 with a SKIP — the v1 gate owns it.
"""
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "solution_schema: PyYAML is required. Without it the gate cannot parse a\n"
        "manifest and would pass packages it never read. Run: pip install pyyaml\n")
    sys.exit(2)

SEMVER = re.compile(r'^\d+\.\d+\.\d+$')
ISODATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
SLUG = re.compile(r'^\d{2}-[a-z0-9-]+$')

DIFFICULTY = {'Beginner', 'Intermediate', 'Advanced'}
BUILD_WITH = {'agent', 'openapi-import', 'control-plane-api'}
SCOPES = {'document', 'route'}
RELATION_KEYS = {'pairs_with', 'alternative_to', 'prerequisite_for', 'guides'}

# The composition axis. Each value is a question the library answers; the
# generated guides/choosing-a-solution.md groups solutions by it.
ANSWERS = {
    'who-is-calling',        # identity: 02, 05, 06, 08
    'how-much-can-they-call',  # metering and quota: 01
    'what-shape-is-the-payload',  # mediation: 03, 09, 13, 12
    'what-do-we-know-about-it',   # observability: 04, 10
    'what-else-must-happen',      # orchestration and enrichment: 07, 11, 14
    'what-protocol-is-it',        # transport: 15
}

CANONICAL_NAV = [
    ('Overview', 'readme.md'),
    ('Business need', 'business-need.md'),
    ('How it works', 'how-it-works.md'),
    ('Install', 'install.md'),
    ('Configuration', 'configuration.md'),
    ('Test & verify', 'testing.md'),
    ('Changelog', 'changelog.md'),
]
TAB_FOR_FILE = dict((f, t) for t, f in CANONICAL_NAV)


class Report:
    def __init__(self):
        self.fails = []
        self.warns = []

    def fail(self, msg):
        self.fails.append(msg)

    def warn(self, msg):
        self.warns.append(msg)

    def require(self, cond, msg):
        if not cond:
            self.fail(msg)
        return cond


def spec_plugin_names(sol_dir):
    """Every plugin name declared in gateway/api-spec.yaml, root and route scoped.

    Returns None when the package ships no spec (04-analytics is not a
    deployable package and legitimately has none).
    """
    path = os.path.join(sol_dir, 'gateway', 'api-spec.yaml')
    if not os.path.exists(path):
        return None
    with open(path) as fh:
        doc = yaml.safe_load(fh) or {}
    names = set((doc.get('x-helix-gateway') or {}).get('plugins') or {})
    for _p, ops in (doc.get('paths') or {}).items():
        if not isinstance(ops, dict):
            continue
        for _m, op in ops.items():
            if isinstance(op, dict):
                names |= set((op.get('x-helix-gateway') or {}).get('plugins') or {})
    return names


def check(sol_dir, check_files=True):
    r = Report()
    slug = os.path.basename(os.path.normpath(sol_dir))
    man = os.path.join(sol_dir, 'solution.yaml')

    if not os.path.exists(man):
        r.fail('solution.yaml is missing')
        return r, None

    try:
        with open(man) as fh:
            d = yaml.safe_load(fh) or {}
    except yaml.YAMLError as e:
        r.fail('solution.yaml does not parse: %s' % e)
        return r, None

    if 'layout' not in d:
        r.fail("layout: v2 is required — every package uses the tabbed layout")
        return r, None
    if d['layout'] != 'v2':
        r.fail("layout must be 'v2' when present, got %r" % (d['layout'],))
        return r, None

    # --- solution block -------------------------------------------------
    s = d.get('solution') or {}
    for k in ('name', 'slug', 'title', 'summary', 'version',
              'released', 'updated', 'category', 'tags'):
        r.require(s.get(k), 'solution.%s is required' % k)

    if s.get('slug'):
        r.require(s['slug'] == slug,
                  'solution.slug %r does not match the directory %r' % (s['slug'], slug))
        r.require(SLUG.match(s['slug']),
                  'solution.slug %r must be NN-lowercase-hyphenated' % s['slug'])
    if s.get('version'):
        r.require(SEMVER.match(str(s['version'])),
                  'solution.version %r must be MAJOR.MINOR.PATCH' % s['version'])
    for k in ('released', 'updated'):
        if s.get(k):
            r.require(ISODATE.match(str(s[k])),
                      'solution.%s %r must be YYYY-MM-DD' % (k, s[k]))
    if s.get('released') and s.get('updated'):
        r.require(str(s['updated']) >= str(s['released']),
                  'solution.updated is earlier than solution.released')
    if s.get('summary'):
        r.require(len(s['summary']) <= 300,
                  'solution.summary is %d chars; keep it under 300 (it is a card '
                  'subtitle and a meta description)' % len(s['summary']))
    r.require(isinstance(s.get('category'), str),
              'solution.category must be a single string (the primary nav group); '
              'use solution.categories for extra facets')
    r.require(isinstance(s.get('tags'), list) and s.get('tags'),
              'solution.tags must be a non-empty list')

    # --- facts ----------------------------------------------------------
    f = d.get('facts') or {}
    for k in ('setup_time', 'difficulty', 'needs', 'plugins', 'build_with'):
        r.require(k in f, 'facts.%s is required' % k)
    if f.get('difficulty'):
        r.require(f['difficulty'] in DIFFICULTY,
                  'facts.difficulty %r must be one of %s'
                  % (f['difficulty'], ', '.join(sorted(DIFFICULTY))))
    if f.get('build_with'):
        bad = set(f['build_with']) - BUILD_WITH
        r.require(not bad, 'facts.build_with has unknown value(s): %s' % ', '.join(sorted(bad)))

    # --- implementation.plugins ----------------------------------------
    impl = d.get('implementation') or {}
    plugins = impl.get('plugins')
    r.require(isinstance(plugins, list),
              'implementation.plugins must be a list (it is what the plugin index reads)')
    declared = set()
    for i, p in enumerate(plugins or []):
        if not isinstance(p, dict):
            r.fail('implementation.plugins[%d] must be a mapping' % i)
            continue
        if not p.get('name'):
            r.fail('implementation.plugins[%d].name is required' % i)
            continue
        declared.add(p['name'])
        r.require(p.get('role'),
                  'implementation.plugins[%d] (%s) needs a role — one line on what it '
                  'does HERE, which is what the plugin index prints' % (i, p['name']))
        sc = p.get('scope')
        r.require(sc in SCOPES,
                  'implementation.plugins[%d] (%s).scope must be document or route'
                  % (i, p['name']))
        if sc == 'route':
            r.require(p.get('at'),
                      'implementation.plugins[%d] (%s) is route-scoped and must name '
                      'its route(s) in `at`' % (i, p['name']))

    # THE parity check: the manifest may not claim a plugin set the spec does not
    # declare. This is what lets the plugin index be generated without parsing prose.
    spec_names = spec_plugin_names(sol_dir)
    if spec_names is None:
        r.require(not declared,
                  'no gateway/api-spec.yaml, so implementation.plugins must be empty; '
                  'declares: %s' % ', '.join(sorted(declared)))
    else:
        missing = spec_names - declared
        extra = declared - spec_names
        r.require(not missing,
                  'in api-spec.yaml but not in implementation.plugins: %s'
                  % ', '.join(sorted(missing)))
        r.require(not extra,
                  'in implementation.plugins but not in api-spec.yaml: %s'
                  % ', '.join(sorted(extra)))

    if isinstance(f.get('plugins'), list) and plugins is not None:
        r.require(set(f['plugins']) == declared,
                  'facts.plugins %s does not match implementation.plugins %s'
                  % (sorted(set(f.get('plugins') or [])), sorted(declared)))

    # --- nav ------------------------------------------------------------
    nav = d.get('nav')
    if not r.require(isinstance(nav, list) and nav,
                     'nav must be a non-empty list — it drives the tab strip AND the '
                     'gate\'s required-file list, so an empty nav is a package with no '
                     'required files at all'):
        nav = []
    seen_files = []
    for i, n in enumerate(nav):
        if not isinstance(n, dict) or not n.get('tab') or not n.get('file'):
            r.fail('nav[%d] must be a mapping with `tab` and `file`' % i)
            continue
        seen_files.append(n['file'])
        r.require(n['file'] == n['file'].lower(),
                  'nav[%d].file %r must be lowercase' % (i, n['file']))
        want = TAB_FOR_FILE.get(n['file'])
        if want:
            r.require(n['tab'] == want,
                      'nav[%d]: %s is the %r tab, not %r'
                      % (i, n['file'], want, n['tab']))
        else:
            r.warn('nav[%d].file %r is not one of the six canonical tabs'
                   % (i, n['file']))
    if seen_files:
        r.require(seen_files[0] == 'readme.md',
                  'nav[0] must be readme.md — the Overview is the landing page')
        r.require(len(seen_files) == len(set(seen_files)),
                  'nav lists a file more than once')
        order = [x for x in (fn for _t, fn in CANONICAL_NAV) if x in seen_files]
        r.require([x for x in seen_files if x in order] == order,
                  'nav order must follow %s' % ' -> '.join(order))

    if check_files and seen_files:
        for fn in seen_files:
            r.require(os.path.exists(os.path.join(sol_dir, fn)),
                      'nav names %s but the file does not exist' % fn)
        on_disk = set(x for x in os.listdir(sol_dir) if x.endswith('.md'))
        orphans = on_disk - set(seen_files)
        r.require(not orphans,
                  'markdown file(s) not listed in nav: %s' % ', '.join(sorted(orphans)))

    # --- relations and the composition axis -----------------------------
    rel = d.get('relations') or {}
    bad = set(rel) - RELATION_KEYS
    r.require(not bad, 'relations has unknown key(s): %s' % ', '.join(sorted(bad)))
    siblings = os.path.dirname(os.path.normpath(sol_dir))
    for k in RELATION_KEYS - {'guides'}:
        for other in rel.get(k) or []:
            r.require(os.path.isdir(os.path.join(siblings, other)),
                      'relations.%s names %r, which is not a solution' % (k, other))
            r.require(other != slug, 'relations.%s lists the solution itself' % k)

    r.require(d.get('answers') in ANSWERS,
              'answers must be one of: %s (it is the composition axis the '
              'choosing-a-solution page groups by)' % ', '.join(sorted(ANSWERS)))

    r.require(d.get('status'), 'status is required')
    return r, 'v2'


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('-')]
    check_files = '--no-files' not in argv
    if len(args) != 1:
        sys.stderr.write(__doc__)
        return 2

    sol_dir = args[0]
    r, layout = check(sol_dir, check_files=check_files)
    name = os.path.basename(os.path.normpath(sol_dir))

    if layout == 'v1':
        print('  SKIP %s — v1 layout, no `layout:` key' % name)
        return 0
    for w in r.warns:
        print('  WARN %s — %s' % (name, w))
    for f in r.fails:
        print('  FAIL %s — %s' % (name, f))
    if r.fails:
        return 1
    print('  PASS %s — v2 manifest valid%s' % (name, '' if check_files else ' (schema only)'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
