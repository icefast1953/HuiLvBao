import test from 'node:test';
import assert from 'node:assert/strict';
import {afterRemoval, chartLayout, RequestGate,restoreInput,ratesForBase} from '../web/model.mjs';

test('deleting the input currency resets to the first remaining row without reusing rounded output',()=>{
  assert.deepEqual(afterRemoval({source:'USD',amount:'100.001'},['CNY','EUR']),{source:'CNY',amount:'1'});
  assert.deepEqual(afterRemoval({source:'USD',amount:'100.001'},['USD','EUR']),{source:'USD',amount:'100.001'});
});
test('a delayed old response cannot overwrite a newer edit',()=>{
  const gate=new RequestGate(); const old=gate.next(); const latest=gate.next();
  assert.equal(gate.accepts(old),false); assert.equal(gate.accepts(latest),true);
});
test('a fresh session cannot keep a hidden CNY source after CNY was removed',()=>{
  assert.deepEqual(restoreInput(null,['USD','EUR']),{source:'USD',amount:'1'});
  assert.deepEqual(restoreInput({source:'USD',amount:'100.001'},['USD']),{source:'USD',amount:'100.001'});
});
test('search and language redraw never expose another base after a failed query',()=>{
  assert.deepEqual(ratesForBase({source:'USD',rows:[{code:'CNY'}]},'GAU'),[]);
  assert.deepEqual(ratesForBase(null,'CNY'),[]);
});
test('history uses actual calendar spacing and never fills missing days',()=>{
  const dots=chartLayout([{date:'2026-10-20',rate:'1'},{date:'2026-10-21',rate:'2'},{date:'2026-10-26',rate:'3'}],700,240);
  assert.equal(dots.length,3); assert.ok(Math.abs((dots[1].x-dots[0].x)/(dots[2].x-dots[0].x)-1/6)<1e-10);
  assert.ok(dots.every(p=>Number.isFinite(p.x)&&Number.isFinite(p.y)));
  assert.equal(chartLayout([],700,240).length,0);
  assert.ok(Number.isFinite(chartLayout([{date:'2026-10-20',rate:'1'}],700,240)[0].y));
});
