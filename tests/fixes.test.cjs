const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('index.html', 'utf8');
const section = (start, end) => {
  const first = html.indexOf(start);
  const last = html.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `Missing section: ${start}`);
  return html.slice(first, last);
};
const URL_OK = 'https://proj.supabase.co/storage/v1/object/public/product-images/abc-foto.jpg';

function load(extra = {}) {
  const alerts = [];
  let reloads = 0;
  const context = {
    SUPABASE_URL: 'https://proj.supabase.co',
    S: {listId: 'list', items: [], user: {id: 'u'}},
    t: key => key,
    alert: m => alerts.push(m),
    confirm: () => true,
    render: () => {},
    reload: () => { reloads++; },
    icon: () => '',
    crypto: {randomUUID: () => 'local-id'},
    console,
    ...extra
  };
  vm.createContext(context);
  vm.runInContext(`
    let pendingWrites=0,writeEpoch=0,reloadAfterWrites=false;const writeChains=new Map();
    ${section('const esc=', 'const normalize=')}
    ${section('/* L\'URL non finisce mai dentro onclick', 'function render(')}
    ${section('function queueWrite(', 'function changeQty(')}
    ${section('async function closeCart(', 'function hidePhotoModal(')}
    this.state=()=>({pendingWrites,reloadAfterWrites});
    Object.assign(this,{thumb,safeImg,imgPath});
  `, context);
  return {context, alerts, get reloads() { return reloads; }};
}

test('thumbnail does not put a malicious url inside onclick', () => {
  const {context} = load();
  const evil = "x');alert(1)//";
  assert.match(context.thumb({image_url: evil, description: 'd'}), /list-avatar/);
  const html = context.thumb({image_url: URL_OK, description: 'd'});
  assert.match(html, /data-url=/);
  assert.match(html, /openPhotoModal\(this\.dataset\.url\)/);
  assert.ok(!html.includes(`openPhotoModal('`));
});

test('only https urls of the project bucket are accepted', () => {
  const {context} = load();
  assert.equal(context.safeImg(URL_OK), URL_OK);
  assert.equal(context.safeImg('https://evil.example/x.jpg'), '');
  assert.equal(context.safeImg('javascript:alert(1)'), '');
  assert.equal(context.safeImg(URL_OK + '"onerror="alert(1)'), '');
  assert.equal(context.safeImg(null), '');
  assert.equal(context.imgPath(URL_OK), 'abc-foto.jpg');
});

test('writes on the same product run in tap order', async () => {
  const {context} = load();
  const order = [];
  let releaseFirst;
  const first = context.queueWrite('p1', () => new Promise(r => { releaseFirst = () => { order.push('insert'); r({error: null}); }; }));
  const second = context.queueWrite('p1', async () => { order.push('delete'); return {error: null}; });
  await new Promise(r => setTimeout(r, 10));
  assert.deepEqual(order, []);
  releaseFirst();
  await Promise.all([first, second]);
  assert.deepEqual(order, ['insert', 'delete']);
  assert.equal(context.state().pendingWrites, 0);
});

test('a failed write alerts once and reloads after the queue drains', async () => {
  const fixture = load();
  await Promise.all([
    fixture.context.queueWrite('p1', async () => ({error: {message: 'rete assente'}})),
    fixture.context.queueWrite('p2', async () => ({error: null}))
  ]);
  assert.deepEqual(fixture.alerts, ['saveError rete assente']);
  assert.equal(fixture.reloads, 1);
});

test('close cart waits for pending writes and uses the atomic rpc', async () => {
  const calls = [];
  const fixture = load({sb: {rpc: async (name, args) => { calls.push([name, args, fixture.context.state().pendingWrites]); return {error: null}; }}});
  let release;
  fixture.context.queueWrite('p1', () => new Promise(r => { release = () => r({error: null}); }));
  const closing = fixture.context.closeCart();
  await new Promise(r => setTimeout(r, 10));
  assert.equal(calls.length, 0);
  release();
  await closing;
  assert.deepEqual(calls.map(c => [c[0], c[1].p_list_id, c[2]]), [['close_shopping_cart', 'list', 0]]);
  assert.equal(fixture.reloads, 1);
  assert.deepEqual(fixture.alerts, []);
});

test('close cart reports errors without losing the list', async () => {
  const fixture = load({sb: {rpc: async () => ({error: {message: 'offline'}})}});
  await fixture.context.closeCart();
  assert.deepEqual(fixture.alerts, ['closeCartError offline']);
  assert.equal(fixture.reloads, 1);
});
