import { defineCollection } from 'astro:content'
import { docsLoader } from '@astrojs/starlight/loaders'
import { docsSchema } from '@astrojs/starlight/schema'
import { z } from 'astro/zod'

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    // hydrate.mjs derives these from solution.yaml. The published markdown
    // carries no frontmatter of its own, so this is where the extra fields
    // the tab strip needs are declared.
    schema: docsSchema({
      extend: z.object({
        tabs: z.array(z.string()).optional(),
        slugName: z.string().optional(),
      }),
    }),
  }),
}
