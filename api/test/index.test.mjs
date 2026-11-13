import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { formatCrore, formatKm, escapeHtml } from '../src/index.js';

function fakeDb(rows) {
  return { prepare: () => ({ all: async () => ({ results: rows }) }) };
}

const get = (path, rows = []) =>
  worker.fetch(new Request(`https://example.com${path}`), { DB: fakeDb(rows) });

test('/ redirects to /home', async () => {
  const res = await get('/');
  assert.equal(res.status, 302);
  assert.equal(res.headers.get('location'), 'https://example.com/home');
});

test('/home shows the empty state when the flat table is empty', async () => {
  const res = await get('/home');
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /text\/html/);
  assert.match(await res.text(), /No flats yet\./);
});

test('/home lists rows from the flat table', async () => {
  const res = await get('/home', [
    { id: 1, name: '2-bed <near> park', price: 9500000, size_sqft: 1200, distance_m: 2345, discarded: 0 },
    { id: 2, name: 'Rejected', price: null, size_sqft: null, distance_m: null, discarded: 1 },
  ]);
  const html = await res.text();
  assert.match(html, /2-bed &lt;near&gt; park/);
  assert.match(html, /₹0\.95 Cr/);
  assert.match(html, /2\.3 km/);
  assert.match(html, /class="discarded"/);
});

test('unknown paths are 404 and writes are 405', async () => {
  assert.equal((await get('/nope')).status, 404);
  const res = await worker.fetch(new Request('https://example.com/home', { method: 'POST' }), { DB: fakeDb([]) });
  assert.equal(res.status, 405);
});

test('formatters', () => {
  assert.equal(formatCrore(10500000), '₹1.05 Cr');
  assert.equal(formatCrore(null), '–');
  assert.equal(formatKm(1500), '1.5 km');
  assert.equal(escapeHtml(`"a"&'b'`), '&quot;a&quot;&amp;&#39;b&#39;');
});
