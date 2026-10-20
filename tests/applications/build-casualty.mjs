// The product compiler rejects cond-expand library clauses. Expose private
// settlement only in this temporary test source root, never in the game package.
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,join,dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
const root=resolve(import.meta.dirname,'../..'),output=resolve(process.argv[2]??join(root,'build/application-tests/casualty.wasm'));
const temporary=mkdtempSync(join(tmpdir(),'siegework-casualty-'));
try {
  mkdirSync(join(temporary,'siegework'));mkdirSync(dirname(output),{recursive:true});
  const source=readFileSync(join(root,'apps/siegework/src/siegework/model.sld'),'utf8');
  if(!source.includes('(export World'))throw new Error('model export boundary changed');
  writeFileSync(join(temporary,'siegework/model.sld'),source.replace('(export World','(export clear-casualties World'));
  const result=spawnSync('chibi-scheme',['-I',join(root,'bootstrap'),join(root,'tests/applications/build.scm'),
    root,join(root,'tests/applications/casualty.sld'),output,temporary,join(root,'apps/siegework/src')],{stdio:'inherit'});
  if(result.error)throw result.error;
  process.exitCode=result.status??1;
} finally {rmSync(temporary,{recursive:true,force:true});}
