import { defineEcConfig } from 'astro-expressive-code';

// Jake grammar for syntax highlighting
const jakeGrammar = {
  name: 'jake',
  scopeName: 'source.jake',
  fileTypes: ['jake'],
  patterns: [
    { include: '#comments' },
    { include: '#directives' },
    { include: '#task-declaration' },
    { include: '#file-declaration' },
    { include: '#simple-declaration' },
    { include: '#variable-assignment' },
    { include: '#variable-expansion' },
    { include: '#strings' },
    { include: '#functions' },
  ],
  repository: {
    comments: {
      match: '#.*$',
      name: 'comment.line.number-sign.jake',
    },
    directives: {
      patterns: [
        {
          match: '@(default|desc|description|group)\\b',
          name: 'keyword.other.directive.jake',
        },
        {
          match: '@(needs|require|confirm)\\b',
          name: 'keyword.control.validation.jake',
        },
        {
          match: '@(cache|watch|ignore|quiet|cd)\\b',
          name: 'keyword.control.behavior.jake',
        },
        {
          match: '@(export|dotenv)\\b',
          name: 'keyword.control.environment.jake',
        },
        {
          match: '@(import)\\b',
          name: 'keyword.control.import.jake',
        },
        {
          match: '@(if|elif|else|end)\\b',
          name: 'keyword.control.conditional.jake',
        },
        {
          match: '@(each)\\b',
          name: 'keyword.control.loop.jake',
        },
        {
          match: '@(only-os|platform)\\b',
          name: 'keyword.control.platform.jake',
        },
        {
          match: '@(pre|post|before|after|on_error)\\b',
          name: 'keyword.control.hook.jake',
        },
      ],
    },
    'task-declaration': {
      match: '^(task)\\s+([a-zA-Z_][a-zA-Z0-9_-]*)\\s*(:)?',
      captures: {
        1: { name: 'keyword.declaration.task.jake' },
        2: { name: 'entity.name.function.jake' },
        3: { name: 'punctuation.separator.jake' },
      },
    },
    'file-declaration': {
      match: '^(file)\\s+([^:]+)\\s*(:)?',
      captures: {
        1: { name: 'keyword.declaration.file.jake' },
        2: { name: 'entity.name.function.jake' },
        3: { name: 'punctuation.separator.jake' },
      },
    },
    'simple-declaration': {
      match: '^(simple)\\s+([a-zA-Z_][a-zA-Z0-9_-]*)\\s*(:)?',
      captures: {
        1: { name: 'keyword.declaration.simple.jake' },
        2: { name: 'entity.name.function.jake' },
        3: { name: 'punctuation.separator.jake' },
      },
    },
    'variable-assignment': {
      match: '^([a-zA-Z_][a-zA-Z0-9_]*)\\s*(=)\\s*',
      captures: {
        1: { name: 'variable.other.assignment.jake' },
        2: { name: 'keyword.operator.assignment.jake' },
      },
    },
    'variable-expansion': {
      match: '\\{\\{([^}]+)\\}\\}',
      captures: {
        0: { name: 'variable.other.expansion.jake' },
        1: { name: 'variable.other.expansion.inner.jake' },
      },
    },
    strings: {
      patterns: [
        {
          begin: '"',
          end: '"',
          name: 'string.quoted.double.jake',
          patterns: [{ include: '#variable-expansion' }],
        },
        {
          begin: "'",
          end: "'",
          name: 'string.quoted.single.jake',
        },
      ],
    },
    functions: {
      match:
        '\\b(os|env|exists|eq|ne|contains|lowercase|uppercase|trim|dirname|basename|extension|without_extension|without_extensions|absolute_path|home|local_bin|shell_config|is_watching)\\s*\\(',
      captures: {
        1: { name: 'entity.name.function.builtin.jake' },
      },
    },
  },
};

export default defineEcConfig({
  shiki: {
    langs: [jakeGrammar],
  },
});
