// Run against a local server containing both GitHub Pages output directories.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const base = process.env.MARS_PAGES_TEST_URL || 'http://127.0.0.1:8766/mars-terraforming/';
const mainKey = 'mars_terraforming.save.mars-terraforming-main_normal';
const developKey = 'mars_terraforming.save.mars-terraforming-develop_development';

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN,
    headless: true,
    // Keep updater descendants from inheriting the browser's stdio pipes.
    args: ['--disable-updater-scheduler'],
  });
  let context;
  let result;
  try {
    context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
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
    const main = await page(base);
    assert.equal(await main.getByRole('button', { name: '開発 +5分' }).count(), 0);
    await main.getByRole('button', { name: '機関運営', exact: true }).click();
    await main.getByRole('button', { name: '研究者を1人増やす', exact: true }).click();
    await main.getByRole('button', { name: '人員配分を確定', exact: true }).click();
    await main.waitForTimeout(300);
    const mainBefore = await snapshot(main, mainKey);
    assert.equal(mainBefore.contentVersion, 'district-5');
    assert.equal(mainBefore.researchers, 7);
    assert.equal(mainBefore.specialistCount, 12);
    const firstCaches = await main.evaluate(() => caches.keys());
    const mainPrefix = `mars-terraforming:${encodeURIComponent(new URL(base).pathname)}:`;
    assert.ok(firstCaches.some(key => key.startsWith(mainPrefix)));
    const developUrl = new URL('develop/', base).href;
    const develop = await page(developUrl);
    assert.equal(await develop.getByRole('button', { name: '開発 +5分' }).count(), 1);
    await develop.getByRole('button', { name: '機関運営', exact: true }).click();
    const devBefore = await snapshot(develop, developKey);
    assert.equal(devBefore.contentVersion, 'district-5');
    assert.equal(devBefore.researchers, 6);
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
    assert.equal((await snapshot(main, mainKey)).researchers, 7);
    assert.equal((await snapshot(develop, developKey)).researchers, 6);
    for (const target of [main, develop]) {
      await target.getByRole('button', { name: '機関運営', exact: true }).click();
      await target.getByRole('button', { name: '提携・支援', exact: true }).click();
      await target.getByRole('button', { name: '人員配分', exact: true }).click();
    }
    await main.getByRole('button', { name: '設備・進行', exact: true }).click();
    await develop.getByRole('button', { name: '設備・進行', exact: true }).click();
    assert.equal(await main.getByRole('button', { name: '開発 +5分' }).count(), 0);
    assert.equal(await develop.getByRole('button', { name: '開発 +5分' }).count(), 1);
    assert.deepEqual(errors, []);
    result = { result: 'PASS', main: base, develop: developUrl, checks: ['district-5 agency UI on both branches', 'staff allocation persists offline and stays isolated', 'separate saves and locks', 'main has no time skip', 'develop only advances its own world', 'cache namespaces coexist', 'no hidden precache files', 'both reload offline concurrently'], caches: allCaches };
  } finally {
    try {
      // Restore networking and close the context before waiting for browser exit.
      if (context) {
        await context.setOffline(false);
        await context.close();
      }
    } finally {
      await browser.close();
    }
  }
  // Report success only after Playwright has released the browser and its pipes.
  console.log(JSON.stringify(result, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
