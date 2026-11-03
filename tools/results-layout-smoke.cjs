// Real Chrome / CDP smoke test. Start tools/smoke-app.R and headless Chrome on 9225.
const fs = require('fs');
const WebSocket = require('ws');
(async () => {
  const targets = await (await fetch('http://127.0.0.1:9225/json')).json();
  const ws = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(resolve => ws.once('open', resolve));
  let seq = 0; const pending = new Map(); const exceptions = [];
  ws.on('message', raw => { const msg = JSON.parse(raw); if(msg.id) { const p = pending.get(msg.id); pending.delete(msg.id); msg.error ? p.reject(msg.error) : p.resolve(msg.result); } else if(msg.method === 'Runtime.exceptionThrown') exceptions.push(msg.params); });
  const cmd = (method, params = {}) => new Promise((resolve, reject) => { const id = ++seq; pending.set(id,{resolve,reject}); ws.send(JSON.stringify({id,method,params})); });
  const evaluate = async expression => { const out = await cmd('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true}); if(out.exceptionDetails) throw new Error(JSON.stringify(out.exceptionDetails)); return out.result.value; };
  const wait = async (expression, label) => { for(let i=0;i<100;i++) { if(await evaluate(expression)) return; await new Promise(r => setTimeout(r,100)); } throw new Error('Timed out: ' + label + '\n' + await evaluate('document.body.innerText')); };
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Emulation.setDeviceMetricsOverride', {width:1440,height:1100,deviceScaleFactor:1,mobile:false});
  await cmd('Page.navigate',{url:'http://127.0.0.1:7854'});
  await wait("document.querySelector('#datasets table tbody tr td')?.innerText==='A'", 'catalogue');
  await evaluate("document.querySelector('#datasets table tbody tr td').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}))");
  await wait("document.querySelectorAll('select[id^=dim_]')[0]?.selectize?.options?.X", 'dimension choices');
  await evaluate("document.querySelectorAll('select[id^=dim_]')[0].selectize.setValue(['X']);document.querySelectorAll('select[id^=dim_]')[1].selectize.setValue(['index']);document.querySelector('a[data-value=time]').click();document.querySelector('input[name=time_mode][value=latest]').click()");
  await wait("document.querySelector('#summary').innerText.includes('Latest')", 'latest time mode');
  await evaluate("document.querySelector('a[data-value=retrieve]').click();document.querySelector('#retrieve').click()");
  await wait("document.querySelector('#result_status').innerText.includes('120 returned observations')", 'large synthetic result');
  for(const width of [1440,390]) {
    await cmd('Emulation.setDeviceMetricsOverride',{width,height:1000,deviceScaleFactor:1,mobile:width<500});
    for(const size of [10,25,100]) {
      await evaluate(`window.jQuery(window.jQuery.fn.dataTable.tables()).filter(function(){return this.closest('#results')}).DataTable().page.len(${size}).draw()`);
      await wait(`document.querySelectorAll('#results tbody tr').length===${size}`, 'page size '+size);
      const bounds=await evaluate(`(()=>{
        const table=document.querySelector('.imf-results-table').getBoundingClientRect();
        const wrapper=document.querySelector('#results .dataTables_wrapper').getBoundingClientRect();
        const actions=document.querySelector('.imf-export-section').getBoundingClientRect();
        return {tableBottom:Math.max(table.bottom,wrapper.bottom),exportTop:actions.top};
      })()`);
      if(bounds.exportTop<bounds.tableBottom+10) throw new Error('Downloads overlap table: '+JSON.stringify({width,size,...bounds}));
      for(const id of ['excel','rds']) {
        const clickable=await evaluate(`(async()=>{const button=document.querySelector('#${id}');button.scrollIntoView({block:'center',behavior:'instant'});await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));const r=button.getBoundingClientRect();const hit=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);return button===hit||button.contains(hit)})()`);
        if(!clickable) {
          const shot=await cmd('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync('/tmp/imfexplorer-exports-failure.png',Buffer.from(shot.data,'base64'));
          console.log(await evaluate(`(()=>{const b=document.querySelector('#${id}');const r=b.getBoundingClientRect();return {rect:r.toJSON(),innerWidth,innerHeight,hit:document.elementFromPoint(r.left+r.width/2,r.top+r.height/2)?.outerHTML.slice(0,200)}})()`));
          throw new Error(`${id} obscured at width ${width}, page size ${size}`);
        }
      }
      console.log('PASS: width',width,'rows',size,'exports below table and both buttons unobscured');
    }
    const shot=await cmd('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
    fs.writeFileSync(`/tmp/imfexplorer-exports-${width}.png`,Buffer.from(shot.data,'base64'));
  }
  if(exceptions.length) throw new Error(JSON.stringify(exceptions));
  ws.close();
})().catch(e=>{console.error(e);process.exit(1)});
