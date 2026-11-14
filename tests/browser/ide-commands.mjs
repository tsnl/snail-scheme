// Chromium test driver: send the DOM events a person uses in the palette.
// The registry and invocation live in (snail shell ide application); behavioral
// tests run that library through run-ui in tests/programs/ide-application.sld.
import {until} from './chromium.mjs';

export async function command(browser, name, {userGesture = false} = {}) {
  await browser.evaluate('document.getElementById("commands").click()');
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'command query focus');
  await browser.evaluate(`(() => { const input = document.getElementById('command-query');
    input.value = ${JSON.stringify(name)}; input.dispatchEvent(new Event('input')); })()`);
  await until(() => browser.evaluate(`Boolean(document.querySelector('[data-command="${name}"]'))`), name);
  await browser.send('Runtime.evaluate', {expression: `document.querySelector('[data-command="${name}"]').click()`, userGesture});
  await until(() => browser.evaluate('!document.getElementById("command-query") || document.getElementById("command-query").value === ""'), 'command invocation');
}
