// Derived schema-12 records for assertions and bounded encounter fixtures. Only
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
const itemTypes = {buildings:'Building', bots:'Bot', enemies:'Enemy', surveys:'Survey', alerts:'Alert', rails:'Rail', path:'I32', breaches:'I32', excavations:'Dig', tracks:'I32', dismissed:'DismissedAttack'};
function typedRecord(type, value) {
  if (type === 'Enemy') {
    const {burrower = false, rank = value.kind === 2 ? 6 : 0, ...fields} = value;
    value = {...fields, burrower, rank};
  }
  const library = type === 'Survey' ? 'terrain' : ['Client','DismissedAttack'].includes(type) ? 'game' : 'model';
  return [symbol('data'), symbol(`(siegework ${library}):${type}`), symbol(type==='DismissedAttack'?'make-dismissed-attack':`make-${type.toLowerCase()}`),
    ...Object.entries(value).map(([field, contents]) => [symbol(fieldName(field)), typedField(field, contents)])];
}
function typedField(field, value) {
  if (typeof value === 'boolean') return [symbol('Bool'), symbol(value ? 'true' : 'false')];
  if (!Array.isArray(value)) return [symbol('I32'), value];
  const type = itemTypes[field], name = type === 'I32' ? type : `(siegework ${type === 'Survey' ? 'terrain' : type === 'DismissedAttack' ? 'game' : 'model'}):${type}`;
  if (!type) throw new Error(`unknown fixture list ${field}`);
  return [symbol(`(List ${name})`), value.map(item => type === 'I32' ? [symbol(type), item] : typedRecord(type, item))];
}
export const colonyWords = world => snapshotWords(12, typedRecord('World', world), world.runMarker);
export const clientWords = local => {
  const {originX,originY,menu,...fields}=local;
  return snapshotWords(8, typedRecord('Client', {...fields, heading:local.heading ?? 0,
    turnFrom:local.turnFrom ?? 0, turnTo:local.turnTo ?? 0, turnElapsed:local.turnElapsed ?? 300,
    scale:local.scale ?? 1000, preview:local.preview ?? 0, dialog:local.dialog ?? 0,dialogPending:local.dialogPending ?? 0,dialogResult:local.dialogResult ?? 0,homing:local.homing ?? false,lastKind:local.lastKind ?? 3,choiceKind:local.choiceKind ?? 3,buildKind:local.buildKind ?? 0,buildCell:local.buildCell ?? -1,buildResult:local.buildResult ?? 0,failure:local.failure ?? 0,leftHanded:local.leftHanded ?? false,dismissed:local.dismissed ?? []}));
};
export const restoreColony = (runtime, world) => runtime.restore(1, colonyWords(world));
export const restoreClient = (runtime, local) => runtime.restore(2, clientWords(local));

// Established neighborhood scenarios use coordinates relative to the original
// hub at (8,22). Product snapshots and new world tests retain actual coordinates.
export function origin(world) {
  const hub = world.surveys.find(survey => survey.radius === 9);
  return {x:hub.x - 8, y:hub.y - 22};
}
export function at(world, x, y) { const offset = origin(world); return {x:offset.x + x, y:offset.y + y}; }
export function pixelAt(world, x, y) { const cell = at(world, x, y); return {x:cell.x * 40 + 20, y:cell.y * 40 + 20}; }
export function siteAt(world, x, y) { const cell = at(world, x, y); return world.buildings.find(site => site.x === cell.x && site.y === cell.y); }
export function routeCell(world, x, y) { const cell = at(world, x, y); return cell.x + cell.y * 128; }
export function fixtureArguments(world, name, args = []) {
  if (['extract','fortify','observe','upgrade','arm-tower','cancel-building'].includes(name)) {
    const cell = at(world, ...args); return [cell.x,cell.y];
  }
  if (name === 'relocate-building') return args.map(index => routeCell(world, index % 48, Math.floor(index / 48)));
  return args;
}
export function fixtureCall(runtime, name, args = []) {
  return runtime.dispatch(1, runtime.command('match', name, fixtureArguments(colony(runtime.snapshot(1)), name, args)));
}

export function addEnemy(runtime, {x, y, target = 0, kind = 0, hp = 80}) {
  const world = colony(runtime.snapshot(1)), point = pixelAt(world, x, y);
  world.started = true;
  world.enemies.push({id:world.nextId++, ...point, hp, kind, target, path:[]});
  return restoreColony(runtime, world);
}
export function setWorker(world, index, {id = world.bots[index].id, x = 8, y = 22,
  job = 0, target = 0, cargo = 0, timer = 0, path = [], hp = 14, order = 0, source = 0} = {}) {
  world.bots[index] = {id, ...pixelAt(world, x, y), job, target, cargo, timer,
    path:path.map(index => routeCell(world, index % 48, Math.floor(index / 48))), hp, order, source};
}
export const setBuilding = (world, index, changes) => Object.assign(world.buildings[index], changes);
export const setRail = (world, index, changes) => Object.assign(world.rails[index], changes);
export function colonyBalance(world) {
  const cargo = world.bots.filter(bot => [2,4,12,14].includes(bot.job) || (bot.job === 7 && [2,4,12,14].includes(bot.timer)))
    .reduce((sum, bot) => sum + bot.cargo, 0);
  return {bank:160 + world.delivered + world.localSpent - world.spent,
    raw:world.delivered + world.localSpent + world.lostOre + cargo
      + world.buildings.filter(building => building.stage === 2 || building.stage >= 4).reduce((sum, building) => sum + building.stock, 0)
      + world.rails.reduce((sum, rail) => sum + rail.cargo, 0)};
}
