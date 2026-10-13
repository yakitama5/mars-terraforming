// Requires an installed Playwright module and Chrome; no user profile is opened.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const url = process.env.MARS_BASE_URL || 'http://127.0.0.1:8765/';
const output = process.env.MARS_SCREENSHOT_DIR || path.resolve(__dirname, '../docs/screenshots');
const key = process.env.MARS_SAVE_KEY || 'mars_terraforming.save.development';

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN,
    headless: true,
    // Keep updater descendants from inheriting the browser's stdio pipes.
    args: ['--disable-updater-scheduler'],
  });
  let context;
  let page;
  let result;
  try {
    context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    page = await context.newPage();
    const errors = [];
    const origins = new Set();
    page.on('pageerror', error => errors.push(String(error)));
    page.on('request', request => {
      if (request.url().startsWith('http')) origins.add(new URL(request.url()).origin);
    });
    const snapshot = () => page.evaluate(storageKey => {
      const bundle = JSON.parse(localStorage.getItem(storageKey));
      return JSON.parse(JSON.parse(bundle.primary).payload);
    }, key);
    const ready = async target => {
      await target.getByRole('button', { name: '開発 +5分' }).waitFor({ timeout: 60000 });
      await target.waitForTimeout(400);
    };
    const click = async name => {
      const locator = page.getByRole('button', { name, exact: true });
      for (let n = 0; n < 12; n++) {
        if (await locator.count()) {
          const box = await locator.boundingBox();
          if (box && box.y > 100 && box.y + box.height < 970) {
            await locator.click();
            await page.waitForTimeout(250);
            return;
          }
          if (box && box.y < 100) {
            await page.mouse.move(1100, 500);
            await page.mouse.wheel(0, -450);
            await page.waitForTimeout(200);
            continue;
          }
        }
        await page.mouse.move(1100, 700);
        await page.mouse.wheel(0, 400);
        await page.waitForTimeout(200);
      }
      throw new Error(`Cannot reach control: ${name}`);
    };
    const reserve = async (name, repeat) => {
      await page.getByRole('button', { name: '設備・進行', exact: true }).click();
      const section = name.includes('輸送') || name.includes('衛星') ? '輸送・居住' : '製造・受注';
      await page.getByRole('button', { name: section, exact: true }).click();
      await page.waitForTimeout(200);
      await click(`${name}を予約`);
      if (repeat) {
        await page.getByText(repeat, { exact: true }).click();
        await page.waitForTimeout(300);
      }
    };
    await page.goto(url);
    await ready(page);
    await page.waitForFunction(() => navigator.serviceWorker.controller !== null);
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForTimeout(1500);
    fs.mkdirSync(output, { recursive: true });
    await page.screenshot({ path: path.join(output, 'strategy-web-earth.png') });
    await reserve('外部受注・精密機器', '無期限・分岐まで');
    await page.getByRole('button', { name: '研究ツリー', exact: true }).click();
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(output, 'strategy-web-research.png') });
    await click('生命維持の実証を予約');
    await reserve('居住キット製造', '1回');
    await reserve('火星へ輸送', '1回');
    await page.getByRole('button', { name: '設備・進行', exact: true }).click();
    await page.waitForTimeout(300);
    const before = await snapshot();
    const contract = before.plans.find(plan => plan.taskId === 'factory_contract');
    assert.equal(contract.status, 'running');
    await page.getByRole('button', { name: '居住キット製造を前へ', exact: true }).click();
    await page.waitForTimeout(300);
    const reordered = await snapshot();
    assert.deepEqual(reordered.plans.filter(plan => ['factory_contract', 'habitat_kit'].includes(plan.taskId)).map(plan => plan.taskId), ['habitat_kit', 'factory_contract']);
    assert.equal(reordered.plans.find(plan => plan.id === contract.id).status, 'running');
    assert.equal(reordered.plans.find(plan => plan.id === contract.id).completedRuns, 0);
    await page.screenshot({ path: path.join(output, 'strategy-web-equipment.png') });
    await page.reload();
    await ready(page);
    assert.equal((await snapshot()).worldId, before.worldId);
    assert.deepEqual((await snapshot()).plans.filter(plan => ['factory_contract', 'habitat_kit'].includes(plan.taskId)).map(plan => plan.taskId), ['habitat_kit', 'factory_contract']);
    for (let n = 0; n < 3; n++) {
      await page.getByRole('button', { name: '開発 +5分', exact: true }).click();
      await page.waitForTimeout(350);
    }
    const arrived = await snapshot();
    assert.ok(arrived.achievements.includes('first_landing'));
    assert.equal(arrived.marsHabitats, 0);
    await page.getByRole('button', { name: '設備・進行', exact: true }).click();
    await page.getByRole('button', { name: '輸送・居住', exact: true }).click();
    await click('ドーム居住');
    await page.getByRole('button', { name: '惑星マップ', exact: true }).click();
    await page.getByRole('checkbox', { name: '火星', exact: true }).click();
    await page.waitForTimeout(700);
    await page.screenshot({ path: path.join(output, 'strategy-web-mars.png') });
    await page.getByRole('button', { name: '都市開発', exact: true }).click();
    await click('この区画に建設を予約');
    const construction = (await snapshot()).plans.find(plan => plan.taskId === 'district_mars_habitat');
    assert.equal(construction.cityId, 'mars_arcadia');
    assert.equal(construction.plotIndex, 12);
    await page.getByRole('button', { name: '開発用の時間送り', exact: true }).click();
    await page.getByRole('menuitem', { name: '開発 +1時間', exact: true }).click();
    await page.waitForTimeout(700);
    const inhabited = await snapshot();
    assert.equal(inhabited.marsHabitats, 1);
    assert.equal(inhabited.marsResidents, 24);
    assert.equal(inhabited.districts.find(d => d.cityId === 'mars_arcadia' && d.plotIndex === 12).districtId, 'mars_habitat');
    await page.screenshot({ path: path.join(output, 'strategy-web-city.png') });
    console.log('CHECK OK: research tree, reservations, reorder, reload, city plot habitation');

    // The second tab must stop before loading or advancing the shared world.
    const second = await context.newPage();
    await second.goto(url);
    await second.locator('flt-semantics-host').getByText(/別のタブで使用中/).waitFor({ timeout: 60000 });
    await second.screenshot({ path: path.join(output, 'web-second-tab.png') });
    assert.equal(await second.getByRole('button', { name: '開発 +5分' }).count(), 0);
    await second.close();
    console.log('CHECK OK: second tab safely stopped');
    await page.reload();
    await ready(page);
    assert.deepEqual((await snapshot()).claimedRewards, inhabited.claimedRewards);
    assert.equal((await snapshot()).marsResidents, 24);

    // A complete cold reload without network must use local assets and saves.
    await context.setOffline(true);
    await page.reload();
    await ready(page);
    const offline = await snapshot();
    assert.equal(offline.worldId, inhabited.worldId);
    assert.equal(offline.marsResidents, 24);
    await page.getByRole('button', { name: '設備・進行', exact: true }).click();
    await page.waitForTimeout(300);
    assert.ok(await page.getByRole('button', { name: '都市開発', exact: true }).isVisible());
    await context.setOffline(false);
    console.log('CHECK OK: offline reload');
    // Inspect real GPU/layout at an iPhone-sized landscape viewport too.
    await page.setViewportSize({ width: 844, height: 390 });
    await page.getByRole('button', { name: '惑星マップ', exact: true }).click();
    await page.getByRole('checkbox', { name: '地球', exact: true }).click();
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(output, 'strategy-web-small-earth.png') });
    await page.getByRole('button', { name: '都市開発', exact: true }).click();
    await page.waitForTimeout(300);
    const action = await page.getByRole('button', { name: 'この区画に建設を予約', exact: true }).boundingBox();
    assert.ok(action && action.y > 100 && action.y + action.height < 370, 'district action remains visible in landscape');
    await page.screenshot({ path: path.join(output, 'strategy-web-small-city.png') });
    await page.getByRole('button', { name: '研究ツリー', exact: true }).click();
    await page.getByRole('button', { name: '全体表示', exact: true }).click();
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(output, 'strategy-web-small-research.png') });
    console.log('CHECK OK: small landscape, pinned construction action, whole research map');
    assert.deepEqual(errors, []);
    assert.deepEqual([...origins], [new URL(url).origin]);
    result = { result: 'PASS', checks: ['3D startup', 'small landscape and whole research map', 'equipment reorder', 'paid iteration preserved', 'reload keeps order', 'research tree/manufacture/transport/district habitation', 'multi-tab lock', 'reward persistence', 'offline cold reload', 'no external resource hosts'], origins: [...origins] };
  } catch (error) {
    if (page) {
      await page.screenshot({ path: path.join(output, 'web-failure.png') }).catch(() => {});
      console.error('PAGE', await page.locator('body').innerText().catch(() => 'unavailable'));
    }
    throw error;
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
