// Starts the editor, host/ide/ide.sld, as a document interface in the page
// (host/browser/ui.mjs). The page's security policy runs only scripts of
// its own origin, so this is a file rather than the page's inline script.
import {startInterface} from './ui.mjs';

startInterface({url: './ide.wasm', container: document.getElementById('ide'), storageKey: 'snail-ide'})
  .catch(error => { document.body.dataset.error = error.message; console.error(error); });
