// Public schema-3 snapshot inspection for integration assertions. No game rules.
export function colony(words) {
  const records = (offset, stride, count, fields, path = false) =>
    Array.from({length: count}, (_, index) => {
      const start = offset + index * stride;
      const record = Object.fromEntries(fields.map((field, fieldIndex) => [field, words[start + fieldIndex]]));
      if (path) record.path = words.slice(start + 8, start + 8 + words[start + 7]);
      return record;
    });
  return {
    tick: words[1], outcome: words[2], ore: words[3], hull: words[4], kills: words[5], nextId: words[6],
    priority: words[11], repairs: words[12], delivered: words[13], produced: words[14], spent: words[15], lost: words[16], notice: words[17], paused: words[18],
    buildings: records(32, 12, words[7], ['id','kind','x','y','level','hp','stock','stage','cooldown','aimX','aimY']),
    bots: records(416, 140, words[8], ['id','x','y','job','target','cargo','timer'], true),
    enemies: records(2096, 140, words[9], ['id','x','y','hp','kind','target'], true),
    surveys: records(5456, 3, words[10], ['x','y','radius']),
  };
}

// Boundary fixtures use the same schema offsets as the inspection above.
export function addEnemy(runtime, {x, y, target = 0, kind = 0, hp = 80}) {
  const words = runtime.snapshot(1), index = 2096 + words[9] * 140;
  [words[6]++, x * 40 + 20, y * 40 + 20, hp, kind, target, 0, 0].forEach((value, field) => words[index + field] = value);
  words[9]++; runtime.restore(1, words);
}
