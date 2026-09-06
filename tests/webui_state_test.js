#!/usr/bin/env node

// Deterministic state tests for src/webui/app.js. They execute the browser
// client in a Node VM with a deliberately small DOM shim, so they need neither
// a browser nor an npm dependency.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const appSource = fs.readFileSync(path.join(__dirname, '..', 'src', 'webui', 'app.js'), 'utf8');

function element() {
  let innerHTML = '';
  const el = {
    className: '',
    textContent: '',
    style: {},
    disabled: false,
    dataset: {},
    children: [],
    attributes: {},
    tagName: 'DIV',
    classList: {
      add() {},
      remove() {},
      toggle() {},
    },
    addEventListener() {},
    appendChild(child) {
      if (child && child.__fragment) {
        this.children.push(...child.children);
      } else {
        this.children.push(child);
      }
      return child;
    },
    removeChild(child) {
      const index = this.children.indexOf(child);
      if (index >= 0) this.children.splice(index, 1);
    },
    querySelector() { return null; },
    closest() { return null; },
    setAttribute(name, value) { this.attributes[name] = String(value); },
    focus() {},
    blur() {},
  };
  Object.defineProperties(el, {
    innerHTML: {
      get: () => innerHTML,
      set: value => {
        innerHTML = String(value);
        el.children = [];
      },
    },
    firstChild: { get: () => el.children[0] || null },
    scrollHeight: { get: () => el.children.length },
    scrollTop: { get: () => 0, set() {} },
    clientHeight: { get: () => 100 },
  });
  return el;
}

function boot() {
  const elements = {};
  for (const id of [
    'searchInput', 'recipeList', 'recipeCount', 'detailPanel', 'emptyState',
    'outputSection', 'detailName', 'detailStatus', 'detailTime', 'detailDesc',
    'detailDeps', 'detailGroup', 'paramsSection', 'paramsList', 'cmdBlock',
    'runBtn', 'dryRunBtn', 'stopBtn', 'output', 'statusDot', 'statusText',
    'elapsed', 'confirmTask', 'confirmMessage', 'confirmOverlay',
    'confirmCancelBtn', 'confirmOkBtn', 'copyBtn', 'clearBtn',
  ]) elements[id] = element();
  elements.searchInput.tagName = 'INPUT';
  elements.runBtn.tagName = 'BUTTON';
  elements.dryRunBtn.tagName = 'BUTTON';
  elements.stopBtn.tagName = 'BUTTON';

  const sockets = [];
  class FakeWebSocket {
    static OPEN = 1;
    constructor() {
      this.readyState = 0;
      this.sent = [];
      sockets.push(this);
    }
    send(message) { this.sent.push(JSON.parse(message)); }
  }

  const document = {
    activeElement: { tagName: 'BODY', blur() {} },
    querySelector(selector) {
      if (selector.startsWith('#')) return elements[selector.slice(1)] || null;
      return null;
    },
    querySelectorAll() { return []; },
    addEventListener() {},
    contains() { return true; },
    createElement() { return element(); },
    createDocumentFragment() { return { __fragment: true, children: [], appendChild(child) { this.children.push(child); } }; },
  };

  const context = {
    console,
    document,
    window: { CSS: { escape: value => String(value) } },
    CSS: { escape: value => String(value) },
    location: { protocol: 'http:', host: '127.0.0.1:8420' },
    localStorage: { getItem: () => null, setItem() {} },
    navigator: { clipboard: { writeText: () => Promise.resolve() } },
    WebSocket: FakeWebSocket,
    setTimeout: () => 1,
    clearTimeout() {},
    setInterval: () => 1,
    clearInterval() {},
  };
  context.globalThis = context;

  vm.runInNewContext(`${appSource}\n;globalThis.__webuiTest = {
    handle: handleServerMessage,
    run: runRecipe,
    select: selectRecipe,
    dependencyMarkup: () => document.querySelector('#detailDeps').innerHTML,
    socket: () => ws,
    state: () => ({
      running,
      activeTasks: [...activeTasks].sort(),
      runStateReady,
      launchPending,
      locked: launchIsLocked(),
      tasks: Object.fromEntries(Object.entries(taskState).map(([name, task]) => [name, {
        status: task.status,
        duration: task.duration,
        output: task.output.map(entry => entry.text),
      }])),
      controls: {
        runDisabled: $('#runBtn').disabled,
        dryRunDisabled: $('#dryRunBtn').disabled,
        stopDisplay: $('#stopBtn').style.display,
      },
    }),
  };`, context, { filename: 'app.js' });

  const api = context.__webuiTest;
  api.socket().readyState = FakeWebSocket.OPEN;
  api.socket().onopen();
  return api;
}

function init(api, names = ['root', 'dep', 'left', 'right', 'remote']) {
  api.handle({
    type: 'init',
    recipes: names.map(name => ({ name, deps: [], params: [], cmd: [] })),
  });
}

function runState(api, running, recipe = null, activeTasks = []) {
  api.handle({
    type: 'run_state',
    running,
    recipe,
    started_ms: 1_700_000_000_000,
    active_tasks: activeTasks,
  });
}

function testLaunchLockWaitsForAuthoritativeState() {
  const api = boot();
  init(api);
  assert.equal(api.state().locked, true);
  api.run('root');
  assert.equal(api.socket().sent.length, 0, 'must not launch before run_state');

  runState(api, false);
  assert.equal(api.state().locked, false);
  api.run('root');
  assert.equal(JSON.stringify(api.socket().sent), JSON.stringify([{ action: 'run', recipe: 'root', params: {}, dryRun: false }]));
  assert.equal(api.state().launchPending, 'root');
  assert.equal(api.state().locked, true, 'admission request holds the launch lock');
  api.run('root');
  assert.equal(api.socket().sent.length, 1, 'a pending admission cannot be duplicated');

  runState(api, true, 'root');
  assert.equal(api.state().running, 'root');
  assert.equal(api.state().launchPending, null);
}

function testReconnectRestoresAuthoritativeRun() {
  const api = boot();
  init(api);
  runState(api, true, 'root', ['dep']);
  api.handle({ type: 'task_start', name: 'dep', deps: [] });

  api.socket().onclose();
  assert.equal(api.state().runStateReady, false);
  assert.equal(api.state().running, null);
  assert.equal(api.state().locked, true);

  init(api);
  runState(api, true, 'root', ['dep']);
  assert.equal(api.state().running, 'root');
  assert.equal(JSON.stringify(api.state().activeTasks), JSON.stringify(['dep']));
  assert.equal(api.state().tasks.dep.status, 'running');
  assert.equal(api.state().locked, true);
}

function testDisconnectRefreshesVisibleControls() {
  const api = boot();
  init(api);
  runState(api, false);
  api.run('root');
  runState(api, true, 'root');
  assert.equal(api.state().controls.stopDisplay, 'inline-flex');
  assert.equal(api.state().controls.runDisabled, true);

  api.socket().onclose();
  assert.equal(api.state().running, null);
  assert.equal(api.state().controls.stopDisplay, 'none');
  assert.equal(api.state().controls.runDisabled, true, 'launch stays locked until reconnect state arrives');
  assert.equal(api.state().controls.dryRunDisabled, true);
}

function testParallelTasksAndSummaryStayBoundToRoot() {
  const api = boot();
  init(api);
  runState(api, false);
  api.run('root');
  runState(api, true, 'root');
  api.handle({ type: 'task_start', name: 'left', deps: [] });
  api.handle({ type: 'task_start', name: 'right', deps: [] });
  assert.equal(JSON.stringify(api.state().activeTasks), JSON.stringify(['left', 'right']));

  api.handle({ type: 'task_complete', name: 'left', success: true, duration_ms: 4 });
  assert.equal(JSON.stringify(api.state().activeTasks), JSON.stringify(['right']));
  assert.equal(api.state().locked, true);
  api.handle({ type: 'summary', recipe: 'root', tasks_run: 2, tasks_failed: 0, total_ms: 9 });
  assert.match(api.state().tasks.root.output.at(-1), /^Summary:/);
  assert.notEqual(api.state().tasks.left.output.at(-1), api.state().tasks.root.output.at(-1));
  assert.equal(api.state().locked, true, 'summary does not release the run lock');

  runState(api, false);
  assert.equal(api.state().locked, false);
  assert.equal(api.state().running, null);
}

function testRejectionCannotFailExistingRun() {
  const api = boot();
  init(api);
  runState(api, true, 'remote', ['remote']);
  api.handle({ type: 'task_start', name: 'remote', deps: [] });
  api.handle({ type: 'error', message: 'A task is already running' });
  assert.equal(api.state().tasks.remote.status, 'running');
  assert.equal(api.state().running, 'remote');
  assert.equal(api.state().locked, true);
}

function testOutputIsBounded() {
  const api = boot();
  init(api);
  for (let i = 0; i < 5005; i += 1) {
    api.handle({ type: 'output', task: 'root', line: `line-${i}`, stderr: false });
  }
  const output = api.state().tasks.root.output;
  assert.equal(output.length, 5000);
  assert.equal(output[0], 'line-5');
  assert.equal(output.at(-1), 'line-5004');
}

function testDependenciesUseNativeKeyboardButtons() {
  const api = boot();
  api.handle({ type: 'init', recipes: [{ name: 'root', deps: ['dep'], params: [], cmd: [] }] });
  api.select('root');
  assert.match(api.dependencyMarkup(), /<button type="button" class="dep-badge" data-dep="dep">dep<\/button>/);
}

for (const test of [
  testLaunchLockWaitsForAuthoritativeState,
  testReconnectRestoresAuthoritativeRun,
  testDisconnectRefreshesVisibleControls,
  testParallelTasksAndSummaryStayBoundToRoot,
  testRejectionCannotFailExistingRun,
  testOutputIsBounded,
  testDependenciesUseNativeKeyboardButtons,
]) test();

console.log('webui state tests passed');
