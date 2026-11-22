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
const code = 'function must(r){if(r&&r.error)throw r.error;return r;}\n' + [
  section('function historyGroups(', 'async function reload('),
  section('function daysBetween(', 'async function clearCurrentList(')
].join('\n');

function setup({insertError = null, historyError = null} = {}) {
  const now = Date.now();
  const state = {
    user: {id: 'user'},
    listId: 'list',
    cats: [{id: 'cat', name: 'Frutta'}],
    prods: [
      {id: 'apple', description: 'Mela', category_id: 'cat'},
      {id: 'pear', description: 'Pera', category_id: 'cat'}
    ],
    items: [{id: 'selected', product_id: 'pear', status: 'to_buy'}],
    history: [20, 10].map(days => ({
      product_id: 'apple',
      product_description: 'Mela',
      category_name: 'Frutta',
      quantity: 1,
      purchased_at: new Date(now - days * 86400000).toISOString()
    })),
    historyError
  };
  const alerts = [];
  const button = {disabled: false};
  const calls = [];
  let reloads = 0;
  const context = {
    S: state,
    crypto: {randomUUID: () => 'new-item'},
    normalize: s => String(s || '').toLowerCase().trim(),
    normCategory: s => String(s || 'Generale').trim() || 'Generale',
    catName: id => state.cats.find(c => c.id === id)?.name || '',
    prod: id => state.prods.find(p => p.id === id),
    t: (key, values = {}) => `${key}${values.count ? `:${values.count}` : ''}`,
    alert: message => alerts.push(message),
    confirm: () => true,
    $: () => button,
    render: () => {},
    reload: async () => { reloads++; },
    sb: {
      from(table) {
        return {
          async insert(rows) {
            calls.push({table, rows});
            return {error: table === 'list_items' ? insertError : historyError};
          },
          delete() {
            calls.push({table, operation: 'delete'});
            return {eq: () => ({eq: async () => ({error: null})})};
          }
        };
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(code, context);
  return {context, state, alerts, button, calls, get reloads() { return reloads; }};
}

test('adds due products without duplicating selected products', async () => {
  const fixture = setup();
  await fixture.context.suggestProductsForCurrentList();
  assert.deepEqual(Array.from(fixture.state.items, item => item.product_id), ['pear', 'apple']);
  assert.equal(fixture.calls.length, 1);
  assert.equal(fixture.calls[0].rows[0].product_id, 'apple');
  assert.deepEqual(fixture.alerts, ['suggestedAdded:1']);
  assert.equal(fixture.button.disabled, false);
});

test('reports history errors and does not add products', async () => {
  const fixture = setup({historyError: {message: 'history unavailable'}});
  await fixture.context.suggestProductsForCurrentList();
  assert.match(fixture.alerts[0], /historyLoadError.*history unavailable/);
  assert.equal(fixture.calls.length, 0);
  assert.equal(fixture.state.items.length, 1);
});

test('does not show unsaved products when insertion fails', async () => {
  const fixture = setup({insertError: {message: 'insert failed'}});
  await fixture.context.suggestProductsForCurrentList();
  assert.match(fixture.alerts[0], /suggestionSaveError.*insert failed/);
  assert.equal(fixture.state.items.length, 1);
  assert.equal(fixture.reloads, 1);
  assert.equal(fixture.button.disabled, false);
});

test('explains when purchase history is insufficient', async () => {
  const fixture = setup();
  fixture.state.history = fixture.state.history.slice(0, 1);
  await fixture.context.suggestProductsForCurrentList();
  assert.deepEqual(fixture.alerts, ['noSuggested']);
  assert.equal(fixture.calls.length, 0);
});

test('does not insert the same suggestion twice while a request is pending', async () => {
  const fixture = setup();
  let resolveInsert;
  let inserts = 0;
  fixture.context.sb.from = () => ({
    insert: () => {
      inserts++;
      return new Promise(resolve => { resolveInsert = resolve; });
    }
  });
  const first = fixture.context.suggestProductsForCurrentList();
  assert.equal(fixture.button.disabled, true);
  await fixture.context.suggestProductsForCurrentList();
  assert.equal(inserts, 1);
  resolveInsert({error: null});
  await first;
  assert.equal(fixture.button.disabled, false);
});
