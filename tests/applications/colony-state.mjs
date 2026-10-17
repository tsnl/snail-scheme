// Public schema-5 snapshot inspection for integration assertions. No game rules.
export function colony(words) {
  const records = (offset, stride, count, fields, path = false) =>
    Array.from({length: count}, (_, index) => {
      const start = offset + index * stride;
      const record = Object.fromEntries(fields.map((field, fieldIndex) => [field, words[start + fieldIndex]]));
      if (path) record.path = words.slice(start + 8, start + 8 + words[start + 7]);
      if (offset === 416) { record.hp = words[start + 136]; record.order = words[start + 137]; }
      return record;
    });
  return {
    tick: words[1], outcome: words[2], ore: words[3], hull: words[4], kills: words[5], nextId: words[6],
    priority: words[11], repairs: words[12], delivered: words[13], produced: words[14], spent: words[15], lost: words[16], notice: words[17], paused: words[18], seed: words[19], runMarker: words[23], casualties: words[20], lostOre: words[21],
    alerts: records(5660, 4, words[22], ['x','y','kind','tick']),
    buildings: records(32, 12, words[7], ['id','kind','x','y','level','hp','stock','stage','cooldown','aimX','aimY','armed']),
    bots: records(416, 140, words[8], ['id','x','y','job','target','cargo','timer'], true),
    enemies: records(2096, 140, words[9], ['id','x','y','hp','kind','target'], true),
    surveys: records(5456, 3, words[10], ['x','y','radius']),
    rails: records(5696, 140, words[24], ['source','parent','progress','returning','cargo']).map((rail, index) =>
      ({...rail, path: words.slice(5702 + index * 140, 5702 + index * 140 + words[5701 + index * 140])})),
  };
}

// Boundary fixtures use the same schema offsets as the inspection above.
export async function addEnemy(runtime, {x, y, target = 0, kind = 0, hp = 80}) {
  const words = runtime.snapshot(1), index = 2096 + words[9] * 140;
  [words[6]++, x * 40 + 20, y * 40 + 20, hp, kind, target, 0, 0].forEach((value, field) => words[index + field] = value);
  words[9]++; await runtime.restore(1, words);
}

export function setWorker(words, index, {id = words[416 + index * 140], x = 8, y = 22,
  job = 0, target = 0, cargo = 0, timer = 0, path = [], hp = 14, order = 0} = {}) {
  const start = 416 + index * 140;
  words.fill(0, start, start + 140);
  [id, x * 40 + 20, y * 40 + 20, job, target, cargo, timer, path.length, ...path]
    .forEach((value, field) => words[start + field] = value);
  words[start + 136] = hp;
  words[start + 137] = order;
}

export function setBuilding(words, index, changes) {
  const fields = ['id','kind','x','y','level','hp','stock','stage','cooldown','aimX','aimY','armed'];
  for (const [field, value] of Object.entries(changes)) {
    const offset = fields.indexOf(field); if (offset < 0) throw new Error(`unknown building field ${field}`);
    words[32 + index * 12 + offset] = value;
  }
}

export function setRail(words, index, changes) {
  const fields = ['source','parent','progress','returning','cargo'];
  for (const [field, value] of Object.entries(changes)) {
    const offset = fields.indexOf(field); if (offset < 0) throw new Error(`unknown rail field ${field}`);
    words[5696 + index * 140 + offset] = value;
  }
}

export function colonyBalance(world) {
  const cargo = world.bots.filter(bot => bot.job === 2 || (bot.job === 7 && bot.timer === 2))
    .reduce((sum, bot) => sum + bot.cargo, 0);
  return {bank: 160 + world.delivered - world.spent,
    raw: world.delivered + world.lostOre + cargo + world.buildings.reduce((sum, b) => sum + b.stock, 0)
      + world.rails.reduce((sum, rail) => sum + rail.cargo, 0)};
}
