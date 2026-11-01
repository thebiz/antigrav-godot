// Node: dieselben Einstellungen wie im Baukasten auf die Grundaufnahmen anwenden
const fs=require('fs'); require('./vox.js'); const V=globalThis.VoxDSP;
function readWav(f){const b=fs.readFileSync(f);let o=12,sr=0,data=null,bits=16,ch=1;
 while(o<b.length){const id=b.toString('ascii',o,o+4),sz=b.readUInt32LE(o+4);
  if(id==='fmt '){ch=b.readUInt16LE(o+10);sr=b.readUInt32LE(o+12);bits=b.readUInt16LE(o+22);}
  if(id==='data'){data=b.subarray(o+8,o+8+sz);} o+=8+sz+(sz&1);}
 const n=data.length/(bits/8)/ch,x=new Float32Array(n);
 for(let i=0;i<n;i++){x[i]=bits===16?data.readInt16LE(i*2*ch)/32768:data.readFloatLE(i*4*ch);} return {x,sr};}
const [,,voice,settingsFile,outDir]=process.argv;
const p=JSON.parse(fs.readFileSync(settingsFile,'utf8'));
const keys=["rak","lenk","mine","orbs","wand","beben","schild","auto","turbo","elim","enlow"];
const t0=Date.now();
for(const k of keys){const {x,sr}=readWav(`dec/${voice}__${k}.wav`);const y=V.render(x,sr,p);
 fs.writeFileSync(`${outDir}/vo_${k}.wav`,Buffer.from(V.wav(y)));}
console.log('ms',Date.now()-t0);
