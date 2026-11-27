import assert from 'node:assert/strict';
import {until} from './chromium.mjs';

// Called from the real pause menus before saving and before loading a fresh visit.
export async function changeDisplay(browser) {
  const read = selector => browser.evaluate(selector);
  assert.equal(await read('document.querySelector(".refresh-divisor").value'), '1');
  assert.equal(await read('document.querySelector(".show-frame-meter").checked'), true);
  assert.equal(await read('document.querySelector(".frame-plot").getBoundingClientRect().width'), 128);
  await browser.evaluate('document.querySelector(".show-frame-meter").click()');
  await until(() => read('document.querySelector(".frame-meter").hidden'), 'hide frame meter');
  const edit = value => browser.evaluate(`(() => {
    const field = document.querySelector('.refresh-divisor');
    field.value = ${JSON.stringify(value)};
    field.dispatchEvent(new Event('input', {bubbles: true}));
  })()`);
  await edit('0');
  await until(() => read('document.querySelector(".refresh-divisor").ariaInvalid === "true"'), 'invalid refresh divisor');
  await edit('7');
  await until(() => read('document.querySelector(".refresh-divisor").ariaInvalid === "false"'), 'valid refresh divisor');
}

export async function checkFreshDisplay(browser) {
  assert.deepEqual(await browser.evaluate(`[
    document.querySelector('.refresh-divisor').value,
    document.querySelector('.show-frame-meter').checked,
    document.querySelector('.frame-meter').hidden
  ]`), ['7', false, true]);
  const draws = await browser.evaluate(`(async () => {
    const canvas = GPUCanvasContext.prototype, acquire = canvas.getCurrentTexture;
    let count = 0;
    canvas.getCurrentTexture = function(...args) { count++; return acquire.apply(this, args); };
    try {
      for (let i = 0; i < 42; ++i) await new Promise(requestAnimationFrame);
      return count;
    } finally { canvas.getCurrentTexture = acquire; }
  })()`);
  assert.ok(draws > 0 && draws <= 7, `divisor 7 produced ${draws} canvas frames in 42 refreshes`);
}
