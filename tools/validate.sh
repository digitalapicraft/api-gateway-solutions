#!/usr/bin/env bash
# Content gate for the solution library. No network. Exits non-zero on any FAIL.
#
# This is the single implementation. It lives here, in the public repo, because
# it checks public content — and both this repo's CI and the private build
# tooling call it rather than each keeping a copy in step by hand.
#
#   tools/validate.sh [SOLUTION_DIR ...]      (default: all under solutions/)
set -uo pipefail
PUB="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$PUB/tools"

fails=0; warns=0
say(){ printf '%s\n' "$*"; }
pass(){ printf '  \033[32mPASS\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33mWARN\033[0m %s\n' "$*"; warns=$((warns+1)); }
fail(){ printf '  \033[31mFAIL\033[0m %s\n' "$*"; fails=$((fails+1)); }

python3 -c 'import yaml' 2>/dev/null || {
  say "FATAL: PyYAML is missing. Without it this gate cannot parse a manifest and"
  say "would report PASS over files it never read. Run: pip install pyyaml"
  exit 2; }

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  targets=(); while IFS= read -r d; do targets+=("$d"); done \
    < <(find "$PUB/solutions" -mindepth 1 -maxdepth 1 -type d | sort)
fi

# Refuse to report PASS over nothing. An empty solutions/ used to sail through.
[ ${#targets[@]} -eq 0 ] && { say "FATAL: no solutions found under $PUB/solutions"; exit 2; }

for dir in "${targets[@]}"; do
  [ -d "$dir" ] || { fail "not a directory: $dir"; continue; }
  say ""; say "=== $(basename "$dir") ==="

  OVERVIEW=readme.md

  # The manifest is the required-file list, so it is checked first and hardest.
  # An absent or empty `nav` would otherwise be a package with no required files
  # at all, sailing through every check below it.
  if out=$(python3 "$TOOLS/lib/solution_schema.py" "$dir" 2>&1); then
    pass "manifest valid (nav, plugin parity, relations)"
  else fail "manifest:"; printf '%s\n' "$out" | sed 's/^  //; s/^/       /'; fi
  if out=$(python3 "$TOOLS/lib/v2_pages.py" "$dir" 2>&1); then
    pass "pages: tab strips, H1s, overview cap, changelog grammar"
  else fail "pages:"; printf '%s\n' "$out"; fi

  for md in "$dir"/*.md; do
    [ -f "$md" ] || continue
    n=$(grep -c '^```' "$md")
    [ $((n % 2)) -eq 0 ] && pass "fences balanced: $(basename "$md")" \
      || fail "unbalanced code fences: $(basename "$md") ($n markers)"
  done

  for y in "$dir/solution.yaml" "$dir"/gateway/api-spec.yaml "$dir"/gateway/products.json \
           "$dir"/validation/*.yaml "$dir"/tests/test-plan.yaml; do
    [ -f "$y" ] || continue
    if out=$(python3 -c '
import json,sys,yaml
p=sys.argv[1]
try:
    json.load(open(p)) if p.endswith(".json") else yaml.safe_load(open(p))
    print("OK")
except Exception as e:
    print(str(e)[:160]); sys.exit(1)' "$y" 2>&1); then
      pass "$(basename "$(dirname "$y")")/$(basename "$y"): $out"
    else fail "$(basename "$(dirname "$y")")/$(basename "$y"): $out"; fi
  done

  if [ -d "$dir/gateway" ]; then
    if grep -RInE '(signing_secret|client_secret|password)[[:space:]]*[:=][[:space:]]*"?[^<{"[:space:]]' \
         "$dir/gateway" 2>/dev/null >/tmp/ags_secrets && [ -s /tmp/ags_secrets ]; then
      fail "possible real secret in a spec (not a placeholder):"; sed 's/^/       /' /tmp/ags_secrets
    else pass "gateway specs carry no literal secrets"; fi
  fi

  if grep -RInE '([a-z0-9-]+\.)?digitalapicraft\.com|helix-ft|ft-gateway|control-plane\.[a-z0-9.-]+' \
       "$dir" 2>/dev/null >/tmp/ags_host && [ -s /tmp/ags_host ]; then
    fail "internal infra hostname leaked:"; sed 's/^/       /' /tmp/ags_host
  else pass "no internal infra hostnames"; fi
  if grep -RInE 'AIza[0-9A-Za-z_-]{30,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{40,}' \
       "$dir" 2>/dev/null >/tmp/ags_key && [ -s /tmp/ags_key ]; then
    fail "API key / JWT leaked:"; sed 's/^/       /' /tmp/ags_key
  else pass "no API keys / JWTs"; fi
  if grep -RInoE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
       "$dir" 2>/dev/null >/tmp/ags_uuid && [ -s /tmp/ags_uuid ]; then
    warn "bare UUID(s) present (confirm not a live resource id):"; sed 's/^/       /' /tmp/ags_uuid | head -5
  else pass "no bare UUIDs"; fi

  if grep -q '```mermaid' "$dir/$OVERVIEW" 2>/dev/null; then
    if python3 - "$dir/$OVERVIEW" <<'PY'
import re, sys
blocks = re.findall(r'```mermaid\n(.*?)```', open(sys.argv[1]).read(), re.S)
kinds = ('graph','flowchart','sequenceDiagram','classDiagram','stateDiagram',
         'erDiagram','journey','gantt','pie','gitGraph','mindmap','timeline',
         'quadrantChart','requirementDiagram','C4Context','sankey','block-beta')
bad = [i+1 for i,b in enumerate(blocks)
       if not b.strip() or not b.strip().split('\n')[0].strip().startswith(kinds)]
for i in bad: print(f'       block {i} declares no diagram type')
sys.exit(1 if bad else 0)
PY
    then pass "$OVERVIEW carries $(grep -c '```mermaid' "$dir/$OVERVIEW") mermaid diagram(s)"
    else fail "a \`\`\`mermaid block is empty or declares no diagram type"; fi
  else warn "$OVERVIEW has no \`\`\`mermaid diagram"; fi

  # Bounded by the next `## `, not a literal heading — bounding it by one
  # heading name meant renaming that heading made the section run to EOF.
  vslines=$(awk '/^## Validation status/{f=1;n=0;next} f&&/^## /{exit} f{n++} END{print n+0}' "$dir/$OVERVIEW" 2>/dev/null)
  if [ "${vslines:-0}" -gt 25 ]; then
    warn "Validation status is ${vslines} lines — compress it (>25 reads as a provenance log)"
  else pass "validation status is a summary (${vslines:-0} lines)"; fi

  # Threshold 0.75, not 0.55: two warnings once passed at 0.55 against a
  # 398-line page that never mentioned them, on coincidental vocabulary alone.
  if [ -f "$dir/validation/local-validation.yaml" ]; then
    python3 - "$dir" <<'PY' && pass "validation warnings are reflected in the pages" || warn "a validation warning has no counterpart in any page (see above)"
import re, sys, glob
d = sys.argv[1]
lv = open(f"{d}/validation/local-validation.yaml").read()
rd = " ".join(open(p).read() for p in sorted(glob.glob(f"{d}/*.md")))
m = re.search(r'(?ms)^  warnings:\n(.*?)(?=^  [a-z_]+:)', lv)
if not m: sys.exit(0)
items = [re.sub(r'^[>|][-+]?\s*', '', re.sub(r'\s+', ' ', b).strip(' -').strip())
         for b in re.split(r'(?m)^    - ', m.group(1)) if b.strip()]
STOP = set("the a an and or of to in is are it its this that for with not be as on by from you your we they".split())
tok = lambda s: {w for w in re.findall(r'[a-z_]{4,}', s.lower()) if w not in STOP}
rdt, bad = tok(rd), []
for it in items:
    t = tok(it)
    if t and len(t & rdt) / len(t) < 0.75: bad.append(it[:86])
for b in bad: print(f"       orphaned warning: {b}…")
sys.exit(1 if bad else 0)
PY
  fi

  if [ -d "$dir/tests" ]; then
    if python3 - "$dir" <<'PY'
import json, os, re, sys, glob
d = sys.argv[1]; tp = f"{d}/tests/test-plan.yaml"; errs = []
if os.path.exists(tp):
    txt = open(tp).read()
    for m in re.finditer(r'(?m)^\s*expected:\s*(\S.*)$', txt):
        v = m.group(1).strip().strip("\"'")
        if not v.startswith("expected/"):
            errs.append(f"test-plan `expected:` is not a fixture path: {v[:60]}")
    refs = {os.path.basename(m.group(1).strip())
            for m in re.finditer(r'(?m)^\s*expected:\s*(expected/\S+)$', txt)}
else: refs = set()
files = {os.path.basename(p) for p in glob.glob(f"{d}/tests/expected/*.json")}
for o in sorted(files - refs): errs.append(f"fixture never referenced by the plan: {o}")
for m2 in sorted(refs - files): errs.append(f"plan references a missing fixture: {m2}")
for p in sorted(glob.glob(f"{d}/tests/expected/*.json")):
    try: fx = json.load(open(p))
    except Exception as e: errs.append(f"{os.path.basename(p)} is not valid JSON: {e}"); continue
    extra = set(fx) - {"status", "headers", "body"}
    if extra: errs.append(f"{os.path.basename(p)} has non-schema keys {sorted(extra)}")
    if "status" not in fx: errs.append(f"{os.path.basename(p)} has no status")
for e in errs: print(f"       {e}")
sys.exit(1 if errs else 0)
PY
    then pass "test fixtures conform and match the plan"
    else fail "test fixture problems (see above)"; fi
  fi

  if find "$dir" -name '*.md' -print0 | xargs -0 cat 2>/dev/null | tr '\n' ' ' | tr -s ' ' \
       | grep -ioE 'helix +(api +)?gateway' >/tmp/ags_brand 2>/dev/null && [ -s /tmp/ags_brand ]; then
    fail "removed branding phrase present:"; sort -u /tmp/ags_brand | sed 's/^/       /'
  else pass "no removed branding phrases"; fi
done

# ---------------------------------------------------------------- generated
say ""; say "=== generated files are in sync ==="
for g in render-tabs render-facts render-index build-plugin-index; do
  if out=$(python3 "$TOOLS/$g.py" --check 2>&1); then pass "$out"
  else fail "$out"; fi
done

say ""
[ "$fails" -gt 0 ] && { say "RESULT: FAIL ($fails failed, $warns warnings)"; exit 1; }
[ "$warns" -gt 0 ] && { say "RESULT: PASS_WITH_WARNINGS ($warns warnings)"; exit 0; }
say "RESULT: PASS"
