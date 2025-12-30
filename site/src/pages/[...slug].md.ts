import type { APIRoute, GetStaticPaths } from 'astro';
import { getCollection } from 'astro:content';
import fs from 'node:fs/promises';
import path from 'node:path';

export const getStaticPaths: GetStaticPaths = async () => {
  const docs = await getCollection('docs');
  return docs.map((entry) => ({
    params: { slug: entry.id.replace(/\.mdx?$/, '') },
    props: { entry },
  }));
};

export const GET: APIRoute = async ({ props }) => {
  const { entry } = props as { entry: { id: string; body?: string; data: { title: string; description?: string } } };

  // Read the raw markdown file
  const filePath = path.join(process.cwd(), 'src/content/docs', entry.id);
  let content: string;

  try {
    content = await fs.readFile(filePath, 'utf-8');
  } catch {
    // Fallback to entry body if available
    content = entry.body || `# ${entry.data.title}\n\n${entry.data.description || ''}`;
  }

  return new Response(content, {
    headers: {
      'Content-Type': 'text/markdown; charset=utf-8',
    },
  });
};
