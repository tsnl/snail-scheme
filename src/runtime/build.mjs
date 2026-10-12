// Node implements the CLI build effects. Each call borrows one argument-vector
// root and returns a distinct owned result. No root survives a host operation.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { constants, tmpdir } from 'node:os';

// ---- Scheme values at the ABI boundary ----

export function createBuildEffects(node) {
  const owned = new Set();
  let serial = 0;

  function arity(argumentsRoot, count) {
    if (node.exports.length(argumentsRoot) !== count)
      throw new Error(`build operation expected ${count} arguments`);
  }

  function text(root) {
    const api = node.exports;
    if (api.kind(root) !== 9) throw new Error('expected a string');
    let result = '';
    for (let index = 0; index < api.length(root); ++index)
      result += String.fromCodePoint(api.char_at(root, index));
    return result;
  }

  function stringArgument(argumentsRoot, index) {
    const root = node.exports.at(argumentsRoot, index);
    try { return text(root); }
    finally { node.exports.release(root); }
  }

  function booleanArgument(argumentsRoot, index) {
    const root = node.exports.at(argumentsRoot, index);
    try {
      if (node.exports.kind(root) !== 1) throw new Error('expected a boolean');
      return node.exports.atom_value(root) === 1;
    } finally { node.exports.release(root); }
  }

  function stringResult(value) {
    const characters = Array.from(value);
    const root = node.exports.string_new(characters.length);
    characters.forEach((character, index) =>
      node.exports.string_set(root, index, character.codePointAt(0)));
    return root;
  }

  // Own the moving list root; every child accessor returns another owned root.
  function stringsArgument(argumentsRoot, index) {
    const result = [];
    let root = node.exports.at(argumentsRoot, index);
    try {
      while (node.exports.kind(root) !== 2) {
        const item = node.exports.car(root);
        try { result.push(text(item)); }
        finally { node.exports.release(item); }
        const next = node.exports.cdr(root);
        node.exports.release(root);
        root = next;
      }
      return result;
    } finally { node.exports.release(root); }
  }

  // ---- Paths and owned build directories ----

  function absolute(argumentsRoot, index) {
    return path.resolve(node.cwd, stringArgument(argumentsRoot, index));
  }

  function metadata(filename) {
    try { return fs.statSync(filename, { bigint: true }); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  }

  function reserve(parent, prefix) {
    for (let attempts = 0; attempts < 101; ++attempts) {
      const directory = path.join(parent, `${prefix}${process.pid}-${serial++}`);
      try { fs.mkdirSync(directory, { mode: 0o700 }); return directory; }
      catch (error) { if (error.code !== 'EEXIST') throw error; }
    }
    throw new Error('cannot reserve a build directory');
  }

  function reserveBuild(argumentsRoot) {
    arity(argumentsRoot, 1);
    const root = node.exports.at(argumentsRoot, 0);
    let parent;
    try {
      if (node.exports.kind(root) === 1) {
        if (node.exports.atom_value(root) !== 0) throw new Error('expected an output path or false');
        parent = tmpdir();
      } else parent = path.dirname(path.resolve(node.cwd, text(root)));
    }
    finally { node.exports.release(root); }
    const directory = reserve(parent, '.snail-build-');
    owned.add(directory);
    return stringResult(directory);
  }

  function cleanBuild(argumentsRoot) {
    arity(argumentsRoot, 1);
    const directory = absolute(argumentsRoot, 0);
    if (!owned.has(directory)) throw new Error(`build directory is not owned: ${directory}`);
    try { fs.rmSync(directory, { recursive: true }); }
    catch (error) { console.error(`cannot clean build directory ${directory}: ${error.message}`); }
    owned.delete(directory);
    return node.exports.atom(3);
  }

  // ---- Literal process invocation and atomic publication ----

  function processStatus(argumentsRoot) {
    arity(argumentsRoot, 4);
    const argv = stringsArgument(argumentsRoot, 0);
    if (!argv.length) throw new Error('empty command');
    const result = spawnSync(argv[0], argv.slice(1), {
      cwd: absolute(argumentsRoot, 1), argv0: stringArgument(argumentsRoot, 3),
      stdio: [booleanArgument(argumentsRoot, 2) ? 'inherit' : 'ignore', 'inherit', 'inherit'],
      shell: false,
    });
    if (result.error) throw new Error(`cannot run ${JSON.stringify(argv)}: ${result.error.message}`);
    const status = result.status ?? (128 + constants.signals[result.signal]);
    return node.exports.integer(BigInt(status));
  }

  function publishBundle(argumentsRoot) {
    arity(argumentsRoot, 2);
    const bundle = absolute(argumentsRoot, 0), output = absolute(argumentsRoot, 1);
    const destination = reserve(path.dirname(output), '.snail-artifacts-');
    const link = path.join(path.dirname(bundle), 'publish');
    try { fs.renameSync(bundle, destination); }
    catch (error) { fs.rmdirSync(destination); throw error; }
    try {
      fs.symlinkSync(path.join(path.basename(destination), 'program'), link);
      fs.renameSync(link, output);
    } catch (error) {
      try { fs.renameSync(destination, bundle); }
      catch { console.error(`artifact generation retained: ${destination}`); }
      throw error;
    }
    return node.exports.atom(3);
  }

  function copyFile(argumentsRoot) {
    arity(argumentsRoot, 2);
    const source = absolute(argumentsRoot, 0), output = absolute(argumentsRoot, 1);
    if (!fs.statSync(source).isFile()) throw new Error(`artifact is not a regular file: ${source}`);
    fs.copyFileSync(source, output);
    fs.chmodSync(output, fs.statSync(source).mode & 0o7777);
    return node.exports.atom(3);
  }

  function sameFile(argumentsRoot) {
    arity(argumentsRoot, 2);
    const first = metadata(absolute(argumentsRoot, 0)), second = metadata(absolute(argumentsRoot, 1));
    return node.exports.atom(first && second && first.dev === second.dev && first.ino === second.ino ? 1 : 0);
  }

  return {
    imports: {
      'snail:%process-status': processStatus,
      'snail:%absolute-path': argumentsRoot => {
        arity(argumentsRoot, 1); return stringResult(absolute(argumentsRoot, 0));
      },
      'snail:%same-file?': sameFile,
      'snail:%create-directory*': argumentsRoot => {
        arity(argumentsRoot, 1); fs.mkdirSync(absolute(argumentsRoot, 0), { recursive: true });
        return node.exports.atom(3);
      },
      'snail:%reserve-build-directory': reserveBuild,
      'snail:%clean-build-directory': cleanBuild,
      'snail:%publish-file': argumentsRoot => {
        arity(argumentsRoot, 2); fs.renameSync(absolute(argumentsRoot, 0), absolute(argumentsRoot, 1));
        return node.exports.atom(3);
      },
      'snail:%copy-file': copyFile,
      'snail:%publish-bundle': publishBundle,
    },
    reportFailure() {
      for (const directory of owned) console.error(`build failed; intermediates retained: ${directory}`);
    },
  };
}
