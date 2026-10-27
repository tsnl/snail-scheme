// Disk is authoritative. This service owns one physical project root and no
// buffers, revisions, watchers or compiler callbacks. Small reads/saves run in
// one native turn; saves through this service cannot interleave publication.
import {createHash} from 'node:crypto';
import {closeSync, constants, fchmodSync, fstatSync, lstatSync, mkdirSync, mkdtempSync,
  openSync, readSync, realpathSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {join, relative, sep} from 'node:path';

const limit = 8 * 1024 * 1024;
const candidate = path => /\.(sld|scm|datum|html|css|js|mjs|json|svg|txt|md)$/i.test(path);
const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});

export class FileConflict extends Error {
  constructor() { super('the file changed on disk; reload it before saving'); }
}

export class ProjectFileError extends Error {}

function revision(stat, bytes) {
  return `${stat.dev}:${stat.ino}:${createHash('sha256').update(bytes).digest('hex')}`;
}

function stable(before, after) {
  return before.dev === after.dev && before.ino === after.ino && before.mode === after.mode
    && before.size === after.size && before.mtimeNs === after.mtimeNs && before.ctimeNs === after.ctimeNs;
}

// Bound the actual read, not only the initial size check. A growing file cannot
// turn one synchronous request into an unbounded read/allocation.
function readBytes(fd, stat) {
  if (!stat.isFile()) throw new ProjectFileError('expected a regular project file');
  if (stat.size > BigInt(limit)) throw new ProjectFileError('text files may contain at most 8 MiB');
  const bytes = Buffer.allocUnsafe(Number(stat.size) + 1);
  let length = 0;
  while (length < bytes.length) {
    const count = readSync(fd, bytes, length, bytes.length - length, length);
    if (!count) return bytes.subarray(0, length);
    length += count;
  }
  throw new FileConflict();
}

function decode(bytes) {
  let text;
  try { text = decoder.decode(bytes); }
  catch { throw new ProjectFileError('expected valid UTF-8 text'); }
  if (text.includes('\0')) throw new ProjectFileError('text files cannot contain NUL bytes');
  return text;
}

function encode(text) {
  if (typeof text !== 'string' || !text.isWellFormed() || text.includes('\0')) throw new ProjectFileError('expected well-formed text without NUL');
  if (Buffer.byteLength(text, 'utf8') > limit) throw new ProjectFileError('text files may contain at most 8 MiB');
  return Buffer.from(text, 'utf8');
}

export function projectFiles(project) {
  project = realpathSync(project);
  if (!lstatSync(project).isDirectory()) throw new ProjectFileError('expected a project directory');

  // No normalized aliases or traversal. Root build output is reserved; a
  // source directory such as src/build remains an ordinary project directory.
  function parse(path) {
    if (typeof path !== 'string' || !path.isWellFormed() || path.includes('\\') || path.includes('\0')) return null;
    const parts = path.split('/');
    if (parts.some(part => !part || part === '.' || part === '..' || part === '.git') || parts[0] === 'build' || !candidate(path)) return null;
    return {path, parts, absolute: join(project, ...parts)};
  }

  function requiredFile(path) {
    const file = parse(path);
    if (!file) throw new ProjectFileError('invalid project text path');
    return file;
  }

  function checkParents(file) {
    let directory = project;
    if (!lstatSync(directory).isDirectory()) throw new ProjectFileError('the project root must remain a directory');
    for (const part of file.parts.slice(0, -1)) {
      directory = join(directory, part);
      if (!lstatSync(directory).isDirectory()) throw new ProjectFileError('project paths cannot traverse symlinks or non-directories');
    }
  }

  function snapshot(file) {
    checkParents(file);
    const fd = openSync(file.absolute, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    try {
      const before = fstatSync(fd, {bigint: true}), bytes = readBytes(fd, before);
      if (!stable(before, fstatSync(fd, {bigint: true})) || !stable(before, lstatSync(file.absolute, {bigint: true}))) throw new FileConflict();
      return {bytes, revision: revision(before, bytes), mode: Number(before.mode) & 0o777};
    } finally { closeSync(fd); }
  }

  function expect(file, expected) {
    let current;
    try { current = snapshot(file); }
    catch (error) {
      if (error instanceof ProjectFileError || ['ENOENT', 'ENOTDIR', 'ELOOP'].includes(error.code)) throw new FileConflict();
      throw error;
    }
    if (current.revision !== expected) throw new FileConflict();
    return current;
  }

  function staging() {
    const build = join(project, 'build'), stat = lstatSync(build, {throwIfNoEntry: false});
    if (stat && !stat.isDirectory()) throw new ProjectFileError('project build output must be a directory, not a link');
    mkdirSync(build, {recursive: true});
    return mkdtempSync(join(build, '.snail-edit-'));
  }

  // No source/public temporary files: the existing build exclusion also keeps
  // partial editor writes out of compilation and browser artifact bundles.
  // Rename is atomic, not compare-and-replace. External writers can race the
  // final check; portable path operations do not sandbox hostile local writers.
  function save(path, expected, text) {
    const file = requiredFile(path), bytes = encode(text);
    expect(file, expected);
    const directory = staging(), temporary = join(directory, 'contents');
    try {
      const fd = openSync(temporary, 'wx', 0o600);
      let saved;
      try {
        writeFileSync(fd, bytes);
        saved = {text, revision: revision(fstatSync(fd, {bigint: true}), bytes)};
        fchmodSync(fd, expect(file, expected).mode);
      } finally { closeSync(fd); }
      renameSync(temporary, file.absolute); // EXDEV fails safely on a nested mount.
      return saved; // Evidence belongs to submitted bytes, not a later disk read.
    } finally {
      try { rmSync(directory, {recursive: true, force: true}); } catch {} // Preserve primary failure or completed publication.
    }
  }

  // The shared observer supplies regular filenames from a complete scan.
  // Listing filters names only; read/save still establish current disk evidence.
  function list(paths) {
    if (!lstatSync(project).isDirectory()) throw new ProjectFileError('the project root must remain a directory');
    return paths.flatMap(absolute => {
      const file = parse(relative(project, absolute).split(sep).join('/'));
      return file ? [file.path] : [];
    }).sort();
  }

  return {
    project,
    list,
    read(path) { const {bytes, revision} = snapshot(requiredFile(path)); return {text: decode(bytes), revision}; },
    save,
  };
}
