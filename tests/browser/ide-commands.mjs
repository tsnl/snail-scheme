// Invoke the same named command a person chooses in the palette.
import {until} from './chromium.mjs';

export async function command(browser, name) {
  await browser.evaluate('document.getElementById("commands").click()');
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'command query focus');
  await browser.evaluate(`(() => { const input = document.getElementById('command-query');
    input.value = ${JSON.stringify(name)}; input.dispatchEvent(new Event('input')); })()`);
  await until(() => browser.evaluate(`Boolean(document.querySelector('[data-command="${name}"]'))`), name);
  await browser.evaluate(`document.querySelector('[data-command="${name}"]').click()`);
  await until(() => browser.evaluate('!document.getElementById("command-query")'), 'command invocation');
}
