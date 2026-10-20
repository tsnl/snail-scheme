// Settle a test casualty through actual Wasm, then validate its result through
// the product decoder. Live saves never accept hp0 and the game has no kill API.
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
const contract={version:1,applications:[
  {owner:'match',schema:15,handlers:[{binding:'settle',id:'settle',slot:0,payload:['I32']}]},
  {owner:'client',schema:1,handlers:[{binding:'noop',id:'noop',slot:0,payload:[]}]}]};
let bytes;
export function configureCasualties(value){bytes=value;}
export async function settleWorker(runtime,id) {
  bytes??=readFileSync(process.env.SIEGEWORK_CASUALTY_FIXTURE??resolve(import.meta.dirname,'../../build/application-tests/casualty.wasm'));
  const fixture=new ReducerRuntime();
  try {
    await fixture.replace(fixture.prepare(bytes,contract));await fixture.initialize(1);await fixture.initialize(2);
    await fixture.restore(1,runtime.snapshot(1));await fixture.dispatch(1,fixture.command('match','settle',[id]));
    await runtime.restore(1,fixture.snapshot(1));
  } finally {await fixture.close();}
}
