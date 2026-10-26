import fs from 'node:fs';

if (process.argv[2] === 'args') fs.writeSync(1, process.argv.slice(3).join('\n'));
else if (process.argv[2] === 'streams') {
  if (fs.readFileSync(0).length) throw new Error('expected stdin EOF');
  for (let i = 0; i < 256; i++) fs.writeSync(2, 'e'.repeat(4096));
  fs.writeSync(1, 'stdin EOF; no newline');
  process.exitCode = 7;
} else throw new Error('unknown capture fixture');
