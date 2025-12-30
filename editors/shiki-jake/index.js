/**
 * Shiki syntax highlighting for Jake
 *
 * Usage:
 *   import { createHighlighter } from 'shiki';
 *   import jake from 'shiki-jake';
 *
 *   const highlighter = await createHighlighter({
 *     themes: ['github-dark'],
 *     langs: [jake]
 *   });
 *
 *   const html = highlighter.codeToHtml(code, { lang: 'jake', theme: 'github-dark' });
 */

const fs = require('fs');
const path = require('path');

// Load the TextMate grammar
const grammarPath = path.join(__dirname, 'jake.tmLanguage.json');
const grammar = JSON.parse(fs.readFileSync(grammarPath, 'utf8'));

/**
 * Jake language definition for Shiki
 */
const jake = {
  id: 'jake',
  scopeName: 'source.jake',
  aliases: ['jakefile'],
  path: grammarPath,
  grammar: grammar
};

module.exports = jake;
module.exports.default = jake;
