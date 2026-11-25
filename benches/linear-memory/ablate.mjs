// Isolate instruction selection in the emitted benchmark. Each control
// preserves trapping vector access. The compiler itself is unchanged.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {copyFileSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

if (process.argv.length !== 3) throw new Error('usage: node ablate.mjs OUTPUT_DIRECTORY');
const out = resolve(process.argv[2]);
const root = fileURLToPath(new URL('../../', import.meta.url));
const input = readFileSync(join(out, 'managers.wat'), 'utf8');
const runtime = readFileSync(join(out, 'manager.tools'), 'utf8').split('\n')[1];
const linker = join(root, 'build/wasm-snail-scheme-support-toolchain/release/snail-link');
const flags = ['--disable-gc', '--enable-reference-types', '--enable-tail-call', '--enable-bulk-memory',
  '--enable-nontrapping-float-to-int', '--enable-sign-ext', '--enable-mutable-globals', '--enable-multivalue'];

// The compiler prints each function's declarations on one line. The next
// module field begins in column three. Fail if the expected body changes.
function definition(text, name) {
  const start = text.indexOf('  (func ' + name + ' ');
  assert.ok(start >= 0, name);
  const bodyStart = text.indexOf('\n', start);
  const end = text.indexOf('\n  (', bodyStart);
  assert.ok(end > bodyStart, name);
  const header = text.slice(start, bodyStart);
  const body = text.slice(bodyStart, end).trimEnd();
  assert.ok(body.endsWith(')') && !body.includes('call $lm.enter'), name);
  return {start, end, header, body: body.slice(0, -1)};
}
function rewrite(text, name, change) {
  const {start, end, header, body} = definition(text, name);
  return text.slice(0, start) + header + '\n' + change(header, body) + ')' + text.slice(end);
}

// The frontend checks the signed I64 as an unsigned index before narrowing.
// The physical load checks that narrowed index against the same length.
// One unsigned I64 comparison rejects negatives and every index >= length.
function checkedIndex(text) {
  for (const [name, type, shift] of [['Bool', 'i32', 2], ['F64', 'f64', 3], ['I64', 'i64', 3],
                                    ['main:WallId', 'i32', 2]]) {
    for (const op of name === 'I64' || name === 'F64' ? ['read', 'write'] : ['read']) {
      text = rewrite(text, '$array-' + op + '.' + name, (_header, body) => {
        assert.ok(body.includes('(call $range.') && body.includes('(call $lm.index'));
        const length = '(i64.extend_i32_u (i32.load offset=4 (call $lm.nonnull (local.get $array))))';
        const offset = '(i32.shl (i32.wrap_i64 (local.get $at)) (i32.const ' + shift + '))';
        const address = '(i32.add (local.get $array) ' + offset + ')';
        const access = op === 'read' ? '(' + type + '.load offset=8 ' + address + ')' :
          '(' + type + '.store offset=8 ' + address + ' (local.get $value)) (i32.const 0)';
        return '    (if (i64.ge_u (local.get $at) ' + length + ') (then unreachable))\n    ' + access;
      });
    }
  }
  return text;
}

// The existing tail-call sequence evaluates every next argument into a
// distinct temporary first. Assign those values to the parameters and branch
// to the top of the same function. These six loops use no frame or allocation.
function selfLoops(text) {
  for (const local of ['cast-batch', 'trace-dense', 'trace-ids', 'trace-slots', 'clear-distance!', 'visit!']) {
    const name = '$main:' + local;
    text = rewrite(text, name, (header, body) => {
      const params = [...header.matchAll(/\(param (\$\S+) \w+\)/g)].map(m => m[1]);
      const result = header.match(/\(result (\w+)\)/)[1];
      const temps = params.map((_, i) => '(local.get $lm.tmp.' + i + ')');
      const call = '(return_call ' + name + ' ' + temps.join(' ') + ')';
      assert.equal(body.split(call).length, 2, name);
      assert.ok(!body.includes('call $lm.leave') && !body.includes('call $lm.alloc'), name);
      const assign = params.map((p, i) => '(local.set ' + p + ' ' + temps[i] + ')');
      const branch = '(block (result ' + result + ') ' + assign.join(' ') + ' (br $again))';
      return '    (loop $again (result ' + result + ')' + body.replace(call, branch) + ')';
    });
  }
  return text;
}

// Check the full four-F64 footprint once. A successful range test also
// proves that adding three to the slot stays inside the same array.
function checkedWall(text) {
  return rewrite(text, '$main:intersect', (header, body) => {
    const [bounds, at] = [...header.matchAll(/\(param (\$\S+) \w+\)/g)].map(m => '(local.get ' + m[1] + ')');
    const add = body.match(/\(call (\$snail\.core\.base:\+\.\d+) /)[1];
    for (let i = 0; i < 4; i++) {
      const index = i ? '(call ' + add + ' ' + at + ' (i64.const ' + i + '))' : at;
      const read = '(call $array-read.F64 ' + bounds + ' ' + index + ')';
      assert.equal(body.split(read).length, 2);
      body = body.replace(read, '(f64.load offset=' + (8 + 8 * i) + ' (local.get $lm.index))');
    }
    const len = '(i32.load offset=4 (call $lm.nonnull ' + bounds + '))';
    const first = '(call $range. ' + len + ' ' + at + ' (i64.const 4))';
    return '    (local.set $lm.index (i32.add ' + bounds + ' (i32.shl ' + first + ' (i32.const 3))))' + body;
  });
}

// Clang splits the ray loop by direction. Give the same two constant
// directions to Snail's slab calculation. Other directions retain their
// original computation. Apply this after the loop control, so a specialized
// loop continues in its own body on each wall.
function specializeDirections(text) {
  const intersect = '$main:intersect';
  for (const name of [intersect, '$main:trace-dense', '$main:trace-ids', '$main:trace-slots']) {
    const {start, end, header, body} = definition(text, name);
    const params = [...header.matchAll(/\(param (\$\S+) \w+\)/g)].map(m => m[1]);
    const dz = '(local.get ' + params.find(p => p.startsWith('$dz.')) + ')';
    const args = params.map(p => '(local.get ' + p + ')').join(' ');
    let fallback = body;
    const copies = [];
    for (const [suffix, value] of [['slope', '0.125'], ['flat', '0']]) {
      const target = name + '.' + suffix, constant = '(f64.const ' + value + ')';
      let specialized;
      if (name === intersect) {
        assert.ok(body.includes(dz));
        specialized = body.replaceAll(dz, constant);
      } else {
        assert.ok(body.includes('(loop $again') && body.includes('(call ' + intersect + ' '));
        specialized = body.replace('(call ' + intersect + ' ', '(call ' + intersect + '.' + suffix + ' ');
        fallback = '(if (result f64) (f64.eq ' + dz + ' ' + constant + ') ' +
          '(then (return_call ' + target + ' ' + args + ')) (else ' + fallback + '))';
      }
      copies.push(header.replace(name + ' ', target + ' ') + '\n' + specialized + ')');
    }
    text = text.slice(0, start) + [header + '\n' + fallback + ')', ...copies].join('\n') + text.slice(end);
  }
  return text;
}

const bounds = checkedIndex(input), both = selfLoops(bounds), rows = checkedWall(both);
for (const [label, source] of [['bounds', bounds], ['loops', selfLoops(input)], ['bounds-loops', both],
                              ['walls', rows], ['directions', specializeDirections(rows)]]) {
  const dir = join(out, label);
  mkdirSync(join(dir, 'inlined'), {recursive: true});
  const wat = join(dir, 'managers.wat'), wasm = join(dir, 'managers.wasm');
  writeFileSync(wat, source);
  execFileSync(linker, [wat, runtime, wasm]);
  for (const tuning of ['', 'inlined']) {
    const opts = tuning ? ['-O3', '--always-inline-max-function-size=64', '--inlining-optimizing', '-O3'] : ['-O2'];
    execFileSync('wasm-opt', [...flags, ...opts, wasm, '-o', join(dir, tuning, 'managers.release.wasm')]);
    for (const c of ['c.release.wasm', 'c-checked.release.wasm'])
      copyFileSync(join(out, tuning, c), join(dir, tuning, c));
  }
}
