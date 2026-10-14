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
    const externalRequests = [];
    page.on('pageerror', error => errors.push(String(error)));
    page.on('request', request => {
      if (request.url().startsWith('http')) {
        const origin = new URL(request.url()).origin;
        origins.add(origin);
        if (origin !== new URL(url).origin) externalRequests.push(request.url());
      }
    });
    const snapshot = () => page.evaluate(storageKey => {
      const bundle = JSON.parse(localStorage.getItem(storageKey));
      return JSON.parse(JSON.parse(bundle.primary).payload);
    }, key);
    const ready = async target => {
      await target.getByRole('button', { name: '開発 +5分' }).waitFor({ timeout: 60000 });
      await target.waitForTimeout(400);
    };
    const reach = async (locator, description) => {
      for (let n = 0; n < 16; n++) {
        const { width, height } = page.viewportSize();
        const scrollX = width - 150;
        const dock = await page.getByRole('button', { name: '都市開発', exact: true }).boundingBox();
        const contentBottom = dock ? dock.y : height - 20;
        const scrollY = Math.max(110, contentBottom - 145);
        if (await locator.count()) {
          const box = await locator.boundingBox();
          if (box && box.y > 55 && box.y + box.height < contentBottom - 2) {
            await locator.click();
            await page.waitForTimeout(250);
            return;
          }
          if (box && box.y < 55) {
            await page.mouse.move(scrollX, scrollY);
            await page.mouse.wheel(0, -Math.min(350, height / 2));
            await page.waitForTimeout(200);
            continue;
          }
        }
        await page.mouse.move(scrollX, scrollY);
        await page.mouse.wheel(0, Math.min(300, height / 2));
        await page.waitForTimeout(200);
      }
      throw new Error(`Cannot reach control: ${description}`);
    };
    const click = name => reach(
      page.getByRole('button', { name, exact: true }), name,
    );
    const compareInvestment = async screenshotName => {
      const beforeComparison = await snapshot();
      await click('比較に保存');
      await page.getByRole('button', { name: '惑星マップ', exact: true }).click();
      await reach(page.getByRole('button', { name: /^高原科学都市 / }).last(), '高原科学都市');
      await page.getByRole('button', { name: '都市開発', exact: true }).click();
      await click('候補を比較');
      await page.getByRole('button', { name: '比較を閉じる', exact: true }).waitFor();
      assert.equal(await page.getByText('住宅地区 Lv.1 → 2', { exact: true }).count(), 1);
      assert.equal(await page.getByText('住宅地区 新設 Lv.1', { exact: true }).count(), 1);
      const { width, height } = page.viewportSize();
      await page.screenshot({ path: path.join(output, `${screenshotName}.png`) });
      // The entire comparison scrolls while its close action stays reachable.
      await page.mouse.move(width / 2, height - 80);
      await page.mouse.wheel(0, 600);
      await page.waitForTimeout(250);
      const close = page.getByRole('button', { name: '比較を閉じる', exact: true });
      const closeBox = await close.boundingBox();
      assert.ok(closeBox && closeBox.y >= 0 && closeBox.y + closeBox.height <= height);
      await close.click();
      await page.waitForTimeout(250);
      assert.equal(await page.getByRole('button', { name: '比較を閉じる', exact: true }).count(), 0);
      const afterComparison = await snapshot();
      assert.deepEqual(afterComparison.districts, beforeComparison.districts);
      assert.deepEqual(afterComparison.plans.map(p => p.id), beforeComparison.plans.map(p => p.id));
    };
    const inspectForecast = async screenshotName => {
      await page.getByRole('button', { name: '設備・進行', exact: true }).click();
      await page.getByRole('button', { name: '稼働状況', exact: true }).click();
      const beforeForecast = await snapshot();
      // Equipment rows can leave this lazy list scrolled below its header.
      const viewport = page.viewportSize();
      await page.mouse.move(viewport.width / 2, viewport.height - 100);
      await page.mouse.wheel(0, -5000);
      await page.waitForTimeout(300);
      await click('予約の見通し');
      await page.getByRole('button', { name: '見通しを閉じる', exact: true }).waitFor();
      await page.getByRole('checkbox', { name: '8時間後', exact: true }).click();
      await page.getByRole('button', { name: '最新状態で再計算', exact: true }).click();
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(output, `${screenshotName}.png`) });
      const { width, height } = page.viewportSize();
      await page.mouse.move(width / 2, height - 85);
      await page.mouse.wheel(0, 650);
      await page.waitForTimeout(250);
      await page.screenshot({ path: path.join(output, `${screenshotName}-equipment.png`) });
      const close = page.getByRole('button', { name: '見通しを閉じる', exact: true });
      const box = await close.boundingBox();
      assert.ok(box && box.y >= 0 && box.y + box.height <= height);
      await close.click();
      const afterForecast = await snapshot();
      // Real-time ticks continue, but projection must never materialize its future.
      assert.deepEqual(afterForecast.districts, beforeForecast.districts);
      assert.deepEqual(afterForecast.research, beforeForecast.research);
      assert.deepEqual(afterForecast.claimedRewards, beforeForecast.claimedRewards);
      assert.deepEqual(afterForecast.plans.map(p => p.id), beforeForecast.plans.map(p => p.id));
      assert.ok(afterForecast.simulatedMs - beforeForecast.simulatedMs < 60000);
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
    await inspectForecast('forecast-web-summary');
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
    await page.waitForTimeout(800);
    // Use real screen coordinates on the projected ground at the corner,
    // center and ridge; the resulting inspector must refer to that same plot.
    for (const number of [1, 5, 13]) {
      const target = page.getByRole('button', { name: new RegExp(`^アルカディアの区画${number}、`) });
      const bounds = await target.boundingBox();
      assert.ok(bounds, `Projected plot ${number} is visible`);
      await page.mouse.click(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
      await page.getByText(new RegExp(`^区画 ${number}  ·`)).waitFor();
    }
    await page.screenshot({ path: path.join(output, 'terrain-web-before.png') });
    await click('この区画に建設を予約');
    await page.waitForTimeout(500);
    await page.screenshot({ path: path.join(output, 'terrain-web-construction.png') });
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
    await page.screenshot({ path: path.join(output, 'terrain-web-completed.png') });
    console.log('CHECK OK: research tree, reservations, reorder, reload, city plot habitation');

    // Grow the first Earth city through the UI, then compare its upgrade with
    // a new city's first district. No test fixture or save mutation is used.
    await page.getByRole('button', { name: '惑星マップ', exact: true }).click();
    await page.getByRole('checkbox', { name: '地球', exact: true }).click();
    await page.getByRole('button', { name: '都市開発', exact: true }).click();
    await page.getByText(/^候補地 · 完成 0\/25区画/).waitFor();
    await click('この区画に建設を予約');
    await page.getByRole('button', { name: '設備・進行', exact: true }).click();
    await page.getByRole('button', { name: '稼働状況', exact: true }).click();
    await page.getByRole('button', { name: '住宅地区を建設を前へ', exact: true }).click();
    for (let n = 0; n < 2; n++) {
      await page.getByRole('button', { name: '開発 +5分', exact: true }).click();
      await page.waitForTimeout(350);
    }
    assert.ok((await snapshot()).districts.some(d => d.cityId === 'earth_delta' && d.plotIndex === 12));
    await page.getByRole('button', { name: '都市開発', exact: true }).click();
    await page.getByText(/^拠点 · 完成 1\/25区画 · 総Lv\.1/).waitFor();
    await compareInvestment('investment-web-comparison');
    console.log('CHECK OK: city growth and live upgrade/new-city comparison');

    // Research is independently playable while the factory earns funds.
    await page.getByRole('button', { name: '研究ツリー', exact: true }).click();
    await page.getByRole('button', { name: '全体表示', exact: true }).click();
    await page.getByRole('button', { name: /^都市基盤の計画、/ }).click();
    await click('都市基盤の計画を予約');
    for (let n = 0; n < 2; n++) {
      await page.getByRole('button', { name: '開発 +5分', exact: true }).click();
      await page.waitForTimeout(250);
    }
    await page.getByRole('button', { name: '研究ツリー', exact: true }).click();
    await page.getByRole('button', { name: '全体表示', exact: true }).click();
    await page.getByRole('button', { name: /^工程設計、/ }).click();
    await click('工程設計を予約');
    const parallel = await snapshot();
    assert.equal(parallel.plans.find(p => p.taskId === 'process_design').status, 'running');
    assert.equal(parallel.plans.find(p => p.taskId === 'factory_contract').status, 'running');
    await page.getByRole('button', { name: '開発 +5分', exact: true }).click();
    await page.waitForTimeout(300);
    assert.ok((await snapshot()).research.includes('process_design'));
    await page.getByRole('button', { name: '機関運営', exact: true }).click();
    await page.getByRole('button', { name: '研究者を1人減らす', exact: true }).click();
    await click('人員配分を確定');
    assert.equal((await snapshot()).researchers, 5);
    await page.getByRole('button', { name: '提携・支援', exact: true }).click();
    await click('都市技術の共同研究：開発資金を受けるを選ぶ');
    assert.equal((await snapshot()).partnershipChoices.research_exchange, 'funding');
    await page.screenshot({ path: path.join(output, 'agency-web-partnerships.png') });
    await page.getByRole('button', { name: '人員配分', exact: true }).click();
    await click('専門職の育成を予約');
    await page.getByRole('button', { name: '開発 +5分', exact: true }).click();
    await page.waitForTimeout(300);
    const agencySaved = await snapshot();
    assert.equal(agencySaved.specialistCount, 14);
    assert.equal(agencySaved.researchers, 5);
    await page.getByRole('button', { name: '機関運営', exact: true }).click();
    await page.screenshot({ path: path.join(output, 'agency-web-overview.png') });
    console.log('CHECK OK: parallel applied research, one-time partnership, staffing and training');

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
    assert.deepEqual((await snapshot()).claimedRewards, agencySaved.claimedRewards);
    assert.deepEqual((await snapshot()).partnershipChoices, agencySaved.partnershipChoices);
    assert.equal((await snapshot()).specialistCount, 14);
    assert.equal((await snapshot()).researchers, 5);
    assert.equal((await snapshot()).marsResidents, 24);

    // A complete cold reload without network must use local assets and saves.
    await context.setOffline(true);
    await page.reload();
    await ready(page);
    const offline = await snapshot();
    assert.equal(offline.worldId, inhabited.worldId);
    assert.equal(offline.marsResidents, 24);
    assert.deepEqual(offline.partnershipChoices, agencySaved.partnershipChoices);
    assert.equal(offline.specialistCount, 14);
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
    const action = await page.getByRole('button', { name: 'この地区を強化する', exact: true }).boundingBox();
    assert.ok(action && action.y > 100 && action.y + action.height < 370, 'district action remains visible in landscape');
    await page.screenshot({ path: path.join(output, 'strategy-web-small-city.png') });
    await compareInvestment('investment-web-small-comparison');
    await inspectForecast('forecast-web-small-summary');
    await page.getByRole('button', { name: '研究ツリー', exact: true }).click();
    await page.getByRole('button', { name: '全体表示', exact: true }).click();
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(output, 'strategy-web-small-research.png') });
    await page.getByRole('button', { name: '機関運営', exact: true }).click();
    await page.getByRole('button', { name: '人員配分', exact: true }).click();
    await page.screenshot({ path: path.join(output, 'agency-web-small-overview.png') });
    await page.getByRole('button', { name: '提携・支援', exact: true }).click();
    await page.mouse.move(700, 260);
    await page.mouse.wheel(0, 450);
    await page.waitForTimeout(250);
    await page.screenshot({ path: path.join(output, 'agency-web-small-partnerships.png') });
    console.log('CHECK OK: small landscape, pinned construction action, whole research map');
    assert.deepEqual(errors, []);
    assert.deepEqual([...origins], [new URL(url).origin], `Unexpected external resources: ${externalRequests.join(', ')}`);
    result = { result: 'PASS', checks: ['parallel applied research', 'one-time partnership persists offline', 'staff allocation and training', 'agency on small landscape', '3D startup', 'small landscape and whole research map', 'city stage growth', 'live investment comparison and small-screen close', 'read-only eight-hour forecast and small-screen close', 'equipment reorder', 'paid iteration preserved', 'reload keeps order', 'research tree/manufacture/transport/district habitation', 'multi-tab lock', 'reward persistence', 'offline cold reload', 'no external resource hosts'], origins: [...origins] };
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
