// The browser IDE: a toolbar above a file browser docked on the left, a tree
// of editor panes. The toolchain runs in a worker (toolchain.mjs), compiler
// included. Each edit,
// saved or not, goes to it, and each build's events come back: a failure
// puts a squiggle under what the compiler points at. Saving formats a source
// file, keeps the project in storage, and writes the file back to its folder.
import {createEditor} from './editor.mjs';
import {createFormatter} from './formatter.mjs';
import {readEvent} from './load.mjs';
import {createPanes} from './panes.mjs';
import {chooseFolder, loadProject, recallFolder, rememberFolder, storeProject, writeToFolder} from './project.mjs';

const fetchBytes = async url => new Uint8Array(await (await fetch(url)).arrayBuffer());
const [library, sample, formatter] = await Promise.all([
  fetch('files.json').then(response => response.json()), fetch('sample.json').then(response => response.json()),
  fetchBytes('format.wasm').then(createFormatter)]);
const project = loadProject(sample);
const folder = project.folder ? await recallFolder() : null;
const worker = new Worker(new URL('./toolchain.mjs', import.meta.url), {type: 'module'});
const status = document.getElementById('status');

// ---- Buffers ----

// A project file as the IDE holds it: its text, the text last saved, and
// the last build's diagnostic in it.
const buffers = new Map();
let diagnostic = null;

function bufferFor(path) {
  if (!buffers.has(path)) buffers.set(path, {path, text: project.files[path], saved: project.files[path], diagnostic: null});
  return buffers.get(path);
}

const dirty = buffer => buffer.text !== buffer.saved;

// A pane's edit: every pane on the buffer shows it, and the toolchain builds
// from it.
function edited(editor, text) {
  const {buffer} = editor, wasDirty = dirty(buffer);
  buffer.text = text;
  refreshEditors(buffer);
  if (dirty(buffer) !== wasDirty) renderFiles();
  worker.postMessage({type: 'write', path: buffer.path, text});
}

function refreshEditors(buffer) {
  for (const editor of panes.editors()) if (!buffer || editor.buffer === buffer) editor.refresh();
}

function openFile(path, place) {
  const {editor} = panes.active;
  editor.show(bufferFor(path));
  editor.focus();
  editor.reveal(place);
  renderFiles();
}

// ---- Panes ----

const panes = createPanes(document.getElementById('panes'), () => createEditor(formatter, {
  input: edited,
  focus(editor) { panes.activateEditor(editor); renderFiles(); },
  split(editor, direction) { panes.activateEditor(editor); panes.split(direction); },
  close(editor) { panes.activateEditor(editor); panes.close(); renderFiles(); },
}));
panes.active.editor.show(bufferFor('main.sld' in project.files ? 'main.sld' : Object.keys(project.files).sort()[0]));

// ---- Files ----

// The project's files as a tree of folders. A file is marked when a pane
// shows it, when it has unsaved changes, and when the last build failed in it.
const closedFolders = new Set();

function renderFiles() {
  const nav = document.getElementById('files'), heading = document.createElement('h2');
  heading.textContent = project.name + (folder ? '' : ' (in this browser)');
  nav.replaceChildren(heading, treeElement(fileTree(Object.keys(project.files)), ''));
  document.getElementById('project').textContent = project.name;
}

function fileTree(paths) {
  const root = {};
  for (const path of paths) {
    const parts = path.split('/');
    let node = root;
    for (const part of parts.slice(0, -1)) node = node[part] ??= {};
    node[parts.at(-1)] = path;
  }
  return root;
}

// Folders first, then files, each by name.
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
  summary.textContent = name;
  details.open = !closedFolders.has(path);
  details.ontoggle = () => (details.open ? closedFolders.delete(path) : closedFolders.add(path));
  details.append(summary, treeElement(tree, path));
  return details;
}

function fileButton(name, path) {
  const button = document.createElement('button'), buffer = buffers.get(path);
  button.className = 'file';
  button.textContent = name;
  button.classList.toggle('active', panes.active.editor.buffer?.path === path);
  button.classList.toggle('dirty', Boolean(buffer && dirty(buffer)));
  button.classList.toggle('failed', diagnostic?.path === path);
  button.onclick = () => openFile(path);
  return button;
}

// ---- Builds ----

// A failure whose message starts with a project file's place becomes that
// file's diagnostic. Successful builds clear the preceding diagnostic.

function received(text) {
  const event = readEvent(text);
  if (event.kind === 'building') setStatus('Building…', 'building');
  else if (event.kind === 'built') {
    showDiagnostic(null);
    setStatus(`Built in ${event.milliseconds} ms`, 'built');
  } else if (event.kind === 'failed') {
    const found = diagnosticOf(event.message);
    showDiagnostic(found);
    setStatus(found ? `${found.path}:${found.line}:${found.column}: ${found.message}` : event.message.split('\n')[0], 'failed');
  }
}

// The compiler starts a message with the place it means:
// `/project/src/view.sld:18:18: what is wrong`.
function diagnosticOf(message) {
  const match = /^\/project\/(.+?):(\d+):(\d+): ([\s\S]*)$/.exec(message);
  return match && match[1] in project.files ? {path: match[1], line: Number(match[2]), column: Number(match[3]), message: match[4]} : null;
}

function showDiagnostic(found) {
  diagnostic = found;
  if (found) bufferFor(found.path);
  for (const buffer of buffers.values()) buffer.diagnostic = found?.path === buffer.path ? found : null;
  refreshEditors(null);
  renderFiles();
}

function setStatus(text, state) {
  status.textContent = text;
  status.dataset.state = state;
}

status.onclick = () => { if (diagnostic) openFile(diagnostic.path, diagnostic); };

// ---- Saving ----

// Saving formats a source file, keeps the project in storage, and writes
// the file back to the folder it came from.
async function save() {
  const {editor} = panes.active, {buffer} = editor;
  if (/\.(sld|scm)$/.test(buffer.path)) formatPane(editor);
  buffer.saved = project.files[buffer.path] = buffer.text;
  storeProject(project);
  refreshEditors(buffer);
  renderFiles();
  await writeBack(buffer);
}

async function writeBack(buffer) {
  try {
    if (folder) await writeToFolder(folder, buffer.path, buffer.text);
    setStatus(`Saved ${buffer.path}${folder ? ` to ${folder.name}` : ''}`, 'saved');
  } catch (error) {
    setStatus(error.message, 'failed');
  }
}

function formatPane(editor) {
  try {
    editor.replaceAll(formatter.format(editor.buffer.text));
  } catch (error) {
    setStatus(`Could not format ${editor.buffer.path}: ${error.message}`, 'failed');
  }
}

// Opening a folder replaces the project and loads the IDE again, with a new
// toolchain; unsaved changes are lost, after a warning.
let leaving = false;

async function openFolder() {
  const chosen = await chooseFolder(document.getElementById('folder-input'));
  if (!Object.keys(chosen.files).length) return setStatus(`${chosen.name} has no text files`, 'failed');
  if ([...buffers.values()].some(dirty) && !confirm('Discard the unsaved changes?')) return;
  storeProject({name: chosen.name, files: chosen.files, folder: Boolean(chosen.handle)});
  await rememberFolder(chosen.handle);
  leaving = true;
  location.reload();
}

addEventListener('beforeunload', event => { if (!leaving && [...buffers.values()].some(dirty)) event.preventDefault(); });

// ---- Layout ----

function toggleFiles() {
  const hidden = document.querySelector('.project-layout').classList.toggle('no-files');
  document.getElementById('toggle-files').setAttribute('aria-pressed', String(!hidden));
}

// Dragging the file browser's edge sets its width.
function dragFiles(event) {
  const layout = document.querySelector('.project-layout');
  const move = ({clientX}) => {
    layout.style.setProperty('--files-width', `${Math.max(120, Math.min(innerWidth * 0.7, clientX))}px`);
  };
  const stop = () => { removeEventListener('pointermove', move); removeEventListener('pointerup', stop); };
  event.preventDefault();
  addEventListener('pointermove', move);
  addEventListener('pointerup', stop);
}

document.getElementById('files-resizer').addEventListener('pointerdown', dragFiles);
const toolbar = {
  'toggle-files': toggleFiles, 'open-folder': openFolder, format: () => formatPane(panes.active.editor),
  'split-right': () => panes.split('row'), 'split-down': () => panes.split('column'),
};
for (const [id, action] of Object.entries(toolbar)) {
  const button = document.getElementById(id);
  button.onmousedown = event => event.preventDefault();
  button.onclick = action;
}

// Shortcuts take Ctrl, or Command on a Mac: S saves, Shift+F formats, B
// toggles the files, \ splits right and Shift+\ down.
function shortcut({code, shiftKey, altKey}) {
  return code === 'KeyS' ? save
    : code === 'KeyF' && shiftKey ? toolbar.format
      : code === 'KeyB' && !altKey ? toolbar['toggle-files']
        : code === 'Backslash' ? (shiftKey ? toolbar['split-down'] : toolbar['split-right']) : null;
}

addEventListener('keydown', event => {
  const action = (event.ctrlKey || event.metaKey) && shortcut(event);
  if (!action) return;
  event.preventDefault();
  action();
});

// ---- Starting ----

worker.onmessage = ({data}) => {
  if (data.type === 'event') received(data.text);
  else if (data.type === 'log') (data.error ? console.error : console.log)(data.text.trimEnd());
};
worker.postMessage({type: 'start', library, project: project.files});
renderFiles();
setStatus('Starting the toolchain…', 'building');
