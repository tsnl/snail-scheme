// Opens a page in headless Chromium, reports console output and errors,
// runs any JavaScript steps a second apart, and saves a screenshot:
//
//   node page.mjs URL SCREENSHOT [SECONDS] [STEP ...]
//
// With TRACE=FILE, FILE is a trace of the whole visit, the page's spans
// among the browser's work (host/browser/trace.mjs), for Perfetto.
import {openBrowser, sleep} from './chromium.mjs';

const [url, screenshot, seconds = '6', ...steps] = process.argv.slice(2);
const browser = await openBrowser(), trace = process.env.TRACE;
if (trace) await browser.startTrace();
await browser.navigate(trace ? traced(url) : url);
await sleep(Number(seconds) * 1000);
for (const step of steps) {
  console.log('step:', step, '->', JSON.stringify(await browser.evaluate(step)));
  await sleep(1000);
}
console.log('page state:', await browser.evaluate('JSON.stringify(document.body.dataset)'));
await browser.screenshot(screenshot);
if (trace) await browser.stopTrace(trace);
browser.close();

// The page's URL with `trace` in its query, which turns its spans on.
function traced(url) {
  const asked = new URL(url);
  asked.searchParams.set('trace', '');
  return asked.href;
}
