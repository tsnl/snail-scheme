// One editor pane: a text area whose own text is invisible, over a layer
// that draws the text highlighted and one that draws the last build's
// diagnostic as a squiggle, beside a gutter of line numbers. Several panes
// may show one buffer, a project file as the IDE holds it: `{path, text,
// saved, diagnostic}`, where a diagnostic is `{line, column, message}`,
// counting from 1. Tab and Enter indent as Emacs does, through the
// formatter; every change goes through the browser's own editing, so undo
// keeps it.

// ---- Panes ----

// `actions` hears of a pane's input and focus and its header's buttons,
// each with the editor.
export function createEditor(formatter, actions) {
  const editor = {buffer: null, lines: 0};
  const parts = paneParts(editor, actions), {textarea} = parts;
  editor.element = parts.element;
  textarea.addEventListener('input', () => actions.input(editor, textarea.value));
  textarea.addEventListener('focus', () => actions.focus(editor));
  textarea.addEventListener('scroll', () => {
    scrollLayers(parts);
    if (!parts.frame) parts.frame = requestAnimationFrame(() => { parts.frame = null; drawHighlight(parts, editor.buffer.text); });
  });
  parts.formatter = formatter;
  textarea.addEventListener('keydown', event => keyDown(event, textarea, formatter));
  parts.diagnostic.addEventListener('click', () => editor.reveal(editor.buffer.diagnostic));
  Object.assign(editor, {
    show(buffer) { editor.buffer = buffer; editor.refresh(); },
    refresh() { if (textarea.value !== editor.buffer.text) setText(textarea, editor.buffer.text); draw(parts, editor); },
    focus() { textarea.focus(); },
    replaceAll(text) { replaceKeepingCaret(textarea, text); },
    reveal(place) { if (place) revealPlace(textarea, editor.buffer.text, place); },
    setActive(active) { parts.element.classList.toggle('active', active); },
  });
  return editor;
}

function paneParts(editor, actions) {
  const element = node('div', 'pane'), header = node('div', 'pane-header'), title = node('span', 'pane-title');
  const buttons = [['⇥', 'Split right', () => actions.split(editor, 'row')], ['⤓', 'Split down', () => actions.split(editor, 'column')],
                   ['×', 'Close pane', () => actions.close(editor)]].map(([text, label, handler]) => {
    const button = node('button', 'pane-button', text);
    Object.assign(button, {title: label, onmousedown: event => event.preventDefault(), onclick: handler});
    return button;
  });
  header.append(title, ...buttons);
  const body = node('div', 'editor'), gutter = node('div', 'gutter'), gutterContent = node('div', 'gutter-content');
  const numbers = node('pre', 'numbers'), marker = node('div', 'gutter-marker'), code = node('div', 'code');
  const highlight = node('pre', 'highlight'), marks = node('pre', 'marks');
  const textarea = Object.assign(node('textarea'), {spellcheck: false, wrap: 'off', autocapitalize: 'off'});
  gutterContent.append(numbers, marker);
  gutter.append(gutterContent);
  code.append(highlight, marks, textarea);
  body.append(gutter, code);
  const diagnostic = node('div', 'pane-diagnostic');
  element.append(header, body, diagnostic);
  return {element, title, gutterContent, numbers, marker, highlight, marks, textarea, diagnostic};
}

function node(tag, className = '', text = '') {
  return Object.assign(document.createElement(tag), {className, textContent: text});
}

// ---- Drawing ----

function draw(parts, editor) {
  const {buffer} = editor;
  parts.title.textContent = buffer.path + (buffer.text === buffer.saved ? '' : ' ●');
  const lines = buffer.text.split('\n').length;
  if (lines !== editor.lines) parts.numbers.textContent = Array.from({length: lines}, (_, index) => index + 1).join('\n');
  editor.lines = lines;
  drawHighlight(parts, buffer.text);
  drawDiagnostic(parts, buffer);
  scrollLayers(parts);
}

// The highlight layer holds the lines in view, and a few around them, in
// runs of one class each. The formatter's lexer reads them from the start of
// their top-level form, as Emacs resynchronizes; if it fails, the text stays
// plain, so it never disappears.
function drawHighlight(parts, text) {
  const {textarea, highlight} = parts, height = lineHeight(textarea);
  const first = Math.max(0, Math.floor(textarea.scrollTop / height) - 10), count = Math.ceil(textarea.clientHeight / height) + 20;
  const start = lineOffset(text, first + 1), end = lineOffset(text, first + count + 1);
  const base = topLevelStart(text, start), shown = Array.from(text.slice(start, end));
  let classes = '';
  try { classes = parts.formatter.highlight(text.slice(base, end)).slice(Array.from(text.slice(base, start)).length); } catch {}
  highlight.style.top = `${first * height}px`;
  highlight.replaceChildren(...classRuns(shown, classes));
}

function classRuns(characters, classes) {
  const runs = [];
  for (let start = 0, end; start < characters.length; start = end) {
    for (end = start + 1; end < characters.length && classes[end] === classes[start];) end++;
    const run = characters.slice(start, end).join(''), kind = classes[start];
    runs.push(kind && kind !== '.' ? Object.assign(document.createElement('span'), {className: `hl-${kind}`, textContent: run}) : run);
  }
  return runs;
}

// The start of the line at or above `start` that opens a list in its first
// column.
function topLevelStart(text, start) {
  while (start > 0 && text[start] !== '(') start = text.lastIndexOf('\n', start - 2) + 1;
  return start;
}

// The squiggle layer holds the text up to the end of the diagnostic's
// range, invisible but for the range's underline.
function drawDiagnostic(parts, {text, diagnostic}) {
  parts.marker.hidden = parts.diagnostic.hidden = !diagnostic;
  parts.marks.replaceChildren();
  if (!diagnostic) return;
  const start = lineOffset(text, diagnostic.line) + diagnostic.column - 1, end = expressionEnd(text, start);
  const squiggle = Object.assign(document.createElement('span'), {className: 'squiggle', textContent: text.slice(start, end) || ' '});
  parts.marks.append(text.slice(0, start), squiggle);
  parts.marker.style.top = `${(diagnostic.line - 1) * lineHeight(parts.textarea)}px`;
  parts.marker.title = parts.diagnostic.textContent = `${diagnostic.line}:${diagnostic.column}: ${diagnostic.message}`;
}

function scrollLayers({textarea, gutterContent, highlight, marks}) {
  gutterContent.style.transform = `translateY(${-textarea.scrollTop}px)`;
  for (const layer of [highlight, marks]) layer.style.transform = `translate(${-textarea.scrollLeft}px, ${-textarea.scrollTop}px)`;
}

function lineHeight(textarea) {
  return parseFloat(getComputedStyle(textarea).lineHeight);
}

// The offset where line `line`, counting from 1, starts.
function lineOffset(text, line) {
  let offset = 0;
  for (let number = 1; number < line; number++) {
    const newline = text.indexOf('\n', offset);
    if (newline < 0) return text.length;
    offset = newline + 1;
  }
  return offset;
}

// The compiler points at an expression's start: the squiggle covers the
// expression, or as much of it as its line holds.
function expressionEnd(text, start) {
  const newline = text.indexOf('\n', start), lineEnd = newline < 0 ? text.length : newline;
  if (text[start] !== '(') return start + (/^"(?:[^"\\]|\\.)*"?|^[^\s()";]+/.exec(text.slice(start, lineEnd))?.[0].length ?? 1);
  for (let index = start, depth = 0; index < lineEnd; index++) {
    if (text[index] === '(') depth++;
    else if (text[index] === ')' && --depth === 0) return index + 1;
  }
  return lineEnd;
}

function revealPlace(textarea, text, {line, column}) {
  const offset = lineOffset(text, line) + column - 1;
  textarea.focus();
  textarea.setSelectionRange(offset, offset);
  textarea.scrollTop = Math.max(0, (line - 5) * lineHeight(textarea));
}

// ---- Editing ----

// Replaces a range as typing would, so the browser's undo history keeps
// the change and the input event reports it.
function replaceRange(textarea, start, end, text) {
  textarea.focus();
  textarea.setSelectionRange(start, end);
  if (!document.execCommand('insertText', false, text)) {
    textarea.setRangeText(text, start, end, 'end');
    textarea.dispatchEvent(new Event('input'));
  }
}

// Another pane changed the buffer: the text changes, the caret stays.
function setText(textarea, text) {
  const {selectionStart, selectionEnd, scrollTop} = textarea;
  textarea.value = text;
  textarea.setSelectionRange(Math.min(selectionStart, text.length), Math.min(selectionEnd, text.length));
  textarea.scrollTop = scrollTop;
}

// Formatting replaces only what changed, and the caret keeps its line and
// its place after the line's indentation.
function replaceKeepingCaret(textarea, text) {
  const {value, selectionStart, scrollTop} = textarea;
  if (value === text) return;
  const line = countLines(value, 0, selectionStart), lineStart = value.lastIndexOf('\n', selectionStart - 1) + 1;
  const afterIndentation = selectionStart - lineStart - indentationOf(value.slice(lineStart));
  const {prefix, suffix} = changedRange(value, text);
  replaceRange(textarea, prefix, value.length - suffix, text.slice(prefix, text.length - suffix));
  const start = lineOffset(text, line + 1), newline = text.indexOf('\n', start);
  const caret = Math.min(start + indentationOf(text.slice(start)) + Math.max(0, afterIndentation), newline < 0 ? text.length : newline);
  textarea.setSelectionRange(caret, caret);
  textarea.scrollTop = scrollTop;
}

// The lengths of what two texts share at their start and, after that, at
// their end; what lies between changed.
function changedRange(before, after) {
  let prefix = 0, suffix = 0;
  while (prefix < before.length && prefix < after.length && before[prefix] === after[prefix]) prefix++;
  while (suffix < before.length - prefix && suffix < after.length - prefix && before.at(-1 - suffix) === after.at(-1 - suffix)) suffix++;
  return {prefix, suffix};
}

const indentationOf = text => /^[ \t]*/.exec(text)[0].length;
const countLines = (text, from, to) => text.slice(from, to).split('\n').length - 1;

// ---- Indentation ----

// Keys that finish an input method's composition belong to it.
function keyDown(event, textarea, formatter) {
  if (event.ctrlKey || event.metaKey || event.altKey || event.isComposing) return;
  if (event.key === 'Tab') { event.preventDefault(); indentSelection(textarea, formatter); }
  else if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); newlineAndIndent(textarea, formatter); }
}

// Tab indents the caret's line, or every line the selection touches but a
// last one it only reaches the start of. As in Emacs, a caret in the
// indentation moves to the line's first character, and a caret in the text
// stays with it.
function indentSelection(textarea, formatter) {
  const {value, selectionStart} = textarea;
  const selectionEnd = textarea.selectionEnd > selectionStart && value[textarea.selectionEnd - 1] === '\n' ? textarea.selectionEnd - 1 : textarea.selectionEnd;
  const change = reindent(value, formatter, selectionStart, selectionEnd);
  if (!change) return;
  const {start, end, replacement} = change, caret = selectionStart === selectionEnd;
  const column = selectionStart - start, before = indentationOf(value.slice(start)), after = indentationOf(replacement);
  if (replacement !== value.slice(start, end)) replaceRange(textarea, start, end, replacement);
  if (caret) textarea.setSelectionRange(...Array(2).fill(start + (column <= before ? after : column + after - before)));
  else textarea.setSelectionRange(start, start + replacement.length);
}

// The lines that the offsets `from` and `to` lie on, reindented. The
// formatter reads from the start of their top-level form; a blank line gets
// the indentation it would have with something on it.
function reindent(text, formatter, from, to) {
  const start = text.lastIndexOf('\n', from - 1) + 1, newline = text.indexOf('\n', to), end = newline < 0 ? text.length : newline;
  if (from === to && /^[ \t]*$/.test(text.slice(start, end))) return {start, end, replacement: ' '.repeat(lineIndentation(text, formatter, start))};
  const base = formStart(text, start), first = countLines(text, base, start), last = first + countLines(text, start, end);
  try {
    return {start, end, replacement: formatter.indent(text.slice(base, end), first, last).split('\n').slice(first, last + 1).join('\n')};
  } catch {
    return null;
  }
}

// The column the line at `start` would be indented to, found by putting a
// placeholder on it, since a formatted blank line stays empty.
function lineIndentation(text, formatter, start) {
  const placed = `${text.slice(0, start)}x${text.slice(start + indentationOf(text.slice(start)))}`;
  const newline = placed.indexOf('\n', start), end = newline < 0 ? placed.length : newline;
  const base = formStart(placed, start), line = countLines(placed, base, start);
  try {
    return indentationOf(formatter.indent(placed.slice(base, end), line, line).split('\n')[line]);
  } catch {
    return 0;
  }
}

// Emacs takes a top-level form to start at a line that opens a list in its
// first column, looking above the line it indents, so that line may belong
// to the form before it.
function formStart(text, start) {
  return start > 0 ? topLevelStart(text, text.lastIndexOf('\n', start - 2) + 1) : 0;
}

// Enter starts a new line indented for what follows the caret, and, as
// Emacs's electric indentation does, drops the spaces it leaves at the end
// of the line before.
function newlineAndIndent(textarea, formatter) {
  const {value, selectionStart, selectionEnd: end} = textarea;
  const start = selectionStart - /[ \t]*$/.exec(value.slice(0, selectionStart))[0].length;
  const skip = indentationOf(value.slice(end)), text = `${value.slice(0, start)}\n${value.slice(end + skip)}`;
  replaceRange(textarea, start, end + skip, `\n${' '.repeat(lineIndentation(text, formatter, start + 1))}`);
}
