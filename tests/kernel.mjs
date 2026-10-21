// Drives the default kernel through src/notebook/kernel.mjs as the REPL and
// the notebook do: definitions that persist, printed text and values,
// errors after which the kernel goes on, typed procedures, a stopped
// worker, and the percent format of notebook files.
//   node kernel.mjs KERNEL.wasm
import {readFile} from 'node:fs/promises';
import {Worker} from 'node:worker_threads';
import assert from 'node:assert/strict';
import {createKernel, kernelClient, balanced, parseCells, formatCells} from '../src/notebook/kernel.mjs';

const bytes = await readFile(process.argv[2]);
const kernel = await createKernel(bytes);
const value = text => {
  const result = kernel.evaluate(text);
  assert.ok(result.ok, `${text}: ${result.error}`);
  return result.value;
};
const failure = text => {
  const result = kernel.evaluate(text);
  assert.equal(result.ok, false, `${text} should fail`);
  return result.error;
};

// ---- Evaluation ----

assert.equal(value('(define (square x) (* x x))'), null);
assert.equal(value('(square 12)'), '144');
assert.deepEqual(kernel.evaluate('(display "hi") (newline) (quote done)'), {ok: true, output: 'hi\n', value: 'done', error: null});
assert.equal(value('(define (count n) (let loop ((i 0)) (if (= i n) i (loop (+ i 1))))) (count 100000)'), '100000');

// ---- Errors ----

assert.equal(failure('(car 1)'), 'expected a pair, got 1');
assert.equal(failure('undefined-name'), 'unbound variable: undefined-name');
assert.equal(failure('(+ 1'), 'read: unclosed list');
assert.match(failure('(define (deep n) (if (= n 0) 0 (+ 1 (deep (- n 1))))) (deep 1000000)'), /call stack/);
assert.equal(value('(square 3)'), '9');

// ---- Typed procedures ----

assert.equal(value('(define generator (make-random 42)) generator'), '#<random>');
assert.equal(value('(random-below generator 100)'), '6');
assert.equal(failure('(random-below 5 100)'), 'expected a random, got a number');
assert.equal(value('(list-tail (iota 5) 3)'), '(3 4)');
assert.equal(value('(string->number "x")'), '#f');
assert.ok(kernel.names().includes('make-random') && kernel.names().includes('square'));

// ---- A stopped worker ----

const start = async () => {
  const client = kernelClient(new Worker(new URL('../src/notebook/worker.mjs', import.meta.url)));
  await client.load(bytes);
  return client;
};
const looping = await start();
const stopped = looping.evaluate('(let loop () (loop))');
setTimeout(() => looping.terminate(), 200);
await assert.rejects(stopped, /stopped/);
const fresh = await start();
assert.equal((await fresh.evaluate('(+ 1 2)')).value, '3');
fresh.terminate();

// ---- Notebook files ----

assert.ok(balanced('(display ")") ; (\n#\\( (a)'));
assert.ok(!balanced('(define (f x)\n  (+ x'));
const cells = ['(define x 1)', ';; a comment\nx', ''];
assert.deepEqual(parseCells(formatCells(cells)), cells);
assert.deepEqual(parseCells('(a)\n;; %% second\n(b)'), ['(a)', '(b)']);
console.log('kernel: ok');
