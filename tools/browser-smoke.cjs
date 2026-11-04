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
  await wait("document.querySelector('#datasets table tbody tr td')?.innerText === 'A'", 'catalogue');
  if(await evaluate("document.querySelectorAll('#dataset_search_fields input:checked').length") !== 3) throw new Error('Search defaults must include all three fields');
  if(await evaluate("Array.from(document.querySelectorAll('#datasets th')).some(e=>e.innerText==='agency')")) throw new Error('Agency column is visible');
  if(!await evaluate("document.querySelector('#dataset_search').getBoundingClientRect().width >= document.querySelector('.imf-dataset-search').getBoundingClientRect().width - 2")) throw new Error('Search is not full width');
  const searchCase = async (fields, text, expected) => {
    await evaluate(`document.querySelectorAll('#dataset_search_fields input').forEach(e=>{if(e.checked!==${JSON.stringify(fields)}.includes(e.value))e.click()});document.querySelector('#dataset_search').value=${JSON.stringify(text)};document.querySelector('#dataset_search').dispatchEvent(new Event('input',{bubbles:true}))`);
    await wait(`document.querySelectorAll('#datasets tbody tr:not(:has(td.dataTables_empty))').length===${expected}`, 'search '+fields+' / '+text);
  };
  await searchCase(['id','name','description'], 'TEST', 0);
  await searchCase(['id'], 'B', 1);
  await searchCase(['name'], 'B', 0);
  await searchCase(['name'], 'sectors', 1);
  await searchCase(['description'], 'sectors', 0);
  await searchCase(['description'], 'OFFLINE', 2);
  await searchCase([], 'OFFLINE', 0);
  await searchCase(['id','name','description'], '', 2);
  // Dataset search uses the existing catalogue, and filtered rows keep their original IDs.
  await evaluate("document.querySelector('#dataset_search').value='sectors';document.querySelector('#dataset_search').dispatchEvent(new Event('input',{bubbles:true}))");
  await wait("document.querySelectorAll('#datasets table tbody tr').length===1 && document.querySelector('#datasets table tbody tr').innerText.includes('Synthetic sectors')", 'dataset text search');
  await evaluate("document.querySelector('#datasets table tbody tr td').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}))");
  await wait("document.querySelector('#dimension_controls').innerText.includes('SECTOR')", 'filtered row maps to correct dataset');
  await evaluate("document.querySelector('#clear_query').click()");
  await wait("document.querySelector('#summary').innerText.includes('Choose a dataset') && document.querySelector('#dataset_search').value==='' && document.querySelectorAll('#datasets table tbody tr').length===2", 'clear current query and search');
  await wait("(()=>{const cell=document.querySelector('#datasets table tbody tr td');if(cell?.innerText!=='A'||document.documentElement.classList.contains('shiny-busy'))return false;cell.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}));return true})()", 'select reset catalogue');
  await wait("document.querySelectorAll('select[id^=dim_]')[0]?.selectize?.options?.X", 'remote code choices');
  await evaluate("document.querySelector('button[id$=_all]').click()");
  await wait("document.querySelectorAll('select[id^=dim_]')[0].selectize.getValue().length===2", 'select all available codes');
  await evaluate("document.querySelector('.selectize-input .item[data-value=X] .remove').click()");
  await wait("JSON.stringify(document.querySelectorAll('select[id^=dim_]')[0].selectize.getValue())==='[\"Y\"]'", 'remove one selected chip');
  console.log('Initial dimension controls:', await evaluate("Array.from(document.querySelectorAll('select[id^=dim_]')).map(e=>({id:e.id,choices:Object.keys(e.selectize.options)}))"));
  await evaluate("document.querySelectorAll('select[id^=dim_]')[0].selectize.setValue(['Y']); document.querySelectorAll('select[id^=dim_]')[1].selectize.setValue(['limited']); document.querySelector('#update').click()");
  await wait("document.querySelector('#dimension_controls').innerText.includes('Unavailable selected codes: Y')", 'retained invalid selection');
  const retained = await evaluate("document.querySelectorAll('select[id^=dim_]')[0].selectize.getValue()");
  if(!retained.includes('Y')) throw new Error('Unavailable selection silently removed');
  await wait("document.querySelectorAll('select[id^=dim_]')[1].selectize.options.index", 'refreshed remote choices');
  await evaluate("document.querySelectorAll('select[id^=dim_]')[0].selectize.setValue(['X']); document.querySelectorAll('select[id^=dim_]')[1].selectize.setValue(['index'])");
  await wait("document.querySelector('#summary').innerText.includes('Label index [index]')", 'both selected dimensions');
  await wait("document.querySelectorAll('.imf-dimension-card').length===2", 'responsive selection cards');
  await cmd('Page.captureScreenshot',{format:'png',captureBeyondViewport:true}).then(shot => fs.writeFileSync('/tmp/imfexplorer-selection-desktop.png',Buffer.from(shot.data,'base64')));
  await cmd('Emulation.setDeviceMetricsOverride', {width:390,height:844,deviceScaleFactor:1,mobile:true});
  await evaluate("document.querySelector('main')?.scrollTo(0,0)");
  await cmd('Page.captureScreenshot',{format:'png',captureBeyondViewport:false}).then(shot => fs.writeFileSync('/tmp/imfexplorer-selection-mobile.png',Buffer.from(shot.data,'base64')));
  if(!await evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1")) throw new Error('Mobile page overflows horizontally');
  await cmd('Emulation.setDeviceMetricsOverride', {width:1440,height:1100,deviceScaleFactor:1,mobile:false});
  await evaluate("document.querySelector('#next_time').click()");
  await wait("document.querySelector('a[data-value=time]').classList.contains('active')", 'continue to time options');
  await evaluate("document.querySelector('input[name=time_mode][value=latest]').click(); document.querySelector('#latest').value=2; document.querySelector('#latest').dispatchEvent(new Event('change',{bubbles:true}))");
  await evaluate("document.querySelector('a[data-value=review]').click()");
  await wait("document.querySelector('#validation').innerText.includes('automatically')", 'automatic availability review');
  console.log('Generated query:', await evaluate("document.querySelector('#code').innerText"));
  await wait("document.querySelector('#config').href.includes('/download/')", 'query downloads');
  for (const [id,file] of [['script','/tmp/imfexplorer-query.R'],['config','/tmp/imfexplorer-query.json']]) {
    const result = await evaluate(`(async()=>{const r=await fetch(document.querySelector('#${id}').href);return {ok:r.ok,text:await r.text()}})()`);
    if(!result.ok) throw new Error('Download failed: '+id);
    fs.writeFileSync(file,result.text);
  }

  await evaluate("document.querySelector('a[data-value=retrieve]').click(); document.querySelector('#retrieve').click()");
  await wait("document.querySelector('#result_status').innerText.includes('2 returned observations')", 'retrieved fixture data');
  if(!await evaluate("['exclude_unavailable','broad_ok'].every(id=>{const e=document.getElementById(id);const box=e.closest('.shiny-input-container');const label=e.closest('label').querySelector('span');const p=getComputedStyle(box.parentElement);return box.getBoundingClientRect().width>=box.parentElement.clientWidth-parseFloat(p.paddingLeft)-parseFloat(p.paddingRight)-2 && label.getBoundingClientRect().height<=parseFloat(getComputedStyle(label).lineHeight)*1.5})")) throw new Error('Retrieval checkboxes should fill the row and fit on one line at desktop width');

  await wait("document.querySelector('#series_plot img')?.getAttribute('src')", 'plot');
  await wait("document.querySelector('#excel').href.includes('/download/')", 'data downloads');
  for (const [id,file] of [['excel','/tmp/imfexplorer-data.xlsx'],['rds','/tmp/imfexplorer-data.rds']]) {
    const result = await evaluate(`(async()=>{const r=await fetch(document.querySelector('#${id}').href);return {ok:r.ok,bytes:Array.from(new Uint8Array(await r.arrayBuffer()))}})()`);
    if(!result.ok) throw new Error('Download failed: '+id);
    fs.writeFileSync(file,Buffer.from(result.bytes));
  }

  const shot = await cmd('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
  fs.writeFileSync('/tmp/imfexplorer-smoke.png',Buffer.from(shot.data,'base64'));
  await evaluate("document.querySelector('a[data-value=time]').click(); document.querySelector('#latest').value=3; document.querySelector('#latest').dispatchEvent(new Event('change',{bubbles:true})); document.querySelector('a[data-value=retrieve]').click()");
  await wait("document.querySelector('#result_status').innerText.includes('EARLIER QUERY')", 'stale result marker');
  await evaluate("document.querySelector('a[data-value=dimensions]').click(); document.querySelector('button[id$=_clear]').click()");
  await wait("document.querySelectorAll('select[id^=dim_]')[0].selectize.getValue().length===0", 'clear dimension');
  await evaluate("document.querySelector('a[data-value=dataset]').click(); document.querySelectorAll('#datasets table tbody tr')[1].querySelector('td').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}))");
  await wait("document.querySelector('#dimension_controls').innerText.includes('SECTOR')", 'different dataset dimensions');
  await evaluate("document.querySelector('a[data-value=retrieve]').click()");
  await wait("document.querySelector('#result_status').innerText.includes('No data retrieved')", 'result reset');

  const doc = await cmd('DOM.getDocument');
  const fileInput = await cmd('DOM.querySelector',{nodeId:doc.root.nodeId,selector:'#import'});
  await cmd('DOM.setFileInputFiles',{nodeId:fileInput.nodeId,files:['/tmp/imfexplorer-query.json']});
  await wait("document.querySelector('#summary').innerText.includes('Synthetic regions [A]') && document.querySelector('#summary').innerText.includes('Label index [index]') && document.querySelector('#summary').innerText.includes('Latest 2')", 'JSON import restores dataset, filters and time');
  await evaluate("document.querySelector('#clear_query').click()");
  await wait("document.querySelector('#summary').innerText.includes('Choose a dataset') && document.querySelector('input[name=time_mode][value=all]').checked && document.querySelector('#start').value==='' && document.querySelector('#end').value===''", 'clear restored query and time');
  if(exceptions.length) throw new Error('Browser exceptions: '+JSON.stringify(exceptions));
  console.log('PASS: browser catalogue, lazy dimensions, server-side choices, conditional update, retained invalid code, review, retrieval, plot, stale results, clear, dataset reset, all four downloads, JSON reimport, dataset search, select all, individual chip removal, clear current query, automatic retrieval without manual refresh, responsive dimension cards.');
  ws.close();
})().catch(e => {console.error(e);process.exit(1)});
