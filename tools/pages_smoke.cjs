// Run against the published Pages site or a local server containing both paths.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const { completeFirstRun, firstRunControl } = require('./complete_first_run.cjs');
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
      const intro = page.getByRole('button', { name: '物語をスキップ', exact: true });
      const game = page.getByRole('button', { name: '設備・進行', exact: true });
      const movie = page.getByRole('button', { name: '物語へ', exact: true });
      const title = page.getByRole('button', { name: 'タップまたはクリックしてスタート', exact: true });
      const playable = movie.or(intro).or(game).or(firstRunControl(page));
      await title.or(playable).first().waitFor({ timeout: 60000 });
      if (await title.count()) {
        await title.click();
        await playable.first().waitFor({ timeout: 60000 });
      }
      if (await movie.count()) {
        await movie.click();
        await intro.waitFor();
      }
      if (await intro.count()) {
        await intro.click();
        await page.getByRole('button', { name: '名前は後で決める', exact: true }).click();
      }
      await completeFirstRun(page);
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
    await main.getByRole('button', { name: '都市基盤', exact: true }).click();
    assert.equal(await main.getByRole('button', { name: '研究者を1人増やす', exact: true }).count(), 0);
    await main.waitForTimeout(300);
    const mainBefore = await snapshot(main, mainKey);
    assert.equal(mainBefore.contentVersion, 'district-11');
    assert.ok(mainBefore.population >= 180);
    assert.ok(mainBefore.researchPointUnits <= (240 + (mainBefore.population + mainBefore.marsResidents) * 40) * 6000000);
    assert.equal(mainBefore.firstRunTutorial, 'completed');
    assert.ok(mainBefore.districts.some(d => d.cityId === 'earth_delta' && d.plotIndex === 1 && d.districtId === 'housing'));
    assert.ok(mainBefore.plans.some(p => p.taskId === 'life_support'));
    // Both releases expose the new map placement, including normal-time main.
    const inspectPlacement = async (target, saveKey) => {
      const before = await snapshot(target, saveKey);
      await target.getByRole('button', { name: '都市開発', exact: true }).click();
      await target.getByRole('button', { name: '住宅地区を選ぶ', exact: true }).click();
      const tile = target.getByRole('button', { name: /^デルタ湾岸の区画13、/ });
      await tile.waitFor();
      const bounds = await tile.boundingBox();
      assert.ok(bounds);
      await target.mouse.click(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
      await target.getByText(/^区画 13  ·/).waitFor();
      await target.getByRole('button', { name: '配置をやめる', exact: true }).click();
      await target.getByRole('button', { name: '住宅地区を選ぶ', exact: true }).waitFor();
      const after = await snapshot(target, saveKey);
      assert.deepEqual(after.districts, before.districts);
      assert.deepEqual(after.plans.map(p => p.id), before.plans.map(p => p.id));
    };
    const inspectGuidance = async (target, saveKey) => {
      const before = await snapshot(target, saveKey);
      await target.getByRole('button', { name: 'ガイド', exact: true }).click();
      await target.getByText('開発ガイド・Tips', { exact: true }).waitFor();
      // The map also has a guide. Select the focusable entry in the open dialog.
      await target.getByRole('button', { name: /^(?:手引き|6工程の手引き|導入の手順と達成状況を確認)$/ }).and(target.locator('[tabindex="0"]')).click();
      await target.getByRole('button', { name: '6工程', exact: true }).click();
      await target.getByText(/^最初の1時間の手引き · \d\/6達成$/).waitFor();
      await target.getByRole('button', { name: '閉じて開発を続ける', exact: true }).click();
      await target.getByRole('button', { name: '閉じる', exact: true }).and(target.locator('[tabindex="0"]')).click();
      await target.getByText('開発ガイド・Tips', { exact: true }).waitFor({ state: 'hidden' });

      await target.getByRole('button', { name: /^通知(?: \d+)?$/ }).click();
      await target.getByText(/^完了通知 · 未読 \d+件$/).waitFor();
      await target.getByRole('button', { name: /住宅地区を建設が完了/ }).first().waitFor();
      await target.getByRole('button', { name: '閉じる', exact: true }).and(target.locator('[tabindex="0"]')).click();
      await target.getByText(/^完了通知 · 未読 \d+件$/).waitFor({ state: 'hidden' });
      const after = await snapshot(target, saveKey);
      assert.equal(after.worldId, before.worldId);
      // 稼働中研究は時計で進む。案内の閲覧による新しい予約・地区変更はない。
      assert.deepEqual(after.plans.map(p => [p.id, p.taskId]), before.plans.map(p => [p.id, p.taskId]));
      assert.ok(before.research.every(id => after.research.includes(id)));
      assert.deepEqual(after.districts, before.districts);
      assert.ok(after.completionNotices.some(notice => notice.taskId === 'district_housing'));
      assert.equal(after.readCompletionNoticeId, before.readCompletionNoticeId);
    };
    await inspectPlacement(main, mainKey);
    await inspectGuidance(main, mainKey);
    const firstCaches = await main.evaluate(() => caches.keys());
    const mainPrefix = `mars-terraforming:${encodeURIComponent(new URL(base).pathname)}:`;
    assert.ok(firstCaches.some(key => key.startsWith(mainPrefix)));
    const developUrl = new URL('develop/', base).href;
    const develop = await page(developUrl);
    assert.equal(await develop.getByRole('button', { name: '開発 +5分' }).count(), 1);
    await inspectPlacement(develop, developKey);
    await inspectGuidance(develop, developKey);
    await develop.getByRole('button', { name: '機関運営', exact: true }).click();
    const devBefore = await snapshot(develop, developKey);
    assert.equal(devBefore.contentVersion, 'district-11');
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
    assert.equal((await snapshot(main, mainKey)).contentVersion, 'district-11');
    assert.equal((await snapshot(develop, developKey)).contentVersion, 'district-11');
    // Cached releases must retain usable guide and notification entries offline.
    await inspectGuidance(main, mainKey);
    await inspectGuidance(develop, developKey);
    for (const target of [main, develop]) {
      await target.getByRole('button', { name: '機関運営', exact: true }).click();
      await target.getByRole('button', { name: '提携・支援', exact: true }).click();
      await target.getByRole('button', { name: '都市基盤', exact: true }).click();
      assert.equal(await target.getByRole('button', { name: '人員配分を確定', exact: true }).count(), 0);
    }
    await main.getByRole('button', { name: '設備・進行', exact: true }).click();
    await develop.getByRole('button', { name: '設備・進行', exact: true }).click();
    assert.equal(await main.getByRole('button', { name: '開発 +5分' }).count(), 0);
    assert.equal(await develop.getByRole('button', { name: '開発 +5分' }).count(), 1);
    assert.deepEqual(errors, []);
    result = { result: 'PASS', main: base, develop: developUrl, checks: ['first housing and immediate research tutorial completed through UI on both branches', 'facility-first map placement and cancel on both branches', 'six-step onboarding guide and tutorial completion receipt on both branches', 'guide and notification entries work after offline reload', 'district-11 city foundation UI and no staffing controls', 'population-linked RP reserve limit', 'separate saves and locks', 'main has no time skip', 'develop only advances its own world', 'cache namespaces coexist', 'no hidden precache files', 'both reload offline concurrently'], caches: allCaches };
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
