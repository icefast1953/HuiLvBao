import assert from 'node:assert/strict';
const root='http://127.0.0.1:18627';
async function request(path,body){const r=await fetch(root+path,body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{});assert.equal(r.status,200,`${path} status`);return r.json();}
const state=await request('/api/state');assert.equal(state.engine,'Cangjie');assert.equal(state.demo,true,'Run this integration test only against the isolated demo instance');assert.equal(state.catalog.length,173);
for(const code of ['CNY','USD'])await request('/api/favorites',{action:'add',code});
const first=await request('/api/convert',{source:'CNY',amount:'100'});assert.equal(first.rows.find(r=>r.code==='USD').amount,'12.50');
const switched=await request('/api/convert',{source:'USD',amount:'100.001'});assert.equal(switched.rows.find(r=>r.code==='CNY').amount,'800.01');
const invalid=await request('/api/convert',{source:'CNY',amount:'1e2'});assert.equal(invalid.inputError,true);assert.ok(invalid.rows.every(r=>r.amount===null));
const unit=await request('/api/latest?base=CNY');assert.equal(unit.amount,'1');assert.equal(unit.rows.find(r=>r.code==='USD').rate,'0.125');assert.equal(unit.rows.find(r=>r.code==='XAU').rate,null);
for(const days of [7,30,90]){const h=await request(`/api/history?base=CNY&target=USD&days=${days}`);assert.equal(h.error,'');assert.equal(h.rows.length,3);assert.ok(h.rows.every((p,i,a)=>i===0||a[i-1].date<p.date));}
const forbidden=await fetch(root+'/api/state',{headers:{Origin:'https://example.invalid'}});assert.equal(forbidden.status,403);
const traversal=await fetch(root+'/.git/config');assert.equal(traversal.status,404);
console.log('HTTP_INTEGRATION_OK: Cangjie engine, 173 catalog, exact conversion, invalid input, isolated unit rates, 7/30/90 history, origin and static-resource boundaries');
