// One plan executor and packager for cold and resident builds. The compiler
// owns parsing, planning and cache evidence; native code owns processes and
// directories.
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
  return JSON.parse(run(join(root, 'scripts/snail-tool'), ['project-tools']));
}

export function editorTools(root) {
  return JSON.parse(run(join(root, 'scripts/snail-tool'), ['editor-tools']));
}

function link(root, text, output, mode) {
  run(process.env.CHIBI || 'chibi-scheme', ['-h', process.env.SNAIL_HEAP || '2G',
    '-I', join(root, 'bootstrap/chibi-include'), join(root, 'scripts/link.scm'), root, text, output, mode]);
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

    // A phase runs only once the plan has supplied everything it needs, so
    // a compile that still asks for an input names a need the planner
    // missed: an internal error, never a retry.
    function planned(compile) {
      try { return compile(); }
      catch (error) {
        if (!(error instanceof CompilerFailure) || !error.request) throw error;
        const {kind, key, name} = error.request;
        throw new Error(`internal error: the build plan did not supply the ${kind} input ${key ?? name}`, {cause: error});
      }
    }

    function staticProgram(source, libraries, working, mode, inputs) {
      const text = join(working, 'program.wat'), output = join(working, 'program.wasm');
      planned(() => compiler.static(inputs, source, text, working, libraries));
      link(root, text, output, mode);
      return output;
    }

    function compile(phase, generation, mode, inputs) {
      return scratch(working => {
        if (mode !== 'development') {
          copyFileSync(staticProgram(phase.entry, phase.directories, working, mode, inputs), join(generation, 'program.wasm'));
          return {compiled: 1, modules: 1};
        }
        const settings = JSON.stringify([phase.entry, phase.directories]);
        const previous = sessions.get(phase.name);
        const session = previous?.settings === settings ? previous.session : compiler.session(phase.directories);
        const built = planned(() => compiler.modules(session, inputs, phase.entry, working));
        sessions.set(phase.name, {settings, session: built.session});
        writeModules(generation, built.modules, tools.runtime, assemble);
        return {compiled: built.modules.filter(module => module.compiled).length, modules: built.modules.length};
      });
    }

    // A producer is compiled from the source the planner printed, then run
    // to write its library's syntax, which the inputs supply from then on.
    function produce(phase, inputs) {
      return scratch(working => {
        const program = staticProgram(phase.source, phase.directories, working, 'debug', inputs), output = join(working, 'output.syntax');
        run(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), program, output]);
        if (!status(output)) throw new Error('the producer did not write its generated library');
        return compiler.addGenerated(inputs, phase.key, phase.source, output, phase.directories);
      });
    }

    // Builds a target into a generation of its own, which the candidate owns
    // from the start, so a build that fails still discards it.
    function buildTarget(phase, target, outputs, mode, prefix, inputs) {
      const directory = prepareGeneration(project, phase.name, prefix), output = {name: phase.name, directory};
      outputs.set(phase.index, output);
      Object.assign(output, compile(phase, directory, mode, inputs));
      if (target.kind === 'browser') packageBrowser(root, project, target, directory, mode);
      chmodSync(directory, 0o755);
      const files = generationFiles(directory);
      output.digest = generationDigest(files);
      return files;
    }

    // The compiler plans the build, and hands it out in waves: the phases
    // that can run now, dependencies first. A wave that ends waiting has
    // run the producers whose outputs the rest needs, and the plan refined
    // with them names the next. A phase is first given the files of each
    // target it embeds, all built in an earlier phase.
    function build(description, names = null, mode = 'development', prefix = '.snail-') {
      if (!['debug', 'release', 'development', 'check'].includes(mode)) throw new Error(`unknown build mode ${mode}`);
      if (!prefix.startsWith('.snail-') || prefix !== basename(prefix)) throw new Error('invalid project generation prefix');
      const outputMode = mode === 'check' ? 'debug' : mode;
      for (const name of sessions.keys()) if (!description.builds.some(target => target.name === name)) sessions.delete(name);
      const outputs = new Map(), completed = new Map(), supplied = new Set();
      const execute = (phase, inputs) => {
        for (const name of phase.embeds.filter(name => !supplied.has(name))) {
          if (!completed.has(name)) throw new Error(`internal error: the build plan embeds ${name} before building it`);
          inputs = compiler.addArtifact(inputs, name, completed.get(name));
          supplied.add(name);
        }
        if (phase.kind === 'produce') return produce(phase, inputs);
        if (phase.kind === 'check') scratch(working => planned(() => compiler.check(inputs, phase.entry, working, phase.directories)));
        else completed.set(phase.name, buildTarget(phase, described(description, phase.name), outputs, outputMode, prefix, inputs));
        return inputs;
      };
      try {
        scratch(planning => {
          let inputs = compiler.inputs();
          let wave = compiler.plan(inputs, project, join(root, 'src'), planning, mode === 'check' ? 'check' : 'build',
            names ?? description.builds.map(target => target.name));
          for (;;) {
            for (const phase of wave.phases) inputs = execute(phase, inputs);
            if (!wave.waiting) return;
            wave = compiler.refine(wave.plan, inputs);
            if (!wave.phases.length) throw new Error('internal error: a refined build plan has nothing to run');
          }
        });
        // In plan order, which puts the first root first.
        return {project, description, targets: [...outputs].sort(([a], [b]) => a - b).map(([, output]) => output)};
      } catch (error) {
        try { discardProject({targets: [...outputs.values()]}); } catch {}
        throw error;
      }
    }

    return {describe: () => compiler.project(join(project, 'project.datum')), build,
      check: description => discardProject(build(description, null, 'check')),
      close: () => compiler.close()};
  } catch (error) {
    try { compiler.close(); } catch {}
    throw error;
  }
}

// The compiler plans from the project file it reads; packaging takes the
// target's settings from the description the caller read just before.
function described(description, name) {
  const target = description.builds.find(target => target.name === name);
  if (!target) throw new Error(`the project changed while its build was planned: ${name}`);
  return target;
}

// ---- Completed program files ----

// Assemble every returned module into this self-contained generation. Compiler
// caching remains the sole cache; a second native binary cache is unnecessary.
function writeModules(directory, modules, runtime, assemble) {
  mkdirSync(join(directory, 'modules'));
  const files = modules.map(({name, text}) => {
    const digest = createHash('sha256').update(text).digest('hex');
    const path = `modules/${digest}.wasm`;
    writeFileSync(join(directory, path), assemble(text));
    return {name, file: path};
  });
  copyFileSync(runtime, join(directory, 'runtime.wasm'));
  writeFileSync(join(directory, 'modules.json'), JSON.stringify({runtime: 'runtime.wasm', modules: files}));
}

const browserFiles = ['host.mjs', 'runtime.mjs', 'tasks.mjs', 'entry.mjs', 'renderer.mjs', 'hud.mjs', 'pictures.mjs', 'storage.mjs', 'load.mjs', 'style.css'];

function packageBrowser(root, project, target, output, mode) {
  for (const name of browserFiles) copyFileSync(join(root, 'host/browser', name), join(output, name));
  if (target.public !== null) copyPublic(publicDirectory(project, target.public), output);
  const page = join(output, 'index.html');
  if (mode === 'development' && status(page)) {
    writeFileSync(page, `${readFileSync(page, 'utf8')}\n<meta name="snail-modules" content="./modules.json">\n`);
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
    if (status(to) || name === '.snail-publish') throw new Error(`public file conflicts with a build artifact: ${from}`);
    if (entry?.isSymbolicLink()) throw new Error(`public files cannot be symbolic links: ${from}`);
    if (entry?.isDirectory()) { mkdirSync(to); copyPublic(from, to); }
    else if (entry?.isFile()) copyFileSync(from, to);
    else throw new Error(`public entry must be a regular file or directory: ${from}`);
  }
}

function generationFiles(directory, relative = '') {
  const files = [];
  for (const name of directoryNames(join(directory, relative))) {
    if (!relative && name === '.snail-target') continue;
    const file = relative ? `${relative}/${name}` : name, path = join(directory, file), entry = status(path);
    if (entry?.isDirectory()) files.push(...generationFiles(directory, file));
    else if (entry?.isFile()) files.push([file, path]);
    else throw new Error(`completed output must contain regular files and directories: ${path}`);
  }
  // UTF-8 lexicographic order agrees with the compiler's Unicode scalar order.
  return files.sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
}

// Content, not compiler work counters or generation paths, identifies an
// output. Include framing and relative names so file boundaries are unambiguous.
function generationDigest(files) {
  const hash = createHash('sha256');
  for (const [name, path] of files) {
    const bytes = readFileSync(path);
    hash.update(JSON.stringify([name, bytes.length])).update(bytes);
  }
  return hash.digest('hex');
}

// ---- Publication and directory ownership ----

function checkOutput(output, name) {
  const entry = status(output);
  if (!entry) return;
  if (entry.isSymbolicLink()) {
    const link = readlinkSync(output), marker = join(output, '.snail-target');
    if (link.startsWith('.snail-') && link === basename(link) && status(marker)?.isFile() && readFileSync(marker, 'utf8') === name) return;
  }
  throw new Error(`refusing to replace an unmanaged project output: ${output}`);
}

function prepareGeneration(project, name, prefix) {
  const build = join(project, 'build');
  if (status(build)?.isSymbolicLink()) throw new Error(`project build directory cannot be a symbolic link: ${build}`);
  mkdirSync(build, {recursive: true});
  checkOutput(join(build, name), name);
  const directory = mkdtempSync(join(build, prefix));
  try { writeFileSync(join(directory, '.snail-target'), name); }
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
      symlinkSync(basename(directory), join(directory, '.snail-publish'));
    }
    for (const {name, directory} of targets) {
      renameSync(join(directory, '.snail-publish'), join(project, 'build', name));
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
