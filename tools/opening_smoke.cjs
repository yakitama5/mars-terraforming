// Uses an isolated browser context; never reads the user's normal save.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { completeFirstRun } = require('./complete_first_run.cjs');
const url = process.env.MARS_BASE_URL || 'http://127.0.0.1:8765/';
const key = process.env.MARS_SAVE_KEY || 'mars_terraforming.save.development';
const output = process.env.MARS_SCREENSHOT_DIR || path.resolve(__dirname, '../docs/screenshots');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN,
    headless: true,
    args: ['--disable-updater-scheduler'],
  });
  let context;
  let page;
  let result;
  try {
    fs.mkdirSync(output, { recursive: true });
    context = await browser.newContext({ viewport: { width: 844, height: 390 } });
    page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    const snapshot = () => page.evaluate(storageKey => {
      const bundle = JSON.parse(localStorage.getItem(storageKey));
      return JSON.parse(JSON.parse(bundle.primary).payload);
    }, key);
    const button = name => page.getByRole('button', { name, exact: true });
    const enterName = async (label, value) => {
      const field = page.getByRole('textbox', { name: label });
      await field.click();
      // Flutter attaches its active editor after the semantics field gains focus.
      await page.waitForTimeout(200);
      await page.keyboard.press('Meta+A');
      await page.keyboard.insertText(value);
      await page.waitForTimeout(200);
      assert.equal(await field.inputValue(), value);
    };
    const capture = async name => {
      await page.waitForTimeout(400);
      await page.screenshot({ path: path.join(output, `${name}.png`) });
    };
    await page.goto(url);
    await button('物語へ').waitFor({ timeout: 60000 });
    const filmInitial = await snapshot();
    for (const [chapter, label] of ['都市開発', 'ロケット打ち上げ', '月面基地', '火星探査', '火星移住'].entries()) {
      await page.getByText(new RegExp(`^${chapter + 1}\\s+/\\s+${label}$`)).waitFor({ timeout: 30000 });
      await page.waitForTimeout(3000);
      await capture(`cinematic-web-${chapter + 1}`);
    }
    await button('物語をスキップ').waitFor({ timeout: 30000 });
    const filmEnd = await snapshot();
    assert.equal(filmEnd.simulatedMs, filmInitial.simulatedMs);
    assert.equal(filmEnd.moneyUnits, filmInitial.moneyUnits);
    await page.waitForTimeout(2500);
    await capture('blue-web-opening');
    const initial = await snapshot();
    await page.waitForTimeout(6000);
    const reading = await snapshot();
    assert.equal(reading.simulatedMs, initial.simulatedMs);
    assert.equal(reading.moneyUnits, initial.moneyUnits);
    await button('次へ').click();
    await button('次へ').click();
    await button('計画に名前をつける').click();
    await enterName(/地球の最初の街/, '群青市');
    await enterName(/輸送ロケット/, 'あおぞら');
    await enterName(/火星の最初の街/, '朝凪基地');
    await capture('blue-web-naming');
    await button('火星開発を始める').click();
    await completeFirstRun(page);
    await button('都市開発').waitFor();
    await page.waitForTimeout(300);
    const started = await snapshot();
    assert.equal(started.openingSeen, true);
    assert.equal(started.firstRunTutorial, 'completed');
    assert.ok(started.districts.some(d => d.cityId === 'earth_delta' && d.plotIndex === 1 && d.districtId === 'housing'));
    assert.ok(started.plans.some(p => p.taskId === 'life_support'));
    assert.equal(started.missionIdentity.cityNames.earth_delta, '群青市');
    assert.equal(started.missionIdentity.cityNames.mars_arcadia, '朝凪基地');
    assert.equal(started.missionIdentity.rocketName, 'あおぞら');
    await capture('blue-web-map');
    await button('研究ツリー').click();
    await capture('blue-web-research-readable');
    await button('全体表示').click();
    await capture('blue-web-research-overview');
    await button('ガイド').click();
    await button('手引き').or(button('6工程の手引き')).first().click();
    await button('6工程').waitFor();
    await page.waitForTimeout(2500);
    await capture('cinematic-web-guide');
    await button('6工程').click();
    await capture('cinematic-web-roadmap');
    await button('閉じて開発を続ける').click();
    const names = button('都市・ロケットの名前');
    // Guidance scrolls on a short landscape display, while its footer stays put.
    for (let attempt = 0; attempt < 8; attempt++) {
      const box = await names.boundingBox();
      if (box && box.y > 40 && box.y + box.height < 330) break;
      await page.mouse.move(520, 230);
      await page.mouse.wheel(0, 160);
      await page.waitForTimeout(150);
    }
    await names.click();
    await enterName(/輸送ロケット/, 'あおぞら二号');
    await button('名前を保存').click();
    await page.waitForTimeout(300);
    await button('閉じる').and(page.locator('[tabindex="0"]')).click();
    const renamed = await snapshot();
    assert.equal(renamed.missionIdentity.rocketName, 'あおぞら二号');
    assert.equal(renamed.worldId, started.worldId);
    // 自由プレイでは研究の残り時間が進む。改名で予約自体を増減しない。
    assert.deepEqual(renamed.plans.map(p => [p.id, p.taskId]), started.plans.map(p => [p.id, p.taskId]));
    await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 60000 });
    await context.setOffline(true);
    await page.reload({ waitUntil: 'domcontentloaded' });
    assert.equal(await completeFirstRun(page), false);
    await button('都市開発').waitFor({ timeout: 60000 });
    assert.equal(await button('物語をスキップ').count(), 0);
    const resumed = await snapshot();
    assert.deepEqual(resumed.missionIdentity, renamed.missionIdentity);
    assert.equal(resumed.worldId, renamed.worldId);
    await page.setViewportSize({ width: 568, height: 320 });
    await button('都市開発').click();
    await capture('blue-web-small-offline');
    assert.equal(errors.length, 0, errors.join('\n'));
    result = { result: 'PASS', checks: [
      'five rendered cinematic chapters before dialogue on landscape', 'reading does not spend starting funds',
      'first housing and research tutorial completes through UI and stays completed offline',
      'three player names save and can be edited', 'readable research and whole-tree overview',
      'names and world persist through offline reload', '568x320 navigation after reload',
    ] };
  } catch (error) {
    if (page) await page.screenshot({ path: path.join(output, 'blue-web-failure.png') }).catch(() => {});
    throw error;
  } finally {
    if (context) {
      await context.setOffline(false).catch(() => {});
      await context.close();
    }
    await browser.close();
  }
  console.log(JSON.stringify(result, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
