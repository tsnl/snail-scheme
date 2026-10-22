// A project is a name and its text files by relative path. It lives in
// local storage, so a reload keeps it, and may come from a folder on disk,
// which saving then writes back to. The folder's handle survives a reload in
// IndexedDB, the one storage that can hold it; writing asks for permission
// again after a reload.

const projectKey = 'lofi-ide:project';

// ---- Storage ----

export function loadProject(sample) {
  try {
    return JSON.parse(localStorage.getItem(projectKey)) ?? sample;
  } catch {
    return sample;
  }
}

// `folder` says whether the project came from a folder that saving writes
// back to.
export function storeProject(project) {
  localStorage.setItem(projectKey, JSON.stringify({name: project.name, files: project.files, folder: Boolean(project.folder)}));
}

// ---- Folders ----

// The files a project keeps: sources and the text files a page loads.
const textFile = /\.(sld|scm|html|css|js|mjs|json|svg|txt|md)$/;
const skipped = name => name.startsWith('.') || name === 'build' || name === 'node_modules';

// Asks for a folder and reads its text files: with write access where the
// browser offers it, else through a file input, read only.
export async function chooseFolder(input) {
  if (!('showDirectoryPicker' in window)) return readInput(input);
  const handle = await showDirectoryPicker({mode: 'readwrite'});
  return {name: handle.name, files: await readDirectory(handle, ''), handle};
}

async function readDirectory(handle, prefix) {
  const files = {};
  for await (const [name, entry] of handle.entries()) {
    if (skipped(name)) continue;
    if (entry.kind === 'directory') Object.assign(files, await readDirectory(entry, `${prefix}${name}/`));
    else if (textFile.test(name)) files[`${prefix}${name}`] = await (await entry.getFile()).text();
  }
  return files;
}

function readInput(input) {
  return new Promise(resolve => {
    input.onchange = async () => {
      const files = {}, chosen = [...input.files];
      for (const file of chosen) {
        const [, ...parts] = file.webkitRelativePath.split('/');
        if (!parts.some(skipped) && textFile.test(file.name)) files[parts.join('/')] = await file.text();
      }
      resolve({name: chosen[0]?.webkitRelativePath.split('/')[0] ?? 'project', files, handle: null});
    };
    input.click();
  });
}

// Writes a file back to the folder, making its directories as needed.
export async function writeToFolder(handle, path, text) {
  if (await handle.requestPermission({mode: 'readwrite'}) !== 'granted') throw new Error(`no permission to write to ${handle.name}`);
  const parts = path.split('/');
  let directory = handle;
  for (const part of parts.slice(0, -1)) directory = await directory.getDirectoryHandle(part, {create: true});
  const writable = await (await directory.getFileHandle(parts.at(-1), {create: true})).createWritable();
  await writable.write(text);
  await writable.close();
}

// ---- The folder's handle ----

function handles(mode) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('lofi-ide', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('handles');
    request.onsuccess = () => resolve(request.result.transaction('handles', mode).objectStore('handles'));
    request.onerror = () => reject(request.error);
  });
}

export async function rememberFolder(handle) {
  const store = await handles('readwrite');
  await new Promise(resolve => { store.put(handle, 'project').onsuccess = resolve; });
}

export async function recallFolder() {
  try {
    const store = await handles('readonly');
    return await new Promise(resolve => { const request = store.get('project'); request.onsuccess = () => resolve(request.result ?? null); });
  } catch {
    return null;
  }
}
