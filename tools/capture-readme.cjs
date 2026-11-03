// Capture real application screenshots for README.md from the package directory.
// Start a LIVE app at 127.0.0.1:7854 (not tools/smoke-app.R), then headless Chrome
// with --remote-debugging-port=9225. Requires Node.js and the ws module.
// Captures one narrow CPI query (USA, monthly, latest 12 observations).
// Update the README capture date after regenerating these images.
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
  const wait = async (expression, label) => { for(let i=0;i<1200;i++) { if(await evaluate(expression)) return; await new Promise(r => setTimeout(r,100)); } throw new Error('Timed out: ' + label + '\n' + await evaluate('document.body.innerText')); };
  await cmd('Runtime.enable'); await cmd('Page.enable');
  const screenshot = async (name,height) => {
    await cmd('Emulation.setDeviceMetricsOverride',{width:1440,height,deviceScaleFactor:1,mobile:false});
    await evaluate("(async()=>{await document.fonts.ready;document.activeElement?.blur();document.querySelectorAll('select').forEach(e=>e.selectize?.close());window.scrollTo(0,0);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))})()");
    const shot=await cmd('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
    fs.writeFileSync('man/figures/'+name,Buffer.from(shot.data,'base64'));
    console.log('Saved',name);
  };
  fs.mkdirSync('man/figures',{recursive:true});
  await cmd('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
  await cmd('Page.navigate',{url:'http://127.0.0.1:7854'});
  await wait("document.querySelector('#datasets tbody tr td')?.innerText && !document.querySelector('#datasets tbody tr td.dataTables_empty')", 'live IMF catalogue');
  console.log('Live catalogue loaded');
  await evaluate("document.querySelector('#dataset_search').value='CPI';document.querySelector('#dataset_search').dispatchEvent(new Event('input',{bubbles:true}))");
  await wait("Array.from(document.querySelectorAll('#datasets tbody tr')).some(r=>r.cells[0]?.innerText.trim()==='CPI')", 'CPI row');
  const version=await evaluate("Array.from(document.querySelectorAll('#datasets tbody tr')).find(r=>r.cells[0]?.innerText.trim()==='CPI').cells[3].innerText.trim()");
  await screenshot('README-datasets.png',950);
  const query={schema_version:1,agency:'IMF.STA',dataset:'CPI',version,
    filters:{COUNTRY:['USA'],INDEX_TYPE:['CPI'],COICOP_1999:['_T'],TYPE_OF_TRANSFORMATION:['IX'],FREQUENCY:['M']},
    start_period:null,end_period:null,last_n_obs:12,attributes:[]};
  fs.writeFileSync('/tmp/imfexplorer-readme-query.json',JSON.stringify(query));
  const doc=await cmd('DOM.getDocument');
  const input=await cmd('DOM.querySelector',{nodeId:doc.root.nodeId,selector:'#import'});
  await cmd('DOM.setFileInputFiles',{nodeId:input.nodeId,files:['/tmp/imfexplorer-readme-query.json']});
  await wait("document.querySelectorAll('.imf-dimension-card').length===5 && document.querySelector('#summary').innerText.includes('Latest 12')", 'live CPI dimensions');
  await wait("!document.querySelector('#dimension_controls').innerText.includes('API failure') && document.querySelectorAll('select[id^=dim_]').length===5 && Array.from(document.querySelectorAll('select[id^=dim_]')).every(e=>e.selectize?.getValue().length===1)", 'CPI filters restored');
  await wait("document.querySelectorAll('.imf-selection-badge.imf-has-selection').length===5 && !document.documentElement.classList.contains('shiny-busy')", 'all live filters received by server');
  await screenshot('README-dimensions.png',1500);
  await evaluate("document.querySelector('a[data-value=retrieve]').click()");
  await wait("document.querySelector('a[data-value=retrieve]').classList.contains('active') && !document.documentElement.classList.contains('shiny-busy')", 'retrieval tab ready');
  await evaluate("document.querySelector('#retrieve').click()");
  await wait("document.querySelector('#result_status').innerText.includes('12 returned observations')", 'twelve live CPI observations');
  await wait("document.querySelector('#series_plot img')?.getAttribute('src')", 'live CPI plot');
  await screenshot('README-results.png',1650);
  for (const [id, file] of [['excel', '/tmp/imfexplorer-live-data.xlsx'], ['rds', '/tmp/imfexplorer-live-data.rds']]) {
    await wait(`document.querySelector('#${id}').href.includes('/download/')`, 'live '+id+' download');
    const result = await evaluate(`(async()=>{const r=await fetch(document.querySelector('#${id}').href);return {ok:r.ok,bytes:Array.from(new Uint8Array(await r.arrayBuffer()))}})()`);
    if(!result.ok) throw new Error('Download failed: '+id);
    fs.writeFileSync(file, Buffer.from(result.bytes));
  }
  console.log('Live query:',JSON.stringify(query));
  console.log('Result:',await evaluate("document.querySelector('#result_status').innerText"));
  if(exceptions.length) throw new Error(JSON.stringify(exceptions));
  ws.close();
})().catch(e=>{console.error(e);process.exit(1)});
