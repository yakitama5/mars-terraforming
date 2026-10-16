// Dedicated context only: real sound, new-world actions, and an offline restart.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const url = process.env.MARS_BASE_URL || 'http://127.0.0.1:8765/';
const key = process.env.MARS_SAVE_KEY || 'mars_terraforming.save.development';
const output = process.env.MARS_SCREENSHOT_DIR || path.resolve(__dirname, '../docs/screenshots');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN, headless: true,
    args: ['--disable-updater-scheduler', '--autoplay-policy=document-user-activation-required'],
  });
  try {
    fs.mkdirSync(output, { recursive: true });
    const context = await browser.newContext({ viewport: { width: 844, height: 390 } });
    await context.addInitScript(() => {
      window.__lunaAudio = [];
      const play = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () {
        if (!window.__lunaAudio.includes(this)) window.__lunaAudio.push(this);
        return play.apply(this, arguments);
      };
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    const button = name => page.getByRole('button', { name, exact: true });
    const snapshot = () => page.evaluate(storageKey => {
      const bundle = JSON.parse(localStorage.getItem(storageKey));
      return JSON.parse(JSON.parse(bundle.primary).payload);
    }, key);
    const audio = () => page.evaluate(() => window.__lunaAudio.map(a => ({
      paused: a.paused, time: a.currentTime, duration: a.duration,
    })));
    const shot = async name => {
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(output, `${name}.png`) });
    };
    await page.goto(url);
    await button('OPを一時停止').waitFor({ timeout: 60000 });
    await page.waitForTimeout(1500);
    const retry = button('音楽つきで最初から見る');
    const retriedAutoplay = await retry.count() > 0;
    if (retriedAutoplay) await retry.last().click();
    await page.waitForFunction(() => window.__lunaAudio.some(a => !a.paused && a.currentTime > .3), null, { timeout: 12000 });
    const active = (await audio()).find(a => !a.paused);
    assert.ok(Math.abs(active.duration - 40) < .1);
    await button('OPを一時停止').click();
    await page.waitForTimeout(200);
    const paused = (await audio())[0];
    assert.equal(paused.paused, true);
    await page.waitForTimeout(800);
    assert.ok(Math.abs((await audio())[0].time - paused.time) < .1);
    await page.mouse.move(400, 150);
    await page.waitForTimeout(500);
    await button('OPを再生').click();
    await page.waitForFunction(() => window.__lunaAudio.some(a => !a.paused), null, { timeout: 10000 });
    const resumed = (await audio())[0].time;
    await page.waitForTimeout(700);
    assert.ok((await audio())[0].time > resumed + .3);
    await button('音を消す').click();
    await page.waitForTimeout(200);
    assert.equal((await audio())[0].paused, true);
    await page.mouse.move(400, 150);
    await page.waitForTimeout(500);
    await button('音を出す').click();
    await page.waitForTimeout(500);
    assert.equal((await audio())[0].paused, false);
    await button('物語へ').click();
    await page.waitForTimeout(600);
    assert.ok((await audio()).every(a => a.paused));
    await button('物語をスキップ').click();
    await button('名前は後で決める').click();
    await button('住宅地区').waitFor();
    const initial = await snapshot();
    assert.equal(initial.firstRunTutorial, 'placeHousing');
    assert.equal(await button('設備・進行').count(), 0);
    await shot('luna-web-tutorial-start');
    await page.setViewportSize({ width: 568, height: 320 });
    await shot('luna-web-tutorial-small');
    await button('住宅地区').click();
    await button('区画 2（海岸）を選択').click();
    await shot('luna-web-tutorial-placement');
    await button('建設を予約').click();
    await button('ルナに完成を頼む').waitFor();
    const queued = await snapshot();
    assert.equal(queued.firstRunTutorial, 'finishConstruction');
    assert.equal(queued.districts.length, 0);
    assert.ok(queued.moneyUnits < initial.moneyUnits);
    // The current staged order survives a genuine reload before the reward.
    await page.reload();
    await button('ルナに完成を頼む').waitFor({ timeout: 60000 });
    await button('ルナに完成を頼む').click();
    await button('研究へ進む').waitFor();
    const built = await snapshot();
    assert.equal(built.firstRunTutorial, 'income');
    assert.equal(built.districts.length, 1);
    assert.equal(built.simulatedMs, initial.simulatedMs);
    assert.equal(built.moneyUnits, queued.moneyUnits);
    await shot('luna-web-tutorial-built');
    await button('研究へ進む').click();
    await shot('luna-web-tutorial-research');
    await button('研究を予約する').click();
    await button('ガイドと開発を続ける').click();
    await button('閉じる').and(page.locator('[tabindex="0"]')).click();
    await button('設備・進行').waitFor();
    const completed = await snapshot();
    assert.equal(completed.firstRunTutorial, 'completed');
    assert.equal(completed.districts.length, 1);
    assert.equal(completed.plans.filter(p => p.taskId === 'life_support').length, 1);
    await page.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 30000 });
    const asset = await page.evaluate(async () => {
      const response = await caches.match(new URL('assets/assets/audio/opening_music.wav', document.baseURI));
      return response && (await response.arrayBuffer()).byteLength;
    });
    assert.ok(asset > 7000000, 'Soundtrack is precached for offline playback');
    await context.setOffline(true);
    await page.reload();
    await button('設備・進行').waitFor({ timeout: 60000 });
    const restored = await snapshot();
    assert.equal(restored.firstRunTutorial, 'completed');
    assert.equal(restored.worldId, completed.worldId);
    assert.equal(restored.districts.length, 1);
    await shot('luna-web-offline');
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ result: 'PASS', retriedAutoplay, checks: [
      'actual 40-second WAV playback (autoplay retry is reported separately)', 'pause/resume/mute/skip audio lifecycle',
      '844 and 568 landscape', 'coastal housing through actual controls',
      'restart before Luna completion', 'one paid instant completion without elapsed time',
      'research and free-play handoff', 'offline sound cache and world restart',
    ] }, null, 2));
    await context.close();
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
