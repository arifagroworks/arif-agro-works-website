// Reproducible browser from the npm-lockfile package; no separate browser CDN.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),zlib=require('node:zlib'),{spawnSync}=require('node:child_process');
const source=path.resolve(path.dirname(require.resolve('@sparticuz/chromium')),'../bin');
const version=JSON.parse(fs.readFileSync(path.resolve(source,'../package.json'),'utf8')).version;
const target=process.env.AAW_BROWSER_DIR||path.join(os.tmpdir(),'aaw-chromium-'+version);fs.mkdirSync(target,{recursive:true});
for(const name of ['chromium.br','swiftshader.tar.br','al2023.tar.br']){
 const output=path.join(target,name.replace(/\.br$/,''));fs.writeFileSync(output,zlib.brotliDecompressSync(fs.readFileSync(path.join(source,name))));
 if(name.endsWith('.tar.br')){const result=spawnSync('tar',['--no-same-owner','-xf',output,'-C',target],{stdio:'inherit'});if(result.status!==0)throw Error('Browser runtime extraction failed');}
}
const executable=path.join(target,'chromium');fs.chmodSync(executable,0o755);const libraries=[target,path.join(target,'al2023/lib'),process.env.LD_LIBRARY_PATH].filter(Boolean).join(':');
if(process.env.GITHUB_ENV)fs.appendFileSync(process.env.GITHUB_ENV,`AAW_CHROMIUM_PATH=${executable}\nLD_LIBRARY_PATH=${libraries}\n`);
console.log(JSON.stringify({executable,libraries,version}));
