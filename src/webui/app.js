// Jake Web UI client.
// State flows one way: WebSocket messages mutate `taskState`, renderers read it.

let ws = null;
let reconnectAttempts = 0;

let recipes = [];
let selected = null;
let taskState = {};
let running = null;
let start = 0;
let elapsedTimer = null;
let statusResetTimer = null;
let filter = '';
let paramValues = {};
let collapsedGroups = new Set();
let pendingConfirm = null;
let confirmRestoreFocus = null;

const MAX_OUTPUT_LINES = 5000;
const STATUS_RESET_MS = 15000;
const STORAGE_KEY = 'jake.webui.v1';

const $ = s => document.querySelector(s);
const $$ = s => document.querySelectorAll(s);

// ============================================================================
// Persistence
// ============================================================================

function loadUiState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
    collapsedGroups = new Set(saved.collapsed || []);
    paramValues = saved.params || {};
    filter = saved.filter || '';
    selected = saved.selected || null;
    if (filter) $('#searchInput').value = filter;
  } catch (e) { /* corrupt state is not worth breaking the UI over */ }
}

function saveUiState() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      collapsed: [...collapsedGroups],
      params: paramValues,
      filter,
      selected
    }));
  } catch (e) { /* storage full/disabled — ignore */ }
}

// ============================================================================
// WebSocket Connection
// ============================================================================

function connect() {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${protocol}//${location.host}/ws`);

  ws.onopen = () => {
    updateConnectionStatus('connected', 'Connected');
    reconnectAttempts = 0;
  };

  ws.onclose = () => {
    pendingConfirm = null;
    hideConfirm();
    // A run may still be going on the server; we just can't see it anymore.
    // Reset local run state so the UI doesn't stay locked forever.
    if (running) {
      appendTaskOutput(running, { type: 'warning', text: 'Connection lost — run state unknown' });
      Object.keys(taskState).forEach(id => {
        if (taskState[id].status === 'running') taskState[id].status = 'pending';
      });
      endRun();
      renderRecipes(true);
    }
    updateConnectionStatus('disconnected', 'Disconnected');
    const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000);
    reconnectAttempts++;
    setTimeout(connect, delay);
  };

  ws.onerror = () => {
    updateConnectionStatus('disconnected', 'Error');
  };

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);
      handleServerMessage(msg);
    } catch (e) {
      console.error('Invalid message:', event.data);
    }
  };
}

function handleServerMessage(msg) {
  switch (msg.type) {
    case 'init':
      recipes = (msg.recipes || []).map(r => ({
        id: r.name,
        group: r.external || r.group || 'other',
        desc: r.desc || '',
        deps: r.deps || [],
        params: r.params || [],
        default: r.default || false,
        cmd: r.cmd || []
      }));
      initTaskState();
      renderRecipes();
      if (selected && !taskState[selected]) selected = null;
      renderDetail();
      updateConnectionStatus('connected', 'Ready');
      break;
    case 'task_start':
      // A run may have been started by another connected client — adopt it
      // so this tab's status pill, timer, and buttons reflect reality.
      if (!running) beginRun(msg.name);
      ensureTaskState(msg.name);
      taskState[msg.name].status = 'running';
      taskState[msg.name].duration = null;
      taskState[msg.name].output = [];
      if (selected === msg.name) renderOutput();
      appendTaskOutput(msg.name, { type: 'task', text: `${msg.name}` });
      updateRecipeStatus(msg.name);
      renderDetail();
      updateStatus();
      break;
    case 'command':
      if (msg.task) appendTaskOutput(msg.task, { type: 'cmd', text: msg.cmd });
      break;
    case 'output':
      if (msg.task) appendTaskOutput(msg.task, { type: msg.stderr ? 'error' : '', text: msg.line });
      break;
    case 'task_complete':
      ensureTaskState(msg.name);
      taskState[msg.name].status = msg.success ? 'success' : 'failed';
      taskState[msg.name].duration = msg.duration_ms;
      appendTaskOutput(msg.name, {
        type: msg.success ? 'success' : 'error',
        text: `${msg.success ? 'Completed' : 'Failed'} in ${fmt(msg.duration_ms)}`
      });
      updateRecipeStatus(msg.name);
      renderDetail();
      updateStatus();
      break;
    case 'summary':
      if (running && taskState[running]) {
        appendTaskOutput(running, {
          type: 'info',
          text: `Summary: ${msg.tasks_run} tasks, ${msg.tasks_failed} failed, ${fmt(msg.total_ms)} total`
        });
      }
      pendingConfirm = null;
      hideConfirm();
      endRun();
      renderDetail();
      updateStatus();
      break;
    case 'error':
      if (running && taskState[running]) {
        appendTaskOutput(running, { type: 'error', text: msg.message || 'Unknown error' });
        taskState[running].status = 'failed';
        updateRecipeStatus(running);
        pendingConfirm = null;
        hideConfirm();
        endRun();
        renderDetail();
        updateStatus();
      }
      break;
    case 'confirm':
      pendingConfirm = {
        confirmId: msg.confirmId,
        task: msg.task,
        message: msg.message
      };
      showConfirm();
      updateStatus();
      break;
  }
}

function updateConnectionStatus(state, text) {
  $('#statusDot').className = 'status-dot ' + state;
  $('#statusText').textContent = text;
}

// ============================================================================
// Run Lifecycle
// ============================================================================

function beginRun(id) {
  clearTimeout(statusResetTimer);
  clearStaleStatuses(id);
  running = id;
  start = Date.now();
  clearInterval(elapsedTimer);
  elapsedTimer = setInterval(() => {
    $('#elapsed').textContent = fmt(Date.now() - start);
  }, 100);
}

function endRun() {
  running = null;
  clearInterval(elapsedTimer);
  elapsedTimer = null;
  scheduleStatusReset();
}

// Results from a previous run shouldn't linger: reset every finished recipe
// (except the one about to run) back to idle so ✓/✗ always refer to the
// current run.
function clearStaleStatuses(exceptId) {
  let changed = false;
  Object.keys(taskState).forEach(id => {
    if (id === exceptId) return;
    const s = taskState[id];
    if (s.status === 'success' || s.status === 'failed') {
      s.status = 'pending';
      s.duration = null;
      changed = true;
      updateRecipeStatus(id);
    }
  });
  if (changed && selected) renderDetail();
}

// After a quiet period, drift the whole UI back to its idle state.
function scheduleStatusReset() {
  clearTimeout(statusResetTimer);
  statusResetTimer = setTimeout(() => {
    if (running) return;
    clearStaleStatuses(null);
    $('#elapsed').textContent = '0.00s';
    updateStatus();
  }, STATUS_RESET_MS);
}

// ============================================================================
// Initialization
// ============================================================================

function initTaskState() {
  const previousTaskState = taskState;
  const previousParamValues = paramValues;
  const nextTaskState = {};
  const nextParamValues = {};

  recipes.forEach(r => {
    nextTaskState[r.id] = previousTaskState[r.id] || { status: 'pending', duration: null, output: [] };
    nextParamValues[r.id] = {};
    if (r.params) {
      r.params.forEach(p => {
        const previous = previousParamValues[r.id]?.[p.name];
        nextParamValues[r.id][p.name] = previous !== undefined ? previous : (p.default || '');
      });
    }
  });

  taskState = nextTaskState;
  paramValues = nextParamValues;

  if (selected && !taskState[selected]) {
    selected = recipes[0]?.id || null;
  }
  if (running && !taskState[running]) {
    endRun();
  }
}

function ensureTaskState(id) {
  if (!taskState[id]) {
    taskState[id] = { status: 'pending', duration: null, output: [] };
  }
}

function appendTaskOutput(id, entry) {
  ensureTaskState(id);
  const out = taskState[id].output;
  out.push(entry);
  const overflow = out.length - MAX_OUTPUT_LINES;
  if (overflow > 0) out.splice(0, overflow);
  if (selected === id) {
    appendOutputLine(entry, overflow > 0);
  }
}

// ============================================================================
// Event Wiring
// ============================================================================

function setupEvents() {
  $('#searchInput').addEventListener('input', e => {
    filter = e.target.value.toLowerCase();
    renderRecipes();
    saveUiState();
  });

  // Recipe list: one set of delegated listeners instead of per-item inline
  // handlers (inline handlers break on names containing quotes/backslashes).
  const list = $('#recipeList');
  list.addEventListener('click', e => {
    const play = e.target.closest('.recipe-play');
    if (play) {
      e.stopPropagation();
      runRecipe(play.closest('.recipe').dataset.id);
      return;
    }
    const title = e.target.closest('.recipe-group-title');
    if (title) {
      toggleGroup(title.dataset.group);
      return;
    }
    const recipe = e.target.closest('.recipe');
    if (recipe) selectRecipe(recipe.dataset.id);
  });
  list.addEventListener('focusin', e => {
    const recipe = e.target.closest('.recipe');
    if (recipe) selectRecipe(recipe.dataset.id);
  });

  $('#detailPanel').addEventListener('click', e => {
    const dep = e.target.closest('.dep-badge');
    if (dep) selectRecipe(dep.dataset.dep);
  });

  $('#paramsList').addEventListener('input', e => {
    const input = e.target.closest('.param-input');
    if (input && selected) {
      paramValues[selected][input.dataset.param] = input.value;
      saveUiState();
    }
  });

  $('#runBtn').addEventListener('click', () => runSelected());
  $('#dryRunBtn').addEventListener('click', () => runSelected(true));
  $('#stopBtn').addEventListener('click', stopRunning);
  $('#copyBtn').addEventListener('click', copyOutput);
  $('#clearBtn').addEventListener('click', clearOutput);
  $('#confirmCancelBtn').addEventListener('click', () => respondConfirm(false));
  $('#confirmOkBtn').addEventListener('click', () => respondConfirm(true));

  // Clicking the dimmed backdrop must not drop focus behind the modal.
  $('#confirmOverlay').addEventListener('mousedown', e => {
    if (e.target === e.currentTarget) {
      e.preventDefault();
      $('#confirmCancelBtn').focus();
    }
  });

  // Keep keyboard focus inside the confirm dialog while it is open.
  $('#confirmOverlay').addEventListener('keydown', e => {
    if (e.key !== 'Tab') return;
    const cancel = $('#confirmCancelBtn');
    const ok = $('#confirmOkBtn');
    if (e.shiftKey && document.activeElement === cancel) {
      e.preventDefault();
      ok.focus();
    } else if (!e.shiftKey && document.activeElement === ok) {
      e.preventDefault();
      cancel.focus();
    }
  });

  setupKeyboard();
}

function setupKeyboard() {
  document.addEventListener('keydown', e => {
    if (pendingConfirm) {
      // Dialog owns the keyboard: Escape declines, Enter activates the
      // focused button (Cancel by default) — no global "Enter approves".
      if (e.key === 'Escape') {
        e.preventDefault();
        respondConfirm(false);
      }
      return;
    }

    // Ctrl+K: Focus search
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
      e.preventDefault();
      $('#searchInput').focus();
      return;
    }

    const isInput = document.activeElement.tagName === 'INPUT' ||
                    document.activeElement.tagName === 'TEXTAREA';

    // Escape: blur inputs, else stop the running task
    if (e.key === 'Escape') {
      if (isInput) {
        document.activeElement.blur();
      } else if (running) {
        stopRunning();
      } else {
        document.activeElement.blur();
      }
      return;
    }

    // If search focused, arrow down goes to first recipe
    if (document.activeElement === $('#searchInput')) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const first = $('.recipe');
        if (first) first.focus();
      }
      return;
    }

    if (isInput) return;

    // Navigation through recipe list
    const recipeEls = [...$$('.recipe')];
    const current = document.activeElement;
    const idx = recipeEls.indexOf(current);

    if (e.key === 'ArrowDown' || e.key === 'j') {
      e.preventDefault();
      if (!recipeEls.length) return;
      if (idx === -1 || idx === recipeEls.length - 1) {
        recipeEls[0].focus();
      } else {
        recipeEls[idx + 1].focus();
      }
    } else if (e.key === 'ArrowUp' || e.key === 'k') {
      e.preventDefault();
      if (!recipeEls.length) return;
      if (idx <= 0) {
        recipeEls[recipeEls.length - 1].focus();
      } else {
        recipeEls[idx - 1].focus();
      }
    } else if (e.key === 'Enter' && selected) {
      const isOnRecipe = current.classList && current.classList.contains('recipe');
      const isOnButton = current.tagName === 'BUTTON';
      if (isOnRecipe || (!isOnButton && selected)) {
        e.preventDefault();
        runSelected(e.shiftKey);
      }
    }
  });
}

// ============================================================================
// Recipe List Rendering
// ============================================================================

function toggleGroup(group) {
  if (collapsedGroups.has(group)) {
    collapsedGroups.delete(group);
  } else {
    collapsedGroups.add(group);
  }
  renderRecipes(true);
  saveUiState();
}

function renderRecipes(restoreFocus = false) {
  const focusedId = document.activeElement?.dataset?.id;

  const filtered = recipes.filter(r =>
    r.id.toLowerCase().includes(filter) ||
    (r.desc && r.desc.toLowerCase().includes(filter)) ||
    (r.group && r.group.toLowerCase().includes(filter))
  );

  $('#recipeCount').textContent = filtered.length;

  const groups = {};
  filtered.forEach(r => {
    if (!groups[r.group]) groups[r.group] = [];
    groups[r.group].push(r);
  });

  let html = '';
  const sortedGroups = Object.keys(groups).sort((a, b) => {
    // External groups (Makefile, Justfile) go last
    const aExt = a === 'Makefile' || a === 'Justfile';
    const bExt = b === 'Makefile' || b === 'Justfile';
    if (aExt && !bExt) return 1;
    if (!aExt && bExt) return -1;
    return a.localeCompare(b);
  });
  for (const group of sortedGroups) {
    const items = groups[group];
    const isCollapsed = collapsedGroups.has(group);
    html += `<div class="recipe-group${isCollapsed ? ' collapsed' : ''}">`;
    html += `<div class="recipe-group-title" data-group="${escapeHtml(group)}" role="button" aria-expanded="${!isCollapsed}"><svg class="chevron" width="10" height="10" viewBox="0 0 10 10"><path d="M2 3 L5 6 L8 3" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>${escapeHtml(group)}</div>`;
    items.forEach(r => {
      const s = taskState[r.id] || { status: 'pending' };
      const badges = [];
      if (r.default) badges.push('<span class="recipe-badge default">default</span>');

      html += `
        <div class="recipe ${selected === r.id ? 'selected' : ''}"
             data-id="${escapeHtml(r.id)}"
             tabindex="0"
             role="option"
             aria-selected="${selected === r.id}">
          <span class="recipe-icon ${s.status}">${statusIcon(s.status)}</span>
          <span class="recipe-name">${escapeHtml(r.id)}</span>
          ${badges.join('')}
          <button class="recipe-play" tabindex="-1" title="Run" aria-label="Run ${escapeHtml(r.id)}">&#9654;</button>
        </div>
      `;
    });
    html += `</div>`;
  }

  $('#recipeList').innerHTML = html || '<div style="padding:20px;color:var(--text-muted);text-align:center">No recipes found</div>';

  if (restoreFocus && focusedId) {
    const el = $(`.recipe[data-id="${cssEscape(focusedId)}"]`);
    if (el) el.focus();
  }
}

function statusIcon(status) {
  return status === 'running' ? '<span class="spinner"></span>' :
         status === 'success' ? '&#10003;' :
         status === 'failed' ? '&#10007;' : '&#9675;';
}

// Update just the status icon for a recipe without full re-render
function updateRecipeStatus(id) {
  const el = $(`.recipe[data-id="${cssEscape(id)}"]`);
  if (!el) return;

  const s = taskState[id] || { status: 'pending' };
  const iconEl = el.querySelector('.recipe-icon');
  if (!iconEl) return;

  iconEl.className = `recipe-icon ${s.status}`;
  iconEl.innerHTML = statusIcon(s.status);

  el.classList.toggle('selected', selected === id);
  el.setAttribute('aria-selected', selected === id);
}

function selectRecipe(id) {
  if (selected === id) return;

  const prevEl = $(`.recipe[data-id="${cssEscape(selected)}"]`);
  if (prevEl) {
    prevEl.classList.remove('selected');
    prevEl.setAttribute('aria-selected', 'false');
  }

  selected = id;

  const newEl = $(`.recipe[data-id="${cssEscape(id)}"]`);
  if (newEl) {
    newEl.classList.add('selected');
    newEl.setAttribute('aria-selected', 'true');
  }

  renderDetail();
  saveUiState();
}

// ============================================================================
// Detail Panel Rendering
// ============================================================================

function renderDetail() {
  if (!selected) {
    $('#detailPanel').classList.remove('visible');
    $('#emptyState').style.display = 'flex';
    $('#outputSection').style.display = 'none';
    return;
  }

  const r = recipes.find(x => x.id === selected);
  if (!r) return;

  const s = taskState[selected] || { status: 'pending', output: [] };

  $('#emptyState').style.display = 'none';
  $('#detailPanel').classList.add('visible');
  $('#outputSection').style.display = 'flex';

  // Header
  $('#detailName').textContent = r.id;

  const statusClass = s.status === 'pending' ? '' : s.status;
  const statusText = s.status === 'pending' ? 'Not run' :
                     s.status === 'running' ? 'Running...' :
                     s.status === 'success' ? 'Completed' : 'Failed';
  $('#detailStatus').className = 'detail-status ' + statusClass;
  $('#detailStatus').textContent = statusText;
  $('#detailTime').textContent = s.duration != null ? fmt(s.duration) : '';

  // Body
  $('#detailDesc').textContent = r.desc || 'No description';

  // Dependencies
  if (r.deps && r.deps.length) {
    $('#detailDeps').innerHTML = `<div class="dep-list">${r.deps.map(d =>
      `<span class="dep-badge" data-dep="${escapeHtml(d)}" role="button" tabindex="0">${escapeHtml(d)}</span>`
    ).join('')}</div>`;
  } else {
    $('#detailDeps').innerHTML = '<span style="color:var(--text-muted);font-style:italic">none</span>';
  }

  // Group
  $('#detailGroup').innerHTML = `<span style="color:var(--color-purple)">${escapeHtml(r.group)}</span>`;

  // Parameters
  if (r.params && r.params.length) {
    $('#paramsSection').style.display = 'block';
    $('#paramsList').innerHTML = r.params.map(p => `
      <div class="param-row">
        <span class="param-name">${escapeHtml(p.name)}</span>
        <input type="text"
               class="param-input"
               data-param="${escapeHtml(p.name)}"
               value="${escapeHtml(paramValues[r.id]?.[p.name] || '')}"
               placeholder="${escapeHtml(p.default || 'required')}"
               aria-label="Parameter ${escapeHtml(p.name)}">
        ${p.default ? `<span class="param-default">default: ${escapeHtml(p.default)}</span>` : ''}
      </div>
    `).join('');
  } else {
    $('#paramsSection').style.display = 'none';
  }

  // Commands
  if (r.cmd && r.cmd.length) {
    const cmdHtml = r.cmd.map(c => `<div class="cmd-line">${highlightCmd(c)}</div>`).join('');
    $('#cmdBlock').innerHTML = `<div class="detail-label">Commands</div><div class="cmd-content">${cmdHtml}</div>`;
    $('#cmdBlock').style.display = 'flex';
  } else {
    $('#cmdBlock').style.display = 'none';
  }

  // Buttons
  $('#runBtn').innerHTML = s.status === 'running'
    ? '<span class="spinner"></span> Running...'
    : 'Run <span class="btn-kbd">Enter</span>';
  $('#runBtn').disabled = !!running;
  $('#stopBtn').style.display = running ? 'inline-flex' : 'none';

  renderOutput();
}

// Single-pass command highlighter: comments win over strings win over keywords.
function highlightCmd(line) {
  if (/^\s*#/.test(line)) {
    return `<span class="comment">${escapeHtml(line)}</span>`;
  }
  let html = '';
  let rest = line;
  const token = /("[^"]*")|(@\w+)/;
  while (rest.length) {
    const m = rest.match(token);
    if (!m) { html += escapeHtml(rest); break; }
    html += escapeHtml(rest.slice(0, m.index));
    if (m[1]) html += `<span class="string">${escapeHtml(m[1])}</span>`;
    else html += `<span class="keyword">${escapeHtml(m[2])}</span>`;
    rest = rest.slice(m.index + m[0].length);
  }
  return html;
}

// ============================================================================
// Output Rendering
// ============================================================================

function outputLineEl(entry) {
  const div = document.createElement('div');
  if (entry.type === 'task') {
    div.className = 'out-task';
  } else {
    div.className = 'out-line' + (entry.type ? ' ' + entry.type : '');
  }
  div.textContent = entry.text;
  return div;
}

function outputIsSticky(out) {
  return out.scrollHeight - out.scrollTop - out.clientHeight < 40;
}

// Append one line instead of rebuilding the whole pane per message; only
// follow the tail if the user hasn't scrolled up.
function appendOutputLine(entry, trimmed) {
  const out = $('#output');
  const placeholder = out.querySelector('.out-line.muted');
  if (placeholder && out.children.length === 1) out.innerHTML = '';

  const sticky = outputIsSticky(out);
  if (trimmed && out.firstChild) out.removeChild(out.firstChild);
  out.appendChild(outputLineEl(entry));
  if (sticky) out.scrollTop = out.scrollHeight;
}

function renderOutput() {
  if (!selected) return;
  const s = taskState[selected] || { output: [] };
  const out = $('#output');

  if (!s.output || s.output.length === 0) {
    out.innerHTML = '<div class="out-line muted">No output yet. Click Run to execute.</div>';
    return;
  }

  const frag = document.createDocumentFragment();
  s.output.forEach(l => frag.appendChild(outputLineEl(l)));
  out.innerHTML = '';
  out.appendChild(frag);
  out.scrollTop = out.scrollHeight;
}

function clearOutput() {
  if (selected && taskState[selected]) {
    taskState[selected].output = [];
    renderOutput();
  }
}

function copyOutput() {
  if (!selected || !taskState[selected]) return;
  const text = taskState[selected].output.map(l => l.text).join('\n');
  navigator.clipboard.writeText(text);
}

// ============================================================================
// Running Tasks
// ============================================================================

function runSelected(dryRun = false) {
  if (!selected) return;
  runRecipe(selected, dryRun);
}

function runRecipe(id, dryRun = false) {
  if (!taskState[id] || taskState[id].status === 'running' || running) return;

  selectRecipe(id);

  const s = taskState[id];
  s.status = 'running';
  s.duration = null;
  s.output = [];
  beginRun(id);

  updateRecipeStatus(id);
  renderDetail();
  updateStatus();

  if (ws && ws.readyState === WebSocket.OPEN) {
    const params = paramValues[id] || {};
    ws.send(JSON.stringify({ action: 'run', recipe: id, params, dryRun }));
    // Server responds with task_start, output, task_complete, summary.
  } else {
    appendTaskOutput(id, { type: 'error', text: 'Not connected to server' });
    s.status = 'failed';
    endRun();
    updateRecipeStatus(id);
    renderDetail();
    updateStatus();
  }
}

function stopRunning() {
  if (!running) return;

  const id = running;
  pendingConfirm = null;
  hideConfirm();

  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action: 'stop' }));
    appendTaskOutput(id, { type: 'warning', text: 'Stopping...' });
    updateStatus();
    return;
  }

  const s = taskState[id];
  s.status = 'failed';
  s.duration = Date.now() - start;
  appendTaskOutput(id, { type: 'error', text: 'Stopped by user' });
  endRun();
  updateRecipeStatus(id);
  renderDetail();
  updateStatus();
}

function updateStatus() {
  const dot = $('#statusDot');
  const txt = $('#statusText');

  if (pendingConfirm && running) {
    dot.className = 'status-dot running';
    txt.textContent = `Confirm: ${pendingConfirm.task}`;
  } else if (running) {
    dot.className = 'status-dot running';
    txt.textContent = `Running: ${running}`;
  } else {
    const success = Object.values(taskState).filter(s => s.status === 'success').length;
    const failed = Object.values(taskState).filter(s => s.status === 'failed').length;

    if (failed > 0) {
      dot.className = 'status-dot failed';
      txt.textContent = `${failed} failed`;
    } else if (success > 0) {
      dot.className = 'status-dot success';
      txt.textContent = `${success} completed`;
    } else {
      dot.className = 'status-dot connected';
      txt.textContent = 'Ready';
    }
  }
}

function showConfirm() {
  if (!pendingConfirm) return;
  $('#confirmTask').textContent = pendingConfirm.task;
  $('#confirmMessage').textContent = pendingConfirm.message;
  $('#confirmOverlay').classList.add('visible');
  confirmRestoreFocus = document.activeElement;
  $('#confirmCancelBtn').focus();
}

function hideConfirm() {
  $('#confirmOverlay').classList.remove('visible');
  if (confirmRestoreFocus && document.contains(confirmRestoreFocus)) {
    confirmRestoreFocus.focus();
  }
  confirmRestoreFocus = null;
}

function respondConfirm(approved) {
  if (!pendingConfirm) return;
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({
      action: 'confirm',
      confirmId: pendingConfirm.confirmId,
      approved
    }));
  }
  pendingConfirm = null;
  hideConfirm();
  updateStatus();
}

// ============================================================================
// Utilities
// ============================================================================

function escapeHtml(text) {
  if (!text) return '';
  return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function cssEscape(value) {
  return (window.CSS && CSS.escape) ? CSS.escape(String(value)) : String(value).replace(/["\\]/g, '\\$&');
}

function fmt(ms) { return (ms / 1000).toFixed(2) + 's'; }

// ============================================================================
// Initialize
// ============================================================================

loadUiState();
setupEvents();
connect();
