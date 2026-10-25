// 独立したChromeコンテキストだけを使い、通常のユーザーセーブを触らない。
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const url = process.env.MARS_BASE_URL || 'http://127.0.0.1:8765/';
const output = process.env.MARS_SCREENSHOT_DIR || path.resolve(__dirname, '../docs/screenshots');
const key = process.env.MARS_SAVE_KEY || 'mars_terraforming.save.development';

(async () => {
  let browser, context;
  let result;
  try {
    browser = await chromium.launch({
      executablePath: process.env.CHROME_BIN,
      headless: true,
      args: ['--disable-updater-scheduler'],
    });
    context = await browser.newContext({ viewport: { width: 1440, height: 810 } });
    const page = await context.newPage();
    const errors = [], external = [];
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => {
      if (/pipeline failed|shader.*(?:error|failed)|skipping a draw|GL_INVALID|WebGL.*(?:error|failed)/i.test(message.text())) errors.push(message.text());
    });
    page.on('request', request => {
      if (request.url().startsWith('http') && new URL(request.url()).origin !== new URL(url).origin) external.push(request.url());
    });
    fs.mkdirSync(output, { recursive: true });
    const button = name => page.getByRole('button', { name, exact: true });
    const title = () => button('タップまたはクリックしてスタート');
    const snapshot = () => page.evaluate(storageKey => {
      const bundle = JSON.parse(localStorage.getItem(storageKey));
      return JSON.parse(JSON.parse(bundle.primary).payload);
    }, key);
    const capture = async name => page.screenshot({ path: path.join(output, `${name}.png`) });
    await page.goto(url);
    await title().waitFor({ timeout: 60000 });
    await page.waitForTimeout(2500);
    const initial = await snapshot();
    const early = await capture('title-web-pristine');
    await page.waitForTimeout(7000);
    const motion = await capture('title-web-passage');
    assert.notDeepEqual(early, motion, '宇宙は待機中も動く');
    const waiting = await snapshot();
    assert.equal(waiting.moneyUnits, initial.moneyUnits);
    assert.equal(waiting.simulatedMs, initial.simulatedMs);
    assert.equal(waiting.openingStarted, false);

    await page.setViewportSize({ width: 568, height: 320 });
    await page.waitForTimeout(500);
    await capture('title-web-small');
    await page.setViewportSize({ width: 844, height: 390 });
    await title().click();
    await button('物語へ').waitFor({ timeout: 60000 });
    await button('物語へ').click();
    await button('物語をスキップ').click({ timeout: 30000 });
    await button('名前は後で決める').click();
    await button('住宅地区').waitFor({ timeout: 60000 });
    const afterOpening = await snapshot();
    assert.equal(afterOpening.openingSeen, true);
    assert.equal(afterOpening.firstRunTutorial, 'placeHousing');

    // 既存世界のタイトルを独立して確認するため、初回案内済みのテストfixtureを置く。
    // アプリを離れてロックを解放してから、検証context内の保存だけを一度置換する。
    await page.goto('about:blank');
    const payload = JSON.stringify({ ...afterOpening, firstRunTutorial: 'completed' });
    const envelope = JSON.stringify({ schemaVersion: 1, generation: 1, payload,
      checksum: createHash('sha256').update(`1:1:${payload}`).digest('hex') });
    const fixture = JSON.stringify({ formatVersion: 1, primary: envelope, previous: null });
    await page.addInitScript(({ storageKey, value }) => {
      if (!localStorage.getItem('mars-title-fixture-installed')) {
        localStorage.setItem(storageKey, value);
        localStorage.setItem('mars-title-fixture-installed', 'true');
      }
    }, { storageKey: key, value: fixture });
    const started = { ...afterOpening, firstRunTutorial: 'completed' };

    await page.goto(url);
    await title().waitFor({ timeout: 60000 });
    assert.equal((await snapshot()).worldId, started.worldId);
    await page.keyboard.press('Enter');
    await button('設備・進行').waitFor({ timeout: 60000 });
    assert.equal(await button('物語へ').count(), 0);

    await page.evaluate(async () => {
      await navigator.serviceWorker.ready;
      const names = await caches.keys();
      if (!names.length) throw new Error('オフライン用キャッシュが準備されていない');
    });
    await context.setOffline(true);
    await page.reload();
    await title().waitFor({ timeout: 60000 });
    await page.waitForTimeout(1500);
    await capture('title-web-offline');
    assert.equal((await snapshot()).worldId, started.worldId);
    await page.keyboard.press('Space');
    await button('設備・進行').waitFor({ timeout: 60000 });
    assert.equal((await snapshot()).worldId, started.worldId);
    assert.deepEqual(errors, []);
    assert.deepEqual(external, []);
    result = 'PASS: WebGLタイトル、大小画面、宇宙の動き、初回資金保護、クリック→OP、再起動→継続、Enter/Space、オフライン、保存維持、外部取得なし';
    await context.setOffline(false);
  } catch (error) {
    process.exitCode = 1;
    console.error(error);
  } finally {
    await context?.close();
    await browser?.close();
  }
  if (result) console.log(result);
})();
