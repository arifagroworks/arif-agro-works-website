const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
function fixture(reduce=false){
  class Element {
    constructor(){this.children=[];this.attrs={};this.events={};this.style={setProperty(){}};this.classes=new Set();this.classList={add:x=>this.classes.add(x),remove:x=>this.classes.delete(x),toggle:(x,on)=>on?this.classes.add(x):this.classes.delete(x)};this.dataset={};this.complete=true;this.naturalWidth=100;}
    append(x){this.children.push(x)} prepend(x){this.children.unshift(x)} setAttribute(k,v){this.attrs[k]=v} addEventListener(k,f){this.events[k]=f}
  }
  const body=new Element(),hero=new Element(),root=new Element(),card=new Element();root.lang='en';
  let interval=null,langChanged;
  const media={matches:reduce,addEventListener(k,f){this.changed=f}};
  const document={body,documentElement:root,hidden:false,querySelector:()=>hero,querySelectorAll:()=>[card],createElement:()=>new Element(),addEventListener(k,f){this[k]=f}};
  class Observer {constructor(f){this.callback=f;Observer.last=this}observe(){}unobserve(){}}
  const context={document,window:{IntersectionObserver:Observer},matchMedia:()=>media,IntersectionObserver:Observer,MutationObserver:class{constructor(f){langChanged=f}observe(){}},setInterval(f){interval=f;return 1},clearInterval(){interval=null}};
  vm.runInNewContext(fs.readFileSync(require.resolve('../assets/aaw-motion.js'),'utf8'),context);
  return {body,hero,root,document,media,card,observer:Observer.last,button:hero.children.at(-1),images:hero.children[0].children.slice(0,3),tick:()=>interval?.(),running:()=>!!interval,langChanged:()=>langChanged()};
}
test('motion rotates loaded photos and pauses on request',()=>{
 const f=fixture();assert.equal(f.running(),true);f.tick();assert.equal(f.images[1].classes.has('is-current'),true);
 f.button.events.click();assert.equal(f.running(),false);assert.equal(f.button.attrs['aria-pressed'],'true');
 f.button.events.click();assert.equal(f.running(),true);
});
test('hidden tabs and offscreen hero stop the slideshow, then resume',()=>{
 const f=fixture();f.document.hidden=true;f.document.visibilitychange();assert.equal(f.running(),false);
 f.document.hidden=false;f.document.visibilitychange();assert.equal(f.running(),true);
 f.observer.callback([{target:f.hero,isIntersecting:false}]);assert.equal(f.running(),false);
 f.observer.callback([{target:f.hero,isIntersecting:true}]);assert.equal(f.running(),true);
});
test('system reduced motion disables autoplay including after a live preference change',()=>{
 const f=fixture(true);assert.equal(f.running(),false);assert.equal(f.button.hidden,true);
 f.media.matches=false;f.media.changed();assert.equal(f.running(),true);
 f.media.matches=true;f.media.changed();assert.equal(f.running(),false);
});
test('unavailable photos are skipped without replacing the visible frame',()=>{
 const f=fixture();f.images[1].naturalWidth=0;f.tick();assert.equal(f.images[0].className,'is-current');assert.equal(f.images[1].classes.has('is-current'),false);
});
test('language changes update pause and play labels; scroll reveals content',()=>{
 const f=fixture();f.root.lang='hi';f.langChanged();assert.match(f.button.textContent,/मोशन रोकें/);
 f.button.events.click();assert.match(f.button.textContent,/मोशन चलाएँ/);
 f.observer.callback([{target:f.card,isIntersecting:true}]);assert.equal(f.card.classes.has('aaw-revealed'),true);
});
