// A client of one native project. Disk owns saved files, buffers own drafts,
// and the service's shared observer supplies both editor and compiler updates.
import {createEditor} from './editor.mjs';
import {createFormatter} from './formatter.mjs';
import {createPanes} from './panes.mjs';

const status = document.getElementById('status'), diagnosticPanel = document.getElementById('diagnostics');
const buffers = new Map(), closedFolders = new Set();
let project = {name: '', directory: '', files: []}, listSequence = 0, diagnostics = [];
const dirty = buffer => Boolean(buffer?.baseline && buffer.text !== buffer.baseline.text);
const conflict = buffer => Boolean(buffer?.baseline && buffer.observed !== buffer.baseline.revision);
const sourceFile = buffer => /\.(sld|scm|datum)$/.test(buffer?.path ?? '');

async function request(path, options) {
  const response = await fetch(path, options), value = await response.json();
  if (!response.ok) throw Object.assign(new Error(value.message), {status: response.status});
  return value;
}

function setStatus(text, state) {
  status.textContent = status.title = text;
  status.dataset.state = state;
}

const formatter = await fetch('/format.wasm').then(response => {
  if (!response.ok) throw new Error('Could not load the formatter');
  return response.arrayBuffer();
}).then(createFormatter).catch(error => { setStatus(error.message, 'failed'); throw error; });
const panes = createPanes(document.getElementById('panes'), () => createEditor(formatter, {
  input: edited,
  diagnostic: diagnosticFor,
  focus(editor) { panes.activateEditor(editor); renderFiles(); },
  split(editor, direction) { panes.activateEditor(editor); panes.split(direction); },
  close(editor) { panes.activateEditor(editor); panes.close(); renderFiles(); },
}));

// ---- Buffers ----

// A null baseline means no disk contents have been accepted yet. Selecting
// this object is synchronous; an old read never changes a pane's selection.
async function openFile(path, diagnostic) {
  let buffer = buffers.get(path);
  if (!buffer) {
    buffer = {path, text: '', baseline: null, observed: null, saving: false, readSequence: 0, problem: '', operationError: ''};
    buffers.set(path, buffer);
  }
  const editor = panes.active.editor;
  editor.show(buffer);
  renderFiles();
  if (!buffer.baseline || diagnostic) await refreshBuffer(buffer);
  if (panes.active.editor !== editor || editor.buffer !== buffer) return;
  editor.focus();
  if (diagnostic && diagnosticFor(buffer) === diagnostic) editor.reveal(diagnostic.source);
}

function refreshEditors(buffer) {
  for (const editor of panes.editors()) if (!buffer || editor.buffer === buffer) editor.refresh();
  renderFiles();
}

function edited(editor, text) {
  const buffer = editor.buffer;
  if (!buffer?.baseline) return;
  buffer.text = text;
  refreshEditors(buffer);
  if (!dirty(buffer) && conflict(buffer)) void refreshBuffer(buffer);
}

// Listing and file reads certify different observations. Only a current file
// GET returning 404 removes a buffer; a missing tree entry never does so.
async function refreshProject() {
  const sequence = ++listSequence;
  for (const buffer of buffers.values()) void refreshBuffer(buffer);
  try {
    const current = await request('/api/project');
    if (sequence !== listSequence) return;
    project = current;
    renderDiagnostics();
    refreshEditors(null);
    if (!buffers.size && project.files.length) openFile(project.files.includes('main.sld') ? 'main.sld' : project.files[0]);
  } catch (error) { if (sequence === listSequence) setStatus(error.message, 'failed'); }
}

async function refreshBuffer(buffer) {
  if (buffer.saving) return;
  const sequence = ++buffer.readSequence;
  const diagnostic = diagnosticAt(buffer.path), observation = diagnostic?.observation;
  const current = () => sequence === buffer.readSequence && buffers.get(buffer.path) === buffer;
  refreshEditors(buffer); // Starting a read withdraws the previous observation.
  try {
    const snapshot = await request('/api/file?path=' + encodeURIComponent(buffer.path));
    if (!current()) return;
    buffer.observed = snapshot.revision;
    if (!dirty(buffer)) { buffer.text = snapshot.text; buffer.baseline = snapshot; }
    if (diagnosticAt(buffer.path) === diagnostic && diagnostic &&
        (observation === undefined || observation?.revision === snapshot.revision)) {
      diagnostic.observation = {revision: snapshot.revision, sequence};
    }
    buffer.problem = conflict(buffer) ? 'Changed on disk. Your draft is kept; Reload discards it.' : '';
  } catch (error) {
    if (!current()) return;
    buffer.problem = error.message;
    if (error.status === 404) {
      buffer.observed = null;
      if (!dirty(buffer)) {
        buffers.delete(buffer.path);
        for (const editor of panes.editors()) if (editor.buffer === buffer) editor.show(null);
      } else buffer.problem = 'Deleted on disk. Your draft is kept; copy it before reloading.';
    }
  }
  refreshEditors(buffer);
}

// ---- Saving ----

// Operation errors survive background reads until another explicit operation.
// One in-flight save per buffer. Its response changes the baseline, never
// newer typing. Reads begun before the save cannot replace this evidence.
async function save() {
  const editor = panes.active.editor, buffer = editor.buffer;
  if (!buffer?.baseline || buffer.saving) return;
  if (sourceFile(buffer)) formatPane(editor); // Formatting failure must not prevent saving an incomplete draft.
  const text = buffer.text, revision = buffer.baseline.revision;
  buffer.saving = true; buffer.readSequence++; buffer.operationError = '';
  const diagnostic = diagnosticAt(buffer.path);
  if (diagnostic) diagnostic.observation = null; // Save cannot rebind an earlier failure to its new text.
  refreshEditors(buffer);
  try {
    const snapshot = await request('/api/file?path=' + encodeURIComponent(buffer.path), {
      method: 'PUT', headers: {'Content-Type': 'text/plain; charset=utf-8', 'If-Match': `"${revision}"`}, body: text,
    });
    buffer.baseline = snapshot; buffer.observed = snapshot.revision;
  } catch (error) {
    buffer.operationError = error.status === 409 ? 'Changed on disk; save rejected. Your draft is kept.' : error.message;
  } finally {
    buffer.saving = false; buffer.readSequence++;
    refreshEditors(buffer);
    void refreshBuffer(buffer); // Also after failure: the write may have reached disk.
  }
}

function formatPane(editor) {
  if (!editor.buffer?.baseline || !sourceFile(editor.buffer)) return;
  editor.buffer.operationError = '';
  try { editor.replaceAll(formatter.format(editor.buffer.text)); }
  catch (error) { editor.buffer.operationError = error.message; }
  refreshEditors(editor.buffer);
}

function reload() {
  const buffer = panes.active.editor.buffer;
  if (!buffer || buffer.saving) return;
  if (dirty(buffer) && !confirm('Discard this file’s unsaved changes and reload from disk?')) return;
  // Discard now: any later watcher read can load disk, while typing after
  // this point becomes a new draft and survives that read.
  if (buffer.baseline) buffer.text = buffer.baseline.text;
  buffer.operationError = '';
  refreshEditors(buffer);
  void refreshBuffer(buffer);
}

addEventListener('beforeunload', event => { if ([...buffers.values()].some(dirty)) event.preventDefault(); });

// ---- Files ----

function renderFiles() {
  const nav = document.getElementById('files'), heading = document.createElement('h2');
  heading.textContent = project.name || 'Project';
  nav.replaceChildren(heading, treeElement(fileTree(project.files), ''));
  const unlisted = [...buffers.keys()].filter(path => !project.files.includes(path));
  if (unlisted.length) {
    const label = document.createElement('h2'); label.textContent = 'Open files';
    nav.append(label, ...unlisted.map(path => fileButton(path, path)));
  }
  document.getElementById('project').textContent = project.name;
  const buffer = panes.active.editor.buffer;
  document.getElementById('save').disabled = !buffer?.baseline || buffer.saving;
  document.getElementById('reload').disabled = !buffer || buffer.saving;
  document.getElementById('format').disabled = !buffer?.baseline || !sourceFile(buffer);
}

function fileTree(paths) {
  const root = Object.create(null);
  for (const path of paths) {
    const parts = path.split('/'); let node = root;
    for (const part of parts.slice(0, -1)) node = node[part] ??= Object.create(null);
    node[parts.at(-1)] = path;
  }
  return root;
}

function treeElement(tree, prefix) {
  const list = document.createElement('ul');
  const entries = Object.entries(tree).sort(([a, x], [b, y]) => (typeof x === typeof y ? a.localeCompare(b) : typeof x === 'string' ? 1 : -1));
  for (const [name, value] of entries) {
    const item = document.createElement('li');
    item.append(typeof value === 'string' ? fileButton(name, value) : folderElement(name, value, `${prefix}${name}/`));
    list.append(item);
  }
  return list;
}

function folderElement(name, tree, path) {
  const details = document.createElement('details'), summary = document.createElement('summary');
  summary.textContent = name; details.open = !closedFolders.has(path);
  details.ontoggle = () => (details.open ? closedFolders.delete(path) : closedFolders.add(path));
  details.append(summary, treeElement(tree, path));
  return details;
}

function fileButton(name, path) {
  const button = document.createElement('button'), buffer = buffers.get(path);
  button.className = 'file'; button.dataset.path = path; button.textContent = name;
  button.classList.toggle('active', panes.active.editor.buffer?.path === path);
  button.classList.toggle('dirty', dirty(buffer));
  button.classList.toggle('conflict', conflict(buffer));
  button.title = buffer?.operationError || buffer?.problem || path;
  button.onclick = () => openFile(path);
  return button;
}

// ---- Builds ----

// A point binds to a fresh editor read after its failure arrives. Later reads
// withdraw it until they confirm that same revision; Save invalidates it.
// This observation is not proof of the compiler's exact filesystem snapshot.
// Generated scratch and library sources remain readable messages; they are
// never silently mapped onto a project file.
function sourcePath(source) {
  const prefix = project.directory.endsWith('/') ? project.directory : project.directory + '/';
  const path = source?.file.startsWith(prefix) ? source.file.slice(prefix.length) : null;
  return project.files.includes(path) ? path : null;
}

const diagnosticAt = path => diagnostics.find(diagnostic => sourcePath(diagnostic.source) === path);

function diagnosticFor(buffer) {
  if (!buffer?.baseline || dirty(buffer) || conflict(buffer)) return null;
  const diagnostic = diagnosticAt(buffer.path), observation = diagnostic?.observation;
  return observation?.revision === buffer.baseline.revision && observation.sequence === buffer.readSequence ? diagnostic : null;
}

function renderDiagnostics() {
  diagnosticPanel.replaceChildren(...diagnostics.map(diagnostic => {
    const {source} = diagnostic, path = sourcePath(source);
    const element = document.createElement(path ? 'button' : 'div');
    const location = source ? `${path ?? source.file}:${source.line}:${source.column}: ` : '';
    element.textContent = `${diagnostic.severity}: ${location}${diagnostic.message}`;
    if (path) element.onclick = () => { void openFile(path, diagnostic); };
    return element;
  }));
  diagnosticPanel.hidden = !diagnostics.length;
}

function received(current) {
  diagnostics = current.diagnostics;
  renderDiagnostics();
  refreshEditors(null);
  if (diagnostics.length) for (const buffer of buffers.values()) void refreshBuffer(buffer);
  const text = {starting: 'Starting the compiler…', building: 'Building…', succeeded: 'Built', failed: 'Build failed', fatal: 'Compiler stopped'};
  setStatus(text[current.phase] ?? current.phase, ['failed', 'fatal'].includes(current.phase) ? 'failed' : current.phase === 'succeeded' ? 'built' : current.phase);
  status.dataset.attempt = current.id;
}

async function build() {
  try { await request('/api/build', {method: 'POST'}); }
  catch (error) { setStatus(error.message, 'failed'); }
}

let events;
function connect() {
  events?.close();
  events = new EventSource('/api/events');
  events.addEventListener('status', event => received(JSON.parse(event.data)));
  events.addEventListener('files', () => { void refreshProject(); });
  events.onerror = () => setStatus('Connection lost; reconnecting…', 'failed');
}
// An existing stream can survive offline while a file GET fails. Going online
// obtains both current status and files even without a transport-level retry.
addEventListener('online', connect);
connect();

// ---- Layout ----

function toggleFiles() {
  const hidden = document.querySelector('.project-layout').classList.toggle('no-files');
  document.getElementById('toggle-files').setAttribute('aria-pressed', String(!hidden));
}

function dragFiles(event) {
  const layout = document.querySelector('.project-layout');
  const move = ({clientX}) => layout.style.setProperty('--files-width', `${Math.max(120, Math.min(innerWidth * 0.7, clientX))}px`);
  const stop = () => { removeEventListener('pointermove', move); removeEventListener('pointerup', stop); };
  event.preventDefault();
  addEventListener('pointermove', move); addEventListener('pointerup', stop);
}

document.getElementById('files-resizer').addEventListener('pointerdown', dragFiles);
const toolbar = {
  'toggle-files': toggleFiles, save, reload, build, format: () => formatPane(panes.active.editor),
  'split-right': () => panes.split('row'), 'split-down': () => panes.split('column'),
};
for (const [id, action] of Object.entries(toolbar)) {
  const button = document.getElementById(id);
  button.onmousedown = event => event.preventDefault(); button.onclick = action;
}

function shortcut({code, shiftKey, altKey}) {
  return code === 'KeyS' ? save : code === 'KeyF' && shiftKey ? toolbar.format
    : code === 'KeyB' && !altKey ? toolbar['toggle-files']
      : code === 'Backslash' ? (shiftKey ? toolbar['split-down'] : toolbar['split-right']) : null;
}

addEventListener('keydown', event => {
  const action = (event.ctrlKey || event.metaKey) && shortcut(event);
  if (!action) return;
  event.preventDefault(); action();
});
panes.active.editor.show(null);
renderFiles();
setStatus('Connecting…', 'starting');
