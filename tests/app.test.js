// End-to-end check of the journal in local (IndexedDB) mode on a phone-sized viewport.
// Run: node tests/app.test.js
const http = require('http'), fs = require('fs'), path = require('path'), os = require('os');
const { chromium, devices } = require('playwright');
const root = path.join(__dirname, '..');
const types = { '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.html': 'text/html' };
const shot = process.env.SHOTS;
let fails = 0;
function check(name, ok, extra) { console.log((ok ? 'PASS  ' : 'FAIL  ') + name + (extra ? '  ' + extra : '')); if (!ok) fails++; }

(async () => {
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(req.url.split('?')[0]);
    if (p === '/') {
      // same skeleton the artifact host wraps the page in
      res.setHeader('content-type', 'text/html');
      return res.end('<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>' + fs.readFileSync(path.join(root, 'index.html'), 'utf8') + '</body></html>');
    }
    const f = path.join(root, p);
    if (!f.startsWith(root) || !fs.existsSync(f)) { res.statusCode = 404; return res.end(); }
    res.setHeader('content-type', types[path.extname(f)] || 'application/octet-stream');
    res.end(fs.readFileSync(f));
  }).listen(0);
  const url = 'http://localhost:' + server.address().port + '/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ ...devices['iPhone 14'], defaultBrowserType: undefined, permissions: ['clipboard-read', 'clipboard-write'], acceptDownloads: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/fonts\.g|ERR_|Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await page.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await page.goto(url);
  await page.waitForSelector('.card');

  check('18 places shown', await page.locator('.card').count() === 18);
  check('first card is The Vineyard Hotel', (await page.locator('.card h2').first().textContent()) === 'The Vineyard Hotel');
  check('no horizontal scroll', await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  check('category filter counts', (await page.locator('.chip').allTextContents()).join('|') === 'All18|Accommodation2|Restaurant/bar5|Nature/activity6|Estate/garden4|Transport1', (await page.locator('.chip').allTextContents()).join('|'));
  if (shot) await page.screenshot({ path: shot + '/1-feed.png' });

  // filter
  await page.click('.chip[data-filter="transport"]');
  check('filter shows only transport', await page.locator('.card').count() === 1 && (await page.locator('.card h2').textContent()) === 'Hertz');
  await page.click('.chip[data-filter="all"]');

  // list view
  await page.click('#view-list');
  check('list view has 18 bullets', await page.locator('.recap li').count() === 18);
  if (shot) await page.screenshot({ path: shot + '/2-list.png' });
  await page.click('#view-cards');

  // edit a review
  await page.locator('.card').nth(2).locator('h2').click();
  await page.waitForSelector('#sheet[open]');
  if (shot) await page.screenshot({ path: shot + '/3-sheet-empty.png' });
  await page.click('#sheet-edit');
  await page.fill('#f-review', 'Edited review text.');
  await page.fill('#f-notes', 'raw dictated note\nsecond line');
  await page.selectOption('#f-rec', 'Highly recommended');
  await page.fill('#f-date', '2026-11-03');
  if (shot) await page.screenshot({ path: shot + '/4-edit.png' });
  await page.click('#place-form button[type=submit]');
  check('review edit shows in sheet', (await page.locator('#sheet .review').textContent()) === 'Edited review text.');
  check('notes kept alongside', (await page.locator('#sheet .notes p').textContent()) === 'raw dictated note\nsecond line');

  // add multiple photos
  const jpgs = await page.evaluate(async () => {
    const out = [];
    for (const [w, h, c] of [[1600, 1200, '#3d5c48'], [1200, 1600, '#9c4a61'], [3000, 2000, '#c9a66b']]) {
      const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
      const g = cv.getContext('2d'); g.fillStyle = c; g.fillRect(0, 0, w, h); g.fillStyle = '#fff'; g.font = '200px sans-serif'; g.fillText(w + 'x' + h, 100, 400);
      out.push(cv.toDataURL('image/jpeg', 0.9).split(',')[1]);
    }
    return out;
  });
  await page.setInputFiles('#sheet-pick', jpgs.map((b, i) => ({ name: 'IMG_' + i + '.jpg', mimeType: 'image/jpeg', buffer: Buffer.from(b, 'base64') })));
  await page.waitForSelector('.queue', { timeout: 5000 }).catch(() => {});
  if (shot) await page.screenshot({ path: shot + '/5-uploading.png' });
  await page.waitForFunction(() => document.querySelectorAll('#sheet .thumbs button').length === 3 && !document.querySelector('.queue'), null, { timeout: 30000 });
  check('3 photos added in one go', true);
  // a non-photo gives a clear, dismissible error
  await page.setInputFiles('#sheet-pick', [{ name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('hello') }]);
  await page.waitForSelector('.q.is-error');
  check('bad file shows error with retry/dismiss', await page.locator('.q.is-error [data-act="q-dismiss"]').count() === 1, await page.locator('.q.is-error .q-state').textContent());
  await page.click('.q.is-error [data-act="q-dismiss"]');
  if (shot) await page.screenshot({ path: shot + '/6-sheet-photos.png' });

  // cover, caption, reorder photos
  const cover0 = await page.locator('#sheet .hero img').getAttribute('src');
  await page.click('[data-act="manage"]');
  await page.locator('.m').nth(1).locator('[data-act="ph-cover"]').click();
  await page.locator('.m').nth(1).locator('input.cap').fill('Sunset from the terrace');
  await page.locator('.m').nth(1).locator('input.cap').blur();
  await page.locator('.m').nth(2).locator('[data-act="ph-up"]').click();
  if (shot) await page.screenshot({ path: shot + '/7-manage.png' });
  await page.locator('.m').nth(0).locator('[data-act="ph-remove"]').click();
  await page.locator('.m').nth(0).locator('[data-act="ph-remove-yes"]').click();
  await page.click('[data-act="manage"]');
  const cover1 = await page.locator('#sheet .hero img').getAttribute('src');
  check('cover photo changed', cover0 !== cover1);
  check('photo removed (2 left)', await page.locator('#sheet .thumbs button').count() === 2);
  await page.locator('#sheet .hero').click();
  await page.waitForSelector('#lightbox[open]');
  check('lightbox shows caption', /Sunset from the terrace/.test(await page.locator('#lb-cap').textContent()));
  if (shot) await page.screenshot({ path: shot + '/8-lightbox.png' });
  await page.click('#lb-close');
  await page.click('#sheet-close');
  await page.waitForFunction(() => !document.querySelector('#sheet[open]'));

  // reorder places
  await page.click('#btn-reorder');
  await page.locator('.sortrow').nth(0).locator('[data-act="pl-down"]').click();
  // drag row 3 (Foxcroft, now index 2) up to the top with the handle
  const grip = page.locator('.sortrow').nth(2).locator('.grip');
  const gb = await grip.boundingBox(), top = await page.locator('.sortrow').nth(0).boundingBox();
  await page.mouse.move(gb.x + gb.width / 2, gb.y + gb.height / 2);
  await page.mouse.down();
  await page.mouse.move(gb.x + gb.width / 2, gb.y - 30, { steps: 4 });
  await page.mouse.move(gb.x + gb.width / 2, top.y + 2, { steps: 6 });
  await page.mouse.up();
  if (shot) await page.screenshot({ path: shot + '/9-reorder.png' });
  await page.click('#btn-reorder');
  const names = () => page.locator('.card h2').allTextContents();
  let n = await names();
  check('reorder by arrows and drag', n[0] === 'Foxcroft' && n[1] === 'Kirstenbosch Botanical Garden' && n[2] === 'The Vineyard Hotel', n.slice(0, 3).join(' / '));

  // add a place
  await page.click('#btn-add');
  await page.fill('#f-name', 'Test Café');
  await page.fill('#f-location', 'Stellenbosch');
  await page.selectOption('#f-category', 'restaurant');
  await page.fill('#f-review', 'Good coffee.');
  await page.click('#place-form button[type=submit]');
  await page.click('#sheet-close');
  check('place added (19)', await page.locator('.card').count() === 19);

  // refresh
  await page.waitForFunction(() => /Saved/.test(document.getElementById('save-status').textContent));
  await page.reload();
  await page.waitForSelector('.card');
  n = await names();
  check('after refresh: order kept', n[0] === 'Foxcroft' && n[2] === 'The Vineyard Hotel' && n.length === 19);
  check('after refresh: review edit kept', (await page.locator('.card').first().locator('.card-review').textContent()) === 'Edited review text.');
  const cardImg = page.locator('.card').first().locator('.card-photo img');
  check('after refresh: cover photo still on its place', await cardImg.count() === 1 && await cardImg.evaluate(i => i.decode().then(() => i.naturalWidth > 0)));
  check('after refresh: only that place has photos', await page.locator('.card-photo img').count() === 1);
  if (shot) await page.screenshot({ path: shot + '/10-after-refresh.png' });

  // recap
  await page.click('#btn-recap');
  await page.waitForFunction(() => !document.getElementById('toast').hidden);
  const clip = await page.evaluate(() => navigator.clipboard.readText());
  const lines = clip.split('\n');
  check('recap copied', lines[0] === 'South Africa — November 2026' && lines.length === 21 && lines[2] === '• Foxcroft — Restaurant/bar: Edited review text. (Highly recommended)' && lines.includes('• Test Café, Stellenbosch — Restaurant/bar: Good coffee.'), lines[2]);
  check('recap preserves supplied wording', clip.includes('• Hertz — Transport: Mediocre experience: booked car unavailable initially, with a 90-minute wait to exchange it.') && clip.includes('allow 2½–3 hours.') && clip.includes('• Chapman’s Peak Drive — Nature/activity:'));

  // backup
  await page.click('#btn-backup');
  await page.click('[data-m="make"]');
  await page.waitForSelector('[data-m="save"]');
  const [dl] = await Promise.all([page.waitForEvent('download'), page.click('[data-m="save"]')]);
  const zipPath = path.join(os.tmpdir(), 'tj-test-backup.zip');
  await dl.saveAs(zipPath);
  check('backup downloaded', /^travel-journal-backup-\d{4}-\d\d-\d\d\.zip$/.test(dl.suggestedFilename()) && fs.statSync(zipPath).size > 20000, dl.suggestedFilename() + ' ' + fs.statSync(zipPath).size + ' bytes');

  // wreck the journal, then restore
  await page.waitForFunction(() => !document.querySelector('#modal[open]'));
  await page.locator('.card').first().locator('h2').click();
  await page.click('#sheet-edit');
  await page.click('[data-act="place-delete"]');
  await page.click('[data-m="yes"]');
  await page.locator('.card').first().locator('h2').click();
  await page.click('#sheet-edit');
  await page.fill('#f-review', 'WRONG');
  await page.click('#place-form button[type=submit]');
  await page.click('#sheet-close');
  check('journal changed before restore (18, no photos)', await page.locator('.card').count() === 18 && await page.locator('.card-photo img').count() === 0);
  await page.click('#btn-backup');
  await page.setInputFiles('#restore-pick', zipPath);
  await page.waitForSelector('[data-m="go"]');
  if (shot) await page.screenshot({ path: shot + '/11-restore-confirm.png' });
  await page.click('[data-m="go"]');
  await page.waitForFunction(() => /Journal restored/.test(document.getElementById('modal-body').textContent), null, { timeout: 30000 });
  await page.click('[data-m="close"]');
  n = await names();
  check('restore: 19 places in saved order', n.length === 19 && n[0] === 'Foxcroft' && n[1] === 'Kirstenbosch Botanical Garden');
  check('restore: review back', (await page.locator('.card').first().locator('.card-review').textContent()) === 'Edited review text.');
  await page.reload();
  await page.waitForSelector('.card');
  const img2 = page.locator('.card').first().locator('.card-photo img');
  check('restore survives refresh with photos', await img2.count() === 1 && await img2.evaluate(i => i.decode().then(() => i.naturalWidth > 0)));
  await page.locator('.card').first().locator('h2').click();
  await page.waitForSelector('#sheet .thumbs');
  check('restore: 2 photos, caption and cover kept', await page.locator('#sheet .thumbs button').count() === 2 && (await page.locator('#sheet .hero img').getAttribute('alt')) === 'Sunset from the terrace');
  const blobCount = await page.evaluate(() => new Promise(r => { const q = indexedDB.open('travel-journal'); q.onsuccess = () => { const c = q.result.transaction('blobs').objectStore('blobs').count(); c.onsuccess = () => r(c.result); }; }));
  check('no orphaned photo files left behind', blobCount === 4, 'blobs=' + blobCount);

  // map
  await page.click('#sheet-close');
  await page.click('#view-map');
  await page.waitForSelector('.tjmap svg');
  const pinSel = '#map [role="button"][aria-label]';
  await page.waitForFunction(s => document.querySelectorAll(s).length >= 15, pinSel);
  check('map: 15 seeded pins, 4 unplaced', await page.locator(pinSel).count() === 15 && await page.locator('.unplaced-row').count() === 4, await page.locator(pinSel).count() + ' pins, ' + await page.locator('.unplaced-row').count() + ' unplaced');
  await page.waitForTimeout(400);
  if (shot) await page.screenshot({ path: shot + '/13-map.png' });
  await page.locator('.unplaced-row', { hasText: 'Hertz' }).locator('[data-act="place-pin"]').click();
  const mb = await page.locator('#map').boundingBox();
  await page.mouse.click(mb.x + mb.width / 2, mb.y + mb.height / 2);
  await page.waitForFunction(s => document.querySelectorAll(s).length === 16, pinSel);
  check('map: tap places a pin and selects it', (await page.locator('.map-sel h2').textContent()) === 'Hertz' && await page.locator('.unplaced-row').count() === 3);
  if (shot) await page.screenshot({ path: shot + '/14-map-selected.png' });
  await page.click('[data-act="map-open"]');
  await page.waitForSelector('#sheet[open]');
  await page.click('#sheet-edit');
  check('map: position shown in edit form', /^-?\d+\.\d{5}, -?\d+\.\d{5}$/.test(await page.inputValue('#f-pos')), await page.inputValue('#f-pos'));
  await page.fill('#f-pos', 'https://www.google.com/maps/place/X/@-33.9715,18.6021,17z');
  await page.click('#place-form button[type=submit]');
  await page.click('#sheet-close');
  await page.waitForFunction(() => /Saved/.test(document.getElementById('save-status').textContent));
  await page.reload();
  await page.waitForSelector('.tjmap svg');
  await page.waitForFunction(s => document.querySelectorAll(s).length === 16, pinSel);
  const hz = await page.evaluate(() => new Promise(r => { const q = indexedDB.open('travel-journal'); q.onsuccess = () => { const c = q.result.transaction('docs').objectStore('docs').get('place:hertz'); c.onsuccess = () => r(c.result); }; }));
  check('map: pasted Maps link parsed and kept after refresh', hz.lat === -33.9715 && hz.lng === 18.6021 && hz.posApprox === false, JSON.stringify([hz.lat, hz.lng]));
  await page.click('#view-cards');

  // desktop + dark screenshot
  if (shot) {
    const d = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: 'dark', deviceScaleFactor: 1 });
    const p2 = await d.newPage(); await p2.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
    await p2.goto(url); await p2.waitForSelector('.card'); await p2.click('#view-map'); await p2.waitForSelector('.tjmap svg'); await p2.waitForTimeout(500); await p2.screenshot({ path: shot + '/12-desktop-dark.png' });
    check('desktop: no horizontal scroll', await p2.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  }
  check('no page errors', errors.length === 0, errors.join(' | '));
  await browser.close(); server.close();
  console.log(fails ? fails + ' FAILED' : 'All checks passed');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
