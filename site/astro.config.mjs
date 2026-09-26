import { defineConfig } from 'astro/config'
import starlight from '@astrojs/starlight'
import sidebar from './src/generated/sidebar.json' with { type: 'json' }

// Served from GitHub Pages at <owner>.github.io/api-gateway-solutions.
// Moving to a custom domain later means dropping `base` and adding a CNAME.
export default defineConfig({
  site: 'https://digitalapicraft.github.io',
  base: '/api-gateway-solutions',
  trailingSlash: 'ignore',
  integrations: [
    starlight({
      title: 'API Gateway Solutions',
      description:
        'Solved API-gateway problems: the config, the reasoning, and what actually ran.',
      tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
      components: {
        // The tab strip. Every page already carries a plain-markdown one so the
        // files read correctly on GitHub; this renders it as real tabs instead.
        PageTitle: './src/components/SolutionTabs.astro',
        Head: './src/components/Head.astro',
      },
      customCss: ['./src/styles.css'],
      sidebar,
    }),
  ],
})
