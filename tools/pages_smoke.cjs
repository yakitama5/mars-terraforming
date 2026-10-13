// Run against a local server containing both GitHub Pages output directories.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const base = process.env.MARS_PAGES_TEST_URL || 'http://127.0.0.1:8766/mars-terraforming/';
const mainKey = 'mars_terraforming.save.mars-terraforming-main_normal';
const developKey = 'mars_terraforming.save.mars-terraforming-develop_development';

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN, headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const errors = [];
  const page = async url => {
    const result = await context.newPage();
    result.on('pageerror', error => errors.push(String(error)));
    await result.goto(url);
    await ready(result);
    return result;
  };
  const ready = async page => {
    await page.getByRole('button', { name: '設備・進行', exact: true }).waitFor({ timeout: 60000 });
    await page.waitForFunction(() => navigator.serviceWorker.controller?.scriptURL === new URL('offline_worker.js', document.baseURI).href, null, { timeout: 60000 });
    await page.evaluate(() => navigator.serviceWorker.ready);
  };
  const snapshot = (page, key) => page.evaluate(key => {
    const bundle = JSON.parse(localStorage.getItem(key));
    return JSON.parse(JSON.parse(bundle.primary).payload);
  }, key);
  try {
    const main = await page(base);
    assert.equal(await main.getByRole('button', { name: '開発 +5分' }).count(), 0);
    const mainBefore = await snapshot(main, mainKey);
    const firstCaches = await main.evaluate(() => caches.keys());
    const mainPrefix = `mars-terraforming:${encodeURIComponent(new URL(base).pathname)}:`;
    assert.ok(firstCaches.some(key => key.startsWith(mainPrefix)));
    const developUrl = new URL('develop/', base).href;
    const develop = await page(developUrl);
    assert.equal(await develop.getByRole('button', { name: '開発 +5分' }).count(), 1);
    const devBefore = await snapshot(develop, developKey);
    assert.notEqual(mainBefore.worldId, devBefore.worldId);
    await develop.getByRole('button', { name: '開発 +5分' }).click();
    await develop.waitForTimeout(300);
    const devAfter = await snapshot(develop, developKey);
    assert.ok(devAfter.simulatedMs >= devBefore.simulatedMs + 300000);
    // The main tab's normal clock may save independently; its game was not accelerated.
    const mainAfter = await snapshot(main, mainKey);
    assert.ok(mainAfter.simulatedMs - mainBefore.simulatedMs < 300000);
    assert.equal(mainAfter.worldId, mainBefore.worldId);
    const allCaches = await main.evaluate(() => caches.keys());
    for (const key of firstCaches) assert.ok(allCaches.includes(key), `Other scope removed ${key}`);
    assert.ok(allCaches.some(key => key.startsWith(`mars-terraforming:${encodeURIComponent(new URL(developUrl).pathname)}:`)));
    const cachedRequests = await main.evaluate(async () => {
      const keys = await caches.keys();
      const result = [];
      for (const key of keys) for (const request of await (await caches.open(key)).keys()) result.push(new URL(request.url).pathname);
      return result;
    });
    assert.ok(cachedRequests.length > 20);
    assert.ok(cachedRequests.every(path => !path.split('/').some(part => part.startsWith('.'))));
    await context.setOffline(true);
    await main.reload();
    await ready(main);
    assert.equal((await snapshot(main, mainKey)).worldId, mainBefore.worldId);
    await develop.reload();
    await ready(develop);
    assert.equal((await snapshot(develop, developKey)).worldId, devBefore.worldId);
    assert.ok((await snapshot(develop, developKey)).simulatedMs >= devAfter.simulatedMs);
    await main.getByRole('button', { name: '設備・進行' }).click();
    await develop.getByRole('button', { name: '設備・進行' }).click();
    assert.equal(await main.getByRole('button', { name: '開発 +5分' }).count(), 0);
    assert.equal(await develop.getByRole('button', { name: '開発 +5分' }).count(), 1);
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ result: 'PASS', main: base, develop: developUrl, checks: ['separate saves and locks', 'main has no time skip', 'develop only advances its own world', 'cache namespaces coexist', 'no hidden precache files', 'both reload offline concurrently'], caches: allCaches }, null, 2));
  } finally {
    // Restore networking before closing contexts with offline fetches in flight.
    await context.setOffline(false);
    await context.close();
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
