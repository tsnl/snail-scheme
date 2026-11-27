// The user's files for the `FilePicker` capability of src/snail/shell/files.sld, as
// `with-page-files` in src/snail/shell/files/page.sld calls it. Files
// dropped anywhere on the page, or chosen in a picker the program opens,
// become the latest choice and queue a FILES event; a cancelled picker
// queues nothing. Listing the choice gives each file's path within it and
// a blob: address the program fetches it from, and revokes the addresses
// of the choice listed before: a choice that arrives while the program
// still reads the last one leaves those addresses readable. A link
// dropped on the page is a file whose path is its address.
//
// A folder is walked with the File System Access API's directory handles
// where the browser has them (showDirectoryPicker), and otherwise with an
// <input webkitdirectory>; a dropped folder through its entries. Every
// path is relative to the folder: a folder chosen or dropped alone lists
// its contents, not itself.

import {byteView} from './load.mjs';

export const FILES = 17;

export function createFiles(runtime) {
  let latest = [], listed = [], reply = [], nextDownload = 1;
  const downloads = new Map();

  function arrived(files) {
    latest = files;
    runtime.send(FILES, files.length);
  }
  function reset() {
    for (const {address} of listed) URL.revokeObjectURL(address);
    latest = listed = [];
    for (const d of downloads.values()) {
      d.link.remove();
      if (d.url) URL.revokeObjectURL(d.url);
    }
    downloads.clear();
  }

  // ---- Choosing ----

  async function choose(folder) {
    if (folder && globalThis.showDirectoryPicker) return walkHandle(await showDirectoryPicker(), '');
    if (!folder && globalThis.showOpenFilePicker) {
      const handles = await showOpenFilePicker({multiple: true});
      return Promise.all(handles.map(async handle => ({path: handle.name, file: await handle.getFile()})));
    }
    return picked(folder);
  }
  async function walkHandle(directory, prefix) {
    const files = [];
    for await (const [name, handle] of directory.entries()) {
      if (handle.kind === 'file') files.push({path: prefix + name, file: await handle.getFile()});
      else files.push(...await walkHandle(handle, `${prefix}${name}/`));
    }
    return files;
  }
  // An <input type=file>, the one picker every browser has; a cancel
  // event answers nothing.
  function picked(folder) {
    const input = Object.assign(document.createElement('input'), {type: 'file', multiple: true, webkitdirectory: folder});
    return new Promise(resolve => {
      input.addEventListener('change', () => resolve([...input.files].map(file =>
        ({path: folder ? file.webkitRelativePath.replace(/^[^/]*\//, '') : file.name, file}))));
      input.addEventListener('cancel', () => resolve(null));
      input.click();
    });
  }
  // A picker opens only while the page has the user's recent activation,
  // which the key that asked for it gives. A cancelled one throws
  // AbortError; any failure leaves the last choice.
  function openPicker(folder) {
    choose(folder === 1).then(files => { if (files) arrived(files); })
      .catch(error => { if (error.name !== 'AbortError') console.warn('cannot open the picker', error); });
  }

  // ---- Dropping ----

  async function dropped(items) {
    const entries = [...items].map(item => [item.webkitGetAsEntry?.(), item.getAsFile()]);
    if (entries.length === 1 && entries[0][0]?.isDirectory) return walkEntry(entries[0][0], '');
    const files = await Promise.all(entries.map(([entry, file]) =>
      entry?.isDirectory ? walkEntry(entry, `${entry.name}/`) : [{path: file.name, file}]));
    return files.flat();
  }
  async function walkEntry(directory, prefix) {
    const reader = directory.createReader(), files = [];
    for (let batch; (batch = await new Promise((resolve, reject) => reader.readEntries(resolve, reject))).length;) {
      for (const entry of batch) {
        if (entry.isFile) files.push({path: prefix + entry.name, file: await new Promise((resolve, reject) => entry.file(resolve, reject))});
        else files.push(...await walkEntry(entry, `${prefix}${entry.name}/`));
      }
    }
    return files;
  }
  // Items must be read during the drop event; their files after it. The
  // links dropped are the lines of text/uri-list that are not comments.
  addEventListener('dragover', event => event.preventDefault());
  addEventListener('drop', event => {
    event.preventDefault();
    const links = event.dataTransfer.getData('text/uri-list').split(/\r?\n/)
      .filter(line => line && !line.startsWith('#')).map(address => ({path: address, address}));
    dropped([...event.dataTransfer.items].filter(item => item.kind === 'file'))
      .then(files => arrived([...files, ...links]))
      .catch(error => console.error('cannot read the dropped files', error));
  });

  // A text port appends to browser-owned chunks. Construct the downloadable
  // Blob on a user click, after a complete command has returned to the loop.
  function openDownload(address) {
    const name = new TextDecoder().decode(byteView(runtime.execution.entry.memory, address));
    const id = nextDownload++, link = document.createElement('a');
    const file = {link, chunks: [], pending: [], size: 0, url: null};
    link.download = name;
    link.href = '#';
    link.textContent = 'Download ' + name;
    link.style.cssText = 'position:fixed;z-index:10000;right:1rem;top:1rem;background:#202629;color:white;padding:.5rem;font:14px system-ui';
    link.addEventListener('click', () => {
      if (file.url) URL.revokeObjectURL(file.url);
      file.url = URL.createObjectURL(new Blob([...file.chunks, ...file.pending], {type: name.endsWith('.jsonl') ? 'application/x-ndjson' : 'text/plain;charset=utf-8'}));
      link.href = file.url;
    });
    document.body.append(link);
    downloads.set(id, file);
    return id;
  }
  function writeDownload(id, address) {
    const file = downloads.get(id);
    const bytes = byteView(runtime.execution.entry.memory, address).slice();
    file.pending.push(bytes);
    file.size += bytes.length;
    if (file.size >= 1024 * 1024) {
      file.chunks.push(new Blob(file.pending));
      file.pending = [];
      file.size = 0;
    }
  }

  // ---- Imports ----

  const imports = {
    'open-picker': openPicker,
    'open-download': openDownload,
    'write-download': writeDownload,
    listing() {
      for (const {address} of listed) URL.revokeObjectURL(address);
      listed = latest.map(({path, file, address}) => ({path, address: address ?? URL.createObjectURL(file)}));
      reply = [...listed.map(({path, address}) => `${path}\0${address}\0`).join('')];
      return reply.length;
    },
    'reply-scalar': index => reply[index].codePointAt(0),
  };
  return {imports, reset};
}
