// Derived schema-7 records for assertions and bounded encounter fixtures. Only
// actual compiled Scheme transitions implement jobs, routing or combat.
import {snapshotValue, snapshotWords} from './snapshots.mjs';

const camel = field => field.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
const fieldName = field => field === 'ore' ? 'credits' : field.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`);
function readable(value) {
  if (Array.isArray(value)) return value.map(readable);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value)
    .map(([field, contents]) => [field === 'credits' ? 'ore' : camel(field), readable(contents)]));
  return value;
}
export const colony = words => readable(snapshotValue(words, {marked:true}));
export const client = words => readable(snapshotValue(words));
const symbol = text => ({symbol:text});
const itemTypes = {buildings:'Building', bots:'Bot', enemies:'Enemy', surveys:'Survey', alerts:'Alert', rails:'Rail', path:'I32'};
function typedRecord(type, value) {
  const library = type === 'Survey' ? 'terrain' : type === 'Client' ? 'game' : 'model';
  return [symbol('data'), symbol(`(siegework ${library}):${type}`), symbol(`make-${type.toLowerCase()}`),
    ...Object.entries(value).map(([field, contents]) => [symbol(fieldName(field)), typedField(field, contents)])];
}
function typedField(field, value) {
  if (typeof value === 'boolean') return [symbol('Bool'), symbol(value ? 'true' : 'false')];
  if (!Array.isArray(value)) return [symbol('I32'), value];
  const type = itemTypes[field], name = type === 'I32' ? type : `(siegework ${type === 'Survey' ? 'terrain' : 'model'}):${type}`;
  if (!type) throw new Error(`unknown fixture list ${field}`);
  return [symbol(`(List ${name})`), value.map(item => type === 'I32' ? [symbol(type), item] : typedRecord(type, item))];
}
export const colonyWords = world => snapshotWords(7, typedRecord('World', world), world.runMarker);
export const clientWords = local => snapshotWords(1, typedRecord('Client', local));
export const restoreColony = (runtime, world) => runtime.restore(1, colonyWords(world));
export const restoreClient = (runtime, local) => runtime.restore(2, clientWords(local));

export function addEnemy(runtime, {x, y, target = 0, kind = 0, hp = 80}) {
  const world = colony(runtime.snapshot(1));
  world.enemies.push({id:world.nextId++, x:x * 40 + 20, y:y * 40 + 20, hp, kind, target, path:[]});
  return restoreColony(runtime, world);
}
export function setWorker(world, index, {id = world.bots[index].id, x = 8, y = 22,
  job = 0, target = 0, cargo = 0, timer = 0, path = [], hp = 14, order = 0, source = 0} = {}) {
  world.bots[index] = {id, x:x * 40 + 20, y:y * 40 + 20, job, target, cargo, timer, path, hp, order, source};
}
export const setBuilding = (world, index, changes) => Object.assign(world.buildings[index], changes);
export const setRail = (world, index, changes) => Object.assign(world.rails[index], changes);
export function colonyBalance(world) {
  const cargo = world.bots.filter(bot => bot.job === 2 || (bot.job === 7 && bot.timer === 2))
    .reduce((sum, bot) => sum + bot.cargo, 0);
  return {bank:160 + world.delivered + world.localSpent - world.spent,
    raw:world.delivered + world.localSpent + world.lostOre + cargo + world.buildings.reduce((sum, building) => sum + building.stock, 0)
      + world.rails.reduce((sum, rail) => sum + rail.cargo, 0)};
}
