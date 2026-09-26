#!/usr/bin/env node
/**
 * Copy ../solutions and ../guides into the site's content collection, adding
 * the frontmatter Starlight needs.
 *
 * The published markdown carries NO frontmatter on purpose: GitHub renders a
 * `---` block as a table at the top of a page whose first job is to read well
 * raw, and two metadata locations would need a check to prove they agree.
 * solution.yaml is the single source; this step derives the rest.
 *
 * It also injects the two generated sections that would otherwise be
 * hand-copied and drift: the full api-spec into Configuration, and the
 * request/response pairs into Test & verify.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import yaml from 'js-yaml'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO = path.resolve(HERE, '../..')
const OUT = path.resolve(HERE, '../src/content/docs')
const GEN = path.resolve(HERE, '../src/generated')

const rm = (p) => fs.rmSync(p, { recursive: true, force: true })
const mk = (p) => fs.mkdirSync(p, { recursive: true })
const read = (p) => fs.readFileSync(p, 'utf8')

rm(OUT); rm(GEN); mk(OUT); mk(GEN)

const esc = (s) => String(s).replace(/"/g, '\\"')

/** Strip the plain-markdown tab strip; the theme draws real tabs instead. */
function stripTabRow(body, nav) {
  const lines = body.split('\n')
  const isStrip = (l) => nav.some((n) => l.includes(`](${n.file})`)) && l.includes(' · ')
  if (lines[2] !== undefined && isStrip(lines[2])) lines.splice(1, 3)
  return lines.join('\n')
}

/** Rewrite sibling links (install.md) to sibling routes (install). */
function relink(body, nav) {
  for (const n of nav) {
    const route = n.file === 'readme.md' ? './' : './' + n.file.replace(/\.md$/, '')
    body = body.split(`](${n.file})`).join(`](${route})`)
  }
  return body.replace(/\]\((\.\.\/[0-9]{2}-[a-z0-9-]+)\/\)/g, '](../$1/)')
}

function fm(fields, body) {
  const head = Object.entries(fields)
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => (Array.isArray(v) ? `${k}:\n${v.map((x) => `  - "${esc(x)}"`).join('\n')}`
                                       : `${k}: "${esc(v)}"`))
    .join('\n')
  return `---\n${head}\n---\n\n${body.replace(/^# .*\n/, '')}`
}

// ---------------------------------------------------------------- solutions
const solDir = path.join(REPO, 'solutions')
const slugs = fs.readdirSync(solDir).filter((s) =>
  fs.existsSync(path.join(solDir, s, 'solution.yaml'))).sort()

const index = []
for (const slug of slugs) {
  const dir = path.join(solDir, slug)
  const man = yaml.load(read(path.join(dir, 'solution.yaml')))
  const s = man.solution || {}
  const v2 = man.layout === 'v2'
  const nav = v2 ? man.nav : [{ tab: 'Overview', file: 'README.md' }]
  const outDir = path.join(OUT, 'solutions', slug)
  mk(outDir)

  for (const n of nav) {
    const src = path.join(dir, n.file)
    if (!fs.existsSync(src)) continue
    let body = read(src)
    if (v2) body = relink(stripTabRow(body, nav), nav)

    if (v2 && n.file === 'configuration.md') body += specBlock(dir)
    if (v2 && n.file === 'testing.md') body += casesBlock(dir)

    const isHome = n.file.toLowerCase() === 'readme.md'
    fs.writeFileSync(
      path.join(outDir, isHome ? 'index.md' : n.file),
      fm({
        title: isHome ? (s.title || s.name || slug) : n.tab,
        description: isHome ? s.summary : `${n.tab} — ${s.title || s.name || slug}`,
        tabs: v2 ? nav.map((x) => `${x.tab}|${x.file}`) : undefined,
        slugName: slug,
      }, body))
  }
  index.push({ slug, title: s.title || s.name || slug, category: s.category || 'Uncategorised',
               summary: s.summary || '', v2 })
}

/** The spec, verbatim. The doc can never drift from the file it quotes. */
function specBlock(dir) {
  const p = path.join(dir, 'gateway/api-spec.yaml')
  if (!fs.existsSync(p)) return ''
  return `\n\n## The full specification\n\nImport this document as-is. It is the source of truth for everything above.\n\n\`\`\`yaml title="gateway/api-spec.yaml"\n${read(p).replace(/```/g, '\\u0060\\u0060\\u0060')}\n\`\`\`\n`
}

/** Request/response pairs, generated from the fixtures that verify.sh runs. */
function casesBlock(dir) {
  const tp = path.join(dir, 'tests/test-plan.yaml')
  if (!fs.existsSync(tp)) return ''
  let plan
  try { plan = yaml.load(read(tp)) } catch { return '' }
  const cases = plan?.cases || []
  if (!cases.length) return ''
  let out = `\n\n## Every case, as it actually runs\n\nGenerated from \`tests/\` — these are the fixtures \`gateway/verify.sh\` executes, not a re-typed copy.\n`
  for (const c of cases) {
    const req = c.request && fs.existsSync(path.join(dir, 'tests', c.request))
      ? read(path.join(dir, 'tests', c.request)).trim() : null
    const exp = c.expected && fs.existsSync(path.join(dir, 'tests', c.expected))
      ? read(path.join(dir, 'tests', c.expected)).trim() : null
    out += `\n### ${c.id || 'case'} — ${c.intent || ''}\n`
    if (c.type) out += `\n*${c.type}*, expecting \`${c.expected_status ?? '?'}\`.\n`
    if (req) out += `\n\`\`\`http title="request"\n${req}\n\`\`\`\n`
    if (exp) out += `\n\`\`\`json title="expected"\n${exp}\n\`\`\`\n`
  }
  return out
}

// ------------------------------------------------------------------- guides
const guideDir = path.join(REPO, 'guides')
const guides = []
if (fs.existsSync(guideDir)) {
  mk(path.join(OUT, 'guides'))
  for (const f of fs.readdirSync(guideDir).filter((x) => x.endsWith('.md')).sort()) {
    const body = read(path.join(guideDir, f))
    const title = (body.match(/^# (.+)$/m) || [, f.replace(/\.md$/, '')])[1]
    fs.writeFileSync(path.join(OUT, 'guides', f), fm({ title }, body))
    guides.push({ label: title, link: `/guides/${f.replace(/\.md$/, '')}` })
  }
}

// ------------------------------------------------------------------ plugins
const pluginIdx = path.join(REPO, 'plugins/readme.md')
if (fs.existsSync(pluginIdx)) {
  mk(path.join(OUT, 'plugins'))
  fs.writeFileSync(path.join(OUT, 'plugins/index.md'),
    fm({ title: 'Plugin index',
         description: 'Every plugin these solutions use, and which solution uses it.' },
       read(pluginIdx)))
}

// ------------------------------------------------------------- landing + nav
const root = path.join(REPO, 'README.md')
if (fs.existsSync(root)) {
  fs.writeFileSync(path.join(OUT, 'index.md'),
    fm({ title: 'API Gateway Solutions',
         description: 'Solved API-gateway problems: the config, the reasoning, and what actually ran.',
         template: 'splash' }, read(root)))
}

const byCat = {}
for (const s of index) (byCat[s.category] ||= []).push(s)

const sidebar = [
  { label: 'Start here', items: [{ label: 'Overview', link: '/' },
      ...(guides.length ? [{ label: 'Choosing a solution', link: '/guides/choosing-a-solution' }] : [])] },
  ...Object.keys(byCat).sort().map((cat) => ({
    label: cat,
    items: byCat[cat].map((s) => ({ label: s.title, link: `/solutions/${s.slug}/` })),
  })),
  ...(guides.length ? [{ label: 'Reference', items: guides }] : []),
  ...(fs.existsSync(pluginIdx) ? [{ label: 'Plugins', items: [{ label: 'Plugin index', link: '/plugins/' }] }] : []),
]
fs.writeFileSync(path.join(GEN, 'sidebar.json'), JSON.stringify(sidebar, null, 2))

console.log(`hydrated ${index.length} solution(s) — ${index.filter((s) => s.v2).length} v2, ` +
            `${index.filter((s) => !s.v2).length} v1 · ${guides.length} guide(s)`)
