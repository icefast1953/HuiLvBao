export function afterRemoval(input,favorites){
  return favorites.includes(input.source)?{...input}:{source:favorites[0],amount:'1'};
}
export function restoreInput(saved,favorites){
  const input=saved&&typeof saved.source==='string'&&typeof saved.amount==='string'?saved:{source:'CNY',amount:'100'};
  return afterRemoval(input,favorites);
}
export function ratesForBase(data,base){return data?.source===base?data.rows:[];}
export class RequestGate{
  #sequence=0;
  next(){return ++this.#sequence;}
  accepts(sequence){return sequence===this.#sequence;}
}
export function chartLayout(points,width,height){
  if(!points.length)return [];
  const dates=points.map(p=>Date.parse(`${p.date}T00:00:00Z`));
  const values=points.map(p=>Number(p.rate));
  const left=dates[0],span=dates.at(-1)-left,min=Math.min(...values),range=Math.max(...values)-min;
  return points.map((p,i)=>({...p,x:32+(span?(dates[i]-left)/span:.5)*(width-64),y:20+(range?1-(values[i]-min)/range:.5)*(height-48)}));
}
