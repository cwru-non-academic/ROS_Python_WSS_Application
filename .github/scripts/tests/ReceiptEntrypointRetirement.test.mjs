import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

test('legacy receipt shim fails closed without invoking another engine',()=>{
  const path=fileURLToPath(new URL('../Invoke-ReleaseReceipt.ps1',import.meta.url));
  const source=readFileSync(path,'utf8');
  assert.doesNotMatch(source,/&\s*node|runReceipt|Start-Process|Invoke-Expression/);
  const result=spawnSync('pwsh',['-NoProfile','-NonInteractive','-File',path],{encoding:'utf8'});
  assert.equal(result.status,1);
  assert.match(result.stderr,/Invoke-ReleaseReceipt\.ps1 is retired/);
});

test('receipt workflow directly invokes the immutable common engine',()=>{
  const workflow=readFileSync(new URL('../../workflows/release-receipt.yml',import.meta.url),'utf8');
  assert.doesNotMatch(workflow,/Invoke-ReleaseReceipt\.ps1|Write-ReleaseReceipt\.mjs/);
  assert.match(workflow,/bootstrap\/Python_WSS_Integration_Lib/);
  assert.match(workflow,/& node \(Join-Path \$config\.engineRoot '\.github\/scripts\/wss-ci\/receipt\.mjs'\)/);
});
