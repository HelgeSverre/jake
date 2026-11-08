#!/usr/bin/env node

// Exercise cache publication through the shipped binary. Unit tests can inspect
// cache state directly; these fixtures ensure dry-runs and failed commands do
// not certify a file target or @cache-protected command for a later invocation.

const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

if (process.platform === 'win32') {
  console.log('cache lifecycle CLI tests skipped on Windows: fixtures use POSIX shell commands');
  process.exit(0);
}

const binary = path.resolve(process.env.JAKE_CACHE_LIFECYCLE_BIN || path.join(__dirname, '..', 'zig-out', 'bin', 'jake'));
const timeoutMs = 15_000;

if (!fs.existsSync(binary)) {
  throw new Error(`Jake binary not found: ${binary}. Build first or set JAKE_CACHE_LIFECYCLE_BIN.`);
}

function runJake(cwd, args, expectedStatus) {
  const result = childProcess.spawnSync(binary, args, {
    cwd,
    encoding: 'utf8',
    timeout: timeoutMs,
    killSignal: 'SIGKILL',
    env: {
      ...process.env,
      NO_COLOR: '1',
      JAKE_DRY_RUN: 'false',
      JAKE_JOBS: '1',
      JAKE_VERBOSE: 'false',
      JAKE_YES: 'false',
      JAKE_SILENT: 'false',
    },
  });
  if (result.error) {
    throw new Error(`jake ${args.join(' ')} failed to start or timed out: ${result.error.message}`);
  }
  assert.equal(
    result.status,
    expectedStatus,
    `jake ${args.join(' ')} exited unexpectedly\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
}

function withFixture(label, source, test) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `jake-cache-${label}-`));
  try {
    fs.writeFileSync(path.join(dir, 'Jakefile'), source);
    fs.writeFileSync(path.join(dir, 'input.txt'), 'old');
    test(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
  }
}

function argsFor(jobs, dryRun) {
  const args = ['-f', 'Jakefile'];
  if (jobs !== 0) args.push('-j', String(jobs));
  if (dryRun) args.push('-n');
  args.push('all');
  return args;
}

const fixtures = {
  file: [
    'file output.txt: input.txt',
    '    cp input.txt output.txt',
    '    if [ -e fail ]; then false; fi',
    'task all: [output.txt]',
    '',
  ].join('\n'),
  cache: [
    'task cached:',
    '    @cache input.txt',
    '    cp input.txt output.txt',
    '    if [ -e fail ]; then false; fi',
    'task all: [cached]',
    '',
  ].join('\n'),
};

function runLifecycle(kind, jobs, mode) {
  withFixture(`${kind}-${mode}-j${jobs}`, fixtures[kind], dir => {
    const runArgs = argsFor(jobs, false);
    runJake(dir, runArgs, 0);
    assert.equal(fs.readFileSync(path.join(dir, 'output.txt'), 'utf8'), 'old', `${kind}/j${jobs} initial build`);

    fs.writeFileSync(path.join(dir, 'input.txt'), 'new');
    if (mode === 'dry-run') {
      runJake(dir, argsFor(jobs, true), 0);
      assert.equal(fs.readFileSync(path.join(dir, 'output.txt'), 'utf8'), 'old', `${kind}/j${jobs} dry run changed output`);
      runJake(dir, runArgs, 0);
      assert.equal(fs.readFileSync(path.join(dir, 'output.txt'), 'utf8'), 'new', `${kind}/j${jobs} real retry was incorrectly certified by dry run`);
      return;
    }

    fs.writeFileSync(path.join(dir, 'fail'), '');
    runJake(dir, runArgs, 1);
    assert.equal(fs.readFileSync(path.join(dir, 'output.txt'), 'utf8'), 'new', `${kind}/j${jobs} failure did not reach the controlled copy`);
    fs.writeFileSync(path.join(dir, 'input.txt'), 'old');
    fs.rmSync(path.join(dir, 'fail'));
    runJake(dir, runArgs, 0);
    assert.equal(fs.readFileSync(path.join(dir, 'output.txt'), 'utf8'), 'old', `${kind}/j${jobs} failed run left an old certificate`);
  });
}

for (const jobs of [0, 2]) {
  for (const kind of Object.keys(fixtures)) {
    runLifecycle(kind, jobs, 'dry-run');
    runLifecycle(kind, jobs, 'failure');
  }
}

console.log('cache lifecycle CLI tests passed');
