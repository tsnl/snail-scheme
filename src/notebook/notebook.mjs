// The notebook: cells of Scheme run one at a time in a kernel compiled to
// WebAssembly, each showing what it printed, its value and any error. The
// kernel runs in a worker (worker.mjs), so a long evaluation never freezes
// the page, and Restart stops it. Cells persist in the browser's storage,
// and import and export as plain Scheme in the percent format.

import {kernelClient, parseCells, formatCells} from './kernel.mjs';

// ---- State ----

// Each cell keeps its source and its last run: the run's number, counting
// every run since the kernel started, and what the kernel returned. A cell
// that has not run since then has no number. `generation` counts kernels,
// so runs queued for a stopped kernel are dropped.
const state = {cells: [], runs: 0, generation: 0, waiting: 0, kernel: null, url: './kernel.wasm', queue: Promise.resolve()};
const storageKey = 'lofi-notebook';

const welcome = `;; %%
;; Scheme, evaluated by a Lofi kernel in this page. Shift+Enter runs a cell
;; and moves to the next; Ctrl+Enter runs it in place.
(define (square x) (* x x))
(map square (iota 6))
;; %%
;; Typed Lofi functions are procedures here. A generator from (lofi random)
;; is an opaque value that Scheme passes back to them.
(define generator (make-random 42))
(list generator (random-below generator 100))
;; %%
(display "printed text comes first")
(sqrt 2)
`;

// ---- Kernel ----

async function startKernel() {
  const client = kernelClient(new Worker(new URL('./worker.mjs', import.meta.url), {type: 'module'}));
  await client.load(await (await fetch(state.url, {cache: 'no-store'})).arrayBuffer());
  return client;
}

// Stops the kernel, if it is running, and starts a fresh one; no cell has
// run in it.
function restart() {
  state.kernel?.then(client => client.terminate(), () => {});
  state.generation++;
  state.runs = 0;
  state.waiting = 0;
  state.queue = Promise.resolve();
  state.kernel = startKernel();
  state.kernel.catch(error => setStatus(`the kernel failed to load: ${error.message}`));
  for (const cell of state.cells) { cell.number = null; showRun(cell); }
  return state.kernel;
}

// Starts the kernel at `url` (the current one if not given) and runs again,
// in order, every cell that had run, so its definitions are rebuilt.
// Live reload calls this when the kernel's source changes.
export async function reloadKernel(url = state.url) {
  const ran = state.cells.filter(cell => cell.number !== null);
  state.url = url;
  restart();
  for (const cell of ran) enqueue(cell);
  await state.queue;
}

// ---- Running ----

// Runs wait for the runs queued before them.
function enqueue(cell) {
  const generation = state.generation;
  cell.view.root.classList.add('queued');
  state.waiting++;
  setStatus('running');
  state.queue = state.queue.then(() => generation === state.generation && run(cell, generation));
  return state.queue;
}

async function run(cell, generation) {
  let result;
  try {
    result = await (await state.kernel).evaluate(cell.view.source.value);
  } catch (error) {
    result = {ok: false, output: '', value: null, error: error.message};
  }
  if (generation === state.generation) {
    cell.number = ++state.runs;
    cell.result = result;
  }
  showRun(cell);
  state.waiting--;
  setStatus(state.waiting > 0 ? 'running' : 'ready');
}

function runAll() {
  for (const cell of state.cells) enqueue(cell);
}

// ---- Cells ----

function addCell(source, after = state.cells.length - 1) {
  const cell = {source, number: null, result: null, view: null};
  cell.view = cellView(cell);
  state.cells.splice(after + 1, 0, cell);
  arrange();
  return cell;
}

function removeCell(cell) {
  state.cells.splice(state.cells.indexOf(cell), 1);
  cell.view.root.remove();
  if (state.cells.length === 0) addCell('');
  save();
}

function moveCell(cell, offset) {
  const from = state.cells.indexOf(cell), to = from + offset;
  if (to < 0 || to >= state.cells.length) return;
  state.cells.splice(from, 1);
  state.cells.splice(to, 0, cell);
  arrange();
  cell.view.source.focus();
}

// Puts the cells' elements in the order of the cells, then saves.
function arrange() {
  for (const cell of state.cells) elements.cells.append(cell.view.root);
  save();
}

// Shift+Enter runs a cell and moves to the next one, adding one at the end;
// Ctrl+Enter or Cmd+Enter runs it in place; Tab indents.
function onKey(cell, event) {
  if (event.key === 'Enter' && (event.shiftKey || event.ctrlKey || event.metaKey)) {
    event.preventDefault();
    enqueue(cell);
    if (event.shiftKey) {
      const next = state.cells[state.cells.indexOf(cell) + 1] ?? addCell('');
      next.view.source.focus();
    }
  } else if (event.key === 'Tab' && !event.shiftKey) {
    event.preventDefault();
    event.target.setRangeText('  ', event.target.selectionStart, event.target.selectionEnd, 'end');
    fit(event.target);
  }
}

// ---- Views ----

const elements = {};

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(label, title, action) {
  const node = element('button', '', label);
  node.title = title;
  node.addEventListener('click', action);
  return node;
}

function cellView(cell) {
  const root = element('section', 'cell'), prompt = element('div', 'prompt'), source = element('textarea', 'source');
  const tools = element('div', 'tools'), output = element('div', 'output');
  source.value = cell.source;
  source.spellcheck = false;
  source.addEventListener('input', () => { fit(source); save(); });
  source.addEventListener('keydown', event => onKey(cell, event));
  tools.append(
    button('▶', 'Run (Ctrl+Enter)', () => enqueue(cell)),
    button('↑', 'Move up', () => moveCell(cell, -1)),
    button('↓', 'Move down', () => moveCell(cell, 1)),
    button('+', 'Add a cell below', () => addCell('', state.cells.indexOf(cell)).view.source.focus()),
    button('✕', 'Delete', () => removeCell(cell)));
  root.append(prompt, source, tools, output);
  requestAnimationFrame(() => fit(source));
  const view = {root, prompt, source, output};
  cell.view = view;
  showRun(cell);
  return view;
}

// A textarea as tall as its text.
function fit(textarea) {
  textarea.style.height = 'auto';
  textarea.style.height = `${textarea.scrollHeight}px`;
}

function showRun(cell) {
  const {root, prompt, output} = cell.view;
  root.classList.remove('queued');
  prompt.textContent = cell.number === null ? '[ ]' : `[${cell.number}]`;
  output.replaceChildren();
  const result = cell.number === null ? null : cell.result;
  if (!result) return;
  if (result.output) output.append(element('pre', 'printed', result.output));
  if (result.value !== null) output.append(element('pre', 'value', result.value));
  if (result.error) output.append(element('pre', 'error', result.error));
}

function setStatus(text) {
  elements.status.textContent = text;
  document.body.dataset.status = text;
}

// ---- Files ----

function save() {
  localStorage.setItem(storageKey, formatCells(state.cells.map(cell => cell.view.source.value)));
}

function load(text) {
  for (const cell of state.cells) cell.view.root.remove();
  state.cells = [];
  for (const source of parseCells(text)) addCell(source);
  if (state.cells.length === 0) addCell('');
}

function exportFile() {
  const link = element('a');
  link.href = URL.createObjectURL(new Blob([formatCells(state.cells.map(cell => cell.view.source.value))], {type: 'text/plain'}));
  link.download = 'notebook.scm';
  link.click();
  URL.revokeObjectURL(link.href);
}

function importFile() {
  const input = element('input');
  input.type = 'file';
  input.accept = '.scm,.sld,.ss,.txt';
  input.addEventListener('change', async () => { if (input.files[0]) load(await input.files[0].text()); });
  input.click();
}

// ---- Page ----

export async function startNotebook({root, url = './kernel.wasm'}) {
  state.url = url;
  elements.status = element('span', 'status');
  const toolbar = element('header', 'toolbar');
  toolbar.append(
    element('strong', 'title', 'Lofi notebook'),
    button('Run all', 'Run every cell in order', runAll),
    button('Restart', 'Stop the kernel and start a fresh one', restart),
    button('Add cell', 'Add a cell at the end', () => addCell('').view.source.focus()),
    button('Import', 'Open a Scheme file whose cells begin with ;; %%', importFile),
    button('Export', 'Save the cells as a Scheme file', exportFile),
    elements.status);
  elements.cells = element('main', 'cells');
  root.append(toolbar, elements.cells);
  load(localStorage.getItem(storageKey) ?? welcome);
  setStatus('starting');
  await restart();
  setStatus('ready');
}
