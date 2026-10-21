// Opens a page in headless Chromium, reports console output and errors,
// runs any JavaScript steps a second apart, and saves a screenshot:
//
//   node page.mjs URL SCREENSHOT [SECONDS] [STEP ...]
import {openBrowser, sleep} from './chromium.mjs';

const [url, screenshot, seconds = '6', ...steps] = process.argv.slice(2);
const browser = await openBrowser();
await browser.navigate(url);
await sleep(Number(seconds) * 1000);
for (const step of steps) {
  console.log('step:', step, '->', JSON.stringify(await browser.evaluate(step)));
  await sleep(1000);
}
console.log('page state:', await browser.evaluate('JSON.stringify(document.body.dataset)'));
await browser.screenshot(screenshot);
browser.close();
