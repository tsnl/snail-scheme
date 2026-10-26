// Inject a failed listing after entries have been read. This is a test-only
// Node preload, so the production directory reader needs no failure switch.
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';

const readdir = fs.readdirSync;
fs.readdirSync = function(path, ...options) {
  const names = readdir.call(this, path, ...options);
  if (String(path).startsWith(process.env.LOFI_TEST_DIRECTORY_FAILURE)) {
    throw Object.assign(new Error('injected directory read failure'), {code: 'EIO'});
  }
  return names;
};
syncBuiltinESMExports();
