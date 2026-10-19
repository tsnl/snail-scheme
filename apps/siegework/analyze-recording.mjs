// Decode each retained World with the actual Scheme validator and diagnostic
// projection. This host only collects observations; it implements no game rule.
import {readFileSync, statSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {RunRecording, recordingLimits} from '../../src/application/recording.mjs';
import {SnapshotPlayback} from '../../src/application/playback.mjs';

function segment(entry, state) {
  return {firstSequence: entry.sequence, lastSequence: entry.sequence, start: state, end: state,
    firstObservedNestKnown: state.nestKnown ? state.tick : null, firstObservedNestDamage: null,
    peakOre: state.ore, peakEnemies: state.enemies, orders: [], observations: []};
}
function observe(run, entry, state, manifest) {
  if (run.firstObservedNestKnown === null && state.nestKnown) run.firstObservedNestKnown = state.tick;
  if (run.firstObservedNestDamage === null && state.nestHp < run.end.nestHp) run.firstObservedNestDamage = state.tick;
  run.peakOre = Math.max(run.peakOre, state.ore); run.peakEnemies = Math.max(run.peakEnemies, state.enemies);
  const binding = manifest.applications.find(app => app.owner === 'match').handlers.find(handler => handler.id === entry.command?.handler)?.binding;
  if (binding && binding !== manifest.settings.tick) run.orders.push({sequence: entry.sequence, tick: state.tick, binding, args: entry.command.args, effects: entry.effects});
  if (!run.observations.length || state.tick - run.observations.at(-1).tick >= 100 || binding !== manifest.settings.tick)
    run.observations.push({sequence: entry.sequence, ...state});
  run.lastSequence = entry.sequence; run.end = state;
}
export async function analyzeRecording(recording, bytes, manifest) {
  const playback = await SnapshotPlayback.open(bytes, manifest, recording), segments = []; let run;
  try {
    for (const {entry, words} of recording.frames()) {
      await playback.runtime.restore(1, Array.from(words)); const state = playback.inspect();
      if (!run || state.run !== run.end.run || ['checkpoint', 'restore'].includes(entry.kind)) {
        run = segment(entry, state); segments.push(run);
      }
      observe(run, entry, state, manifest);
    }
    return {format: 'siegework-observations-v1', source: recording.stats(), startedAt: recording.startedAt,
      rendererGeneration: manifest.generation, segments};
  } finally { await playback.close(); }
}
async function main() {
  const [dump, directory] = process.argv.slice(2);
  if (!dump || !directory) throw new Error('Usage: node apps/siegework/analyze-recording.mjs FILE.snailrun BUILT-SOLO-DIRECTORY');
  if (statSync(dump).size > recordingLimits.fileBytes) throw new Error('Recording exceeds the 72 MiB file limit');
  const file = readFileSync(dump), recording = RunRecording.import(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength));
  const manifest = JSON.parse(readFileSync(join(directory, 'manifest.json'))), bytes = readFileSync(join(directory, manifest.module));
  console.log(JSON.stringify(await analyzeRecording(recording, bytes, manifest), null, 2));
}
if (process.argv[1] && resolve(process.argv[1]) === import.meta.filename) await main();
