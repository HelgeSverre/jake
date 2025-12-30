// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLlmsTxt from 'starlight-llms-txt';

import tailwindcss from '@tailwindcss/vite';

// https://astro.build/config
export default defineConfig({
  site: 'https://jakefile.dev',

  integrations: [
      starlight({
          title: 'Jake',
          description: 'Modern command running. The best of Make and Just, combined.',
          plugins: [starlightLlmsTxt()],
          logo: {
              light: './src/assets/logo-light.svg',
              dark: './src/assets/logo-dark.svg',
              replacesTitle: true,
          },
          social: [
              { icon: 'github', label: 'GitHub', href: 'https://github.com/HelgeSverre/jake' },
          ],
          customCss: ['./src/styles/custom.css'],
          head: [
              {
                  tag: 'meta',
                  attrs: {
                      property: 'og:image',
                      content: 'https://jakefile.dev/og-image.png',
                  },
              },
          ],
          sidebar: [
              {
                  label: 'Getting Started',
                  items: [
                      { label: 'Introduction', slug: 'docs/introduction' },
                      { label: 'Installation', slug: 'docs/installation' },
                      { label: 'Quick Start', slug: 'docs/quick-start' },
                  ],
              },
              {
                  label: 'Guide',
                  items: [
                      { label: 'Jakefile Syntax', slug: 'docs/syntax' },
                      { label: 'Tasks', slug: 'docs/tasks' },
                      { label: 'File Targets', slug: 'docs/file-targets' },
                      { label: 'Dependencies', slug: 'docs/dependencies' },
                      { label: 'Variables', slug: 'docs/variables' },
                      { label: 'Positional Arguments', slug: 'docs/positional-arguments' },
                      { label: 'Imports', slug: 'docs/imports' },
                      { label: 'Conditionals', slug: 'docs/conditionals' },
                      { label: 'Hooks', slug: 'docs/hooks' },
                      { label: 'Watch Mode', slug: 'docs/watch-mode' },
                      { label: 'Best Practices', slug: 'docs/best-practices' },
                      { label: 'Troubleshooting', slug: 'docs/troubleshooting' },
                  ],
              },
              {
                  label: 'Reference',
                  items: [
                      { label: 'CLI Options', slug: 'reference/cli' },
                      { label: 'Directives', slug: 'reference/directives' },
                      { label: 'Built-in Functions', slug: 'reference/functions' },
                      { label: 'Shell Completions', slug: 'reference/shell-completions' },
                  ],
              },
              {
                  label: 'Migration Guides',
                  items: [
                      { label: 'From Make', slug: 'guides/migrating-from-make' },
                      { label: 'From Just', slug: 'guides/migrating-from-just' },
                  ],
              },
              {
                  label: 'Cookbook',
                  autogenerate: { directory: 'examples' },
              },
          ],
      }),
	],

  vite: {
    plugins: [tailwindcss()],
  },
});