// One project traversal and packager for cold and resident builds. The compiler
// owns parsing and cache evidence; native code owns processes and directories.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmodSync, copyFileSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  readlinkSync, renameSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {basename, join, resolve} from 'node:path';
import {createAssembler} from './assemble.mjs';
import {CompilerFailure, createCompiler} from './compiler.mjs';

// ---- Native tools ----

function run(command, args) {
  const result = spawnSync(command, args, {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr.trim() || `${command} exited with ${result.signal ?? result.status}`);
  return result.stdout;
}

export function projectTools(root) {
  return JSON.parse(run(join(root, 'lofi'), ['project-tools']));
}

function link(root, text, output, mode) {
  run(process.env.CHIBI || 'chibi-scheme', ['-h', process.env.LOFI_HEAP || '2G',
    '-I', join(root, 'host/chibi'), '-I', join(root, 'src'), join(root, 'scripts/link.scm'), root, text, output, mode]);
}

// ---- A resident builder ----

// One builder owns one compiler and one project's successful Sessions. These
// retain exact input evidence, not staging paths, so acceptance of an output
// is independent of accepting a successful compilation into this cache.
export async function createProjectBuilder({root, project, tools, directory}) {
  project = resolve(project);
  const compiler = await createCompiler(tools.compiler, join(directory, 'errors'));
  try {
    const assemble = await createAssembler(readFileSync(tools.assembler));
    const sessions = new Map();

    function scratch(use) {
      const path = mkdtempSync(join(directory, 'compile-'));
      let result;
      try { result = use(path); }
      catch (error) { try { rmSync(path, {recursive: true, force: true}); } catch {} throw error; }
      rmSync(path, {recursive: true, force: true});
      return result;
    }

    // A missing input is serviced only after the failed Wasm call unwinds.
    // Every retry uses the same preceding Session, never an interrupted value.
    function withInputs(invoke, working, libraries, artifact) {
      for (;;) {
        try { return invoke(); }
        catch (error) {
          if (!(error instanceof CompilerFailure) || !error.request) throw error;
          provide(error.request, working, libraries, artifact);
        }
      }
    }

    function provide(request, working, libraries, artifact) {
      if (request.kind === 'generate') {
        const output = join(working, `${request.key}.syntax`);
        if (status(output)) throw new Error('compiler requested an already provided generated library');
        scratch(producer => {
          const program = staticProgram(join(working, `${request.key}.sld`), libraries, producer, 'debug', artifact);
          run(process.execPath, ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), program, output]);
        });
        if (!status(output)) throw new Error('the producer did not write its generated library');
      } else {
        try { compiler.addArtifact(join(working, 'artifacts.datum'), request.name, artifact(request.name)); }
        catch (error) { throw new Error(`${request.file}:${request.line}:${request.column}: ${error.message}`, {cause: error}); }
      }
    }

    function staticProgram(source, libraries, working, mode, artifact) {
      const text = join(working, 'program.wat'), output = join(working, 'program.wasm');
      withInputs(() => compiler.static(source, text, working, libraries), working, libraries, artifact);
      link(root, text, output, mode);
      return output;
    }

    function compile(target, generation, mode, artifact) {
      const source = join(project, target.entry), libraries = target.libraries.map(path => join(project, path)).concat(join(root, 'lib'));
      return scratch(working => {
        if (mode !== 'development') {
          copyFileSync(staticProgram(source, libraries, working, mode, artifact), join(generation, 'program.wasm'));
          return {compiled: 1, modules: 1};
        }
        const settings = JSON.stringify([source, libraries]);
        const previous = sessions.get(target.name);
        const session = previous?.settings === settings ? previous.session : compiler.session(libraries);
        const built = withInputs(() => compiler.modules(session, source, working, working), working, libraries, artifact);
        sessions.set(target.name, {settings, session: built.session});
        writeModules(generation, built.modules, tools.runtime, assemble);
        return {compiled: built.modules.filter(module => module.compiled).length, modules: built.modules.length};
      });
    }

    function build(names = null, mode = 'development') {
      if (!['debug', 'release', 'development'].includes(mode)) throw new Error(`unknown build mode ${mode}`);
      const filename = join(project, 'project.datum'), description = compiler.project(filename);
      for (const name of sessions.keys()) if (!description.builds.some(target => target.name === name)) sessions.delete(name);
      const active = [], completed = new Map(), targets = [];
      const required = name => {
        const target = description.builds.find(target => target.name === name);
        if (!target) throw new Error(`unknown project build target ${name} in ${filename}`);
        return target;
      };
      const artifact = name => {
        const target = required(name);
        if (target.kind !== 'browser') throw new Error(`artifact target must be a browser build: ${name}`);
        return visit(target);
      };
      const visit = target => {
        if (active.includes(target.name)) throw new Error(`artifact dependency cycle: ${[...active, target.name].join(' -> ')}`);
        if (completed.has(target.name)) return completed.get(target.name);
        const directory = prepareGeneration(project, target.name), output = {name: target.name, directory};
        targets.push(output); // Own even the directory of a target that fails.
        active.push(target.name);
        try {
          Object.assign(output, compile(target, directory, mode, artifact));
          if (target.kind === 'browser') packageBrowser(root, project, target, directory, mode);
          chmodSync(directory, 0o755);
          const files = generationFiles(directory);
          completed.set(target.name, files);
          return files;
        } finally { active.pop(); }
      };
      try {
        for (const name of names ?? description.builds.map(target => target.name)) visit(required(name));
        return {project, description, targets};
      } catch (error) {
        try { discardProject({targets}); } catch {}
        throw error;
      }
    }

    return {build, close: () => compiler.close()};
  } catch (error) {
    try { compiler.close(); } catch {}
    throw error;
  }
}

// ---- Completed program files ----

// Assemble every returned module into this self-contained generation. Compiler
// caching remains the sole cache; a second native binary cache is unnecessary.
function writeModules(directory, modules, runtime, assemble) {
  mkdirSync(join(directory, 'modules'));
  const files = modules.map(({name, file}) => {
    const text = readFileSync(file, 'utf8'), digest = createHash('sha256').update(text).digest('hex');
    const path = `modules/${digest}.wasm`;
    writeFileSync(join(directory, path), assemble(text));
    return {name, file: path};
  });
  copyFileSync(runtime, join(directory, 'runtime.wasm'));
  writeFileSync(join(directory, 'modules.json'), JSON.stringify({runtime: 'runtime.wasm', modules: files}));
}

const browserFiles = ['host.mjs', 'runtime.mjs', 'tasks.mjs', 'entry.mjs', 'renderer.mjs', 'hud.mjs', 'pictures.mjs', 'storage.mjs', 'load.mjs', 'style.css'];

function packageBrowser(root, project, target, output, mode) {
  for (const name of browserFiles) copyFileSync(join(root, 'src/app', name), join(output, name));
  if (target.public !== null) copyPublic(publicDirectory(project, target.public), output);
  const page = join(output, 'index.html');
  if (mode === 'development' && status(page)) {
    writeFileSync(page, `${readFileSync(page, 'utf8')}\n<meta name="lofi-modules" content="./modules.json">\n`);
  }
}

// ---- Public trees and artifact inventories ----

const status = path => lstatSync(path, {throwIfNoEntry: false});

function directoryNames(path) {
  try { return readdirSync(path); }
  catch (error) { throw new Error(`cannot read directory ${path}: ${error.message}`, {cause: error}); }
}

function publicDirectory(project, path) {
  const parts = path.split('/');
  if (path === '.' || parts[0] === 'build') throw new Error(`public directory overlaps project build output: ${path}`);
  let directory = project;
  for (const part of parts) {
    directory = join(directory, part);
    if (!status(directory)?.isDirectory()) throw new Error(`public path must contain only directories, not links: ${directory}`);
  }
  return directory;
}

function copyPublic(source, output) {
  for (const name of directoryNames(source)) {
    const from = join(source, name), to = join(output, name), entry = status(from);
    if (status(to) || name === '.lofi-publish') throw new Error(`public file conflicts with a build artifact: ${from}`);
    if (entry?.isSymbolicLink()) throw new Error(`public files cannot be symbolic links: ${from}`);
    if (entry?.isDirectory()) { mkdirSync(to); copyPublic(from, to); }
    else if (entry?.isFile()) copyFileSync(from, to);
    else throw new Error(`public entry must be a regular file or directory: ${from}`);
  }
}

function generationFiles(directory, relative = '') {
  const files = [];
  for (const name of directoryNames(join(directory, relative))) {
    if (!relative && name === '.lofi-target') continue;
    const file = relative ? `${relative}/${name}` : name, path = join(directory, file), entry = status(path);
    if (entry?.isDirectory()) files.push(...generationFiles(directory, file));
    else if (entry?.isFile()) files.push([file, path]);
    else throw new Error(`completed output must contain regular files and directories: ${path}`);
  }
  // UTF-8 lexicographic order agrees with the compiler's Unicode scalar order.
  return files.sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
}

// ---- Publication and directory ownership ----

function checkOutput(output, name) {
  const entry = status(output);
  if (!entry) return;
  if (entry.isSymbolicLink()) {
    const link = readlinkSync(output), marker = join(output, '.lofi-target');
    if (link.startsWith('.lofi-') && link === basename(link) && status(marker)?.isFile() && readFileSync(marker, 'utf8') === name) return;
  }
  throw new Error(`refusing to replace an unmanaged project output: ${output}`);
}

function prepareGeneration(project, name) {
  const build = join(project, 'build');
  if (status(build)?.isSymbolicLink()) throw new Error(`project build directory cannot be a symbolic link: ${build}`);
  mkdirSync(build, {recursive: true});
  checkOutput(join(build, name), name);
  const directory = mkdtempSync(join(build, '.lofi-'));
  try { writeFileSync(join(directory, '.lofi-target'), name); }
  catch (error) { try { rmSync(directory, {recursive: true, force: true}); } catch {} throw error; }
  return directory;
}

// These operations consume a candidate. Publication consumes it even on failure:
// already renamed generations stay; only the remaining suffix is disposable.
// Each output is atomic, but several target links are not a global transaction.
export function publishProject(candidate) {
  const {project, targets} = candidate;
  let published = 0;
  try {
    for (const {name, directory} of targets) {
      checkOutput(join(project, 'build', name), name);
      symlinkSync(basename(directory), join(directory, '.lofi-publish'));
    }
    for (const {name, directory} of targets) {
      renameSync(join(directory, '.lofi-publish'), join(project, 'build', name));
      published++;
    }
  } catch (error) {
    try { discardProject({targets: targets.slice(published)}); } catch {}
    throw error;
  }
}

export function discardProject({targets}) {
  let failure;
  for (const {directory} of targets) {
    try { rmSync(directory, {recursive: true, force: true}); }
    catch (error) { failure ??= error; }
  }
  if (failure) throw failure;
}
