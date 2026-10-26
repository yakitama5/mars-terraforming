// Requires an installed Playwright module and Chrome; no user profile is opened.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { completeFirstRun, firstRunControl } = require('./complete_first_run.cjs');
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
    page.on('console', message => {
      const text = message.text();
      if (/pipeline failed|shader.*(?:error|failed)|skipping a draw|GL_INVALID|WebGL.*(?:error|failed)/i.test(text)) {
        errors.push(text);
        console.error('RENDER ERROR:', text);
      }
    });
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
      const intro = target.getByRole('button', { name: '物語をスキップ', exact: true });
      const game = target.getByRole('button', { name: '設備・進行', exact: true });
      const movie = target.getByRole('button', { name: '物語へ', exact: true });
      const title = target.getByRole('button', { name: 'タップまたはクリックしてスタート', exact: true });
      const playable = movie.or(intro).or(game).or(firstRunControl(target));
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
        await target.getByRole('button', { name: '名前は後で決める', exact: true }).click();
      }
      await completeFirstRun(target);
      await target.getByRole('button', { name: '開発 +5分' }).waitFor({ timeout: 60000 });
      await target.waitForTimeout(400);
    };
    const reach = async (locator, description) => {
      for (let n = 0; n < 16; n++) {
        const { width, height } = page.viewportSize();
        const detailsOpen = await page.getByRole('button', { name: '地図へ戻る', exact: true }).count() > 0;
        const scrollX = detailsOpen ? width / 2 : width - 140;
        const dockControl = page.getByRole('button', { name: '都市開発', exact: true });
        const dock = await dockControl.count() ? await dockControl.boundingBox() : null;
        const contentBottom = dock ? dock.y : height - 20;
        const scrollY = detailsOpen ? height / 2 : Math.max(110, contentBottom - 145);
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
    const ground = async (city, number) => {
      const target = page.getByRole('button', { name: new RegExp(`^${city}の区画${number}、`) });
      await target.waitFor({ state: 'visible' });
      // Flutter's semantic rectangles can lag the newly resized GPU surface.
      // Wait for stable layout before dispatching an actual coordinate tap.
      let bounds, previous, stable = 0;
      for (let attempt = 0; attempt < 30 && stable < 5; attempt++) {
        await page.waitForTimeout(100);
        bounds = await target.boundingBox();
        const signature = bounds && [bounds.x, bounds.y, bounds.width, bounds.height]
          .map(value => value.toFixed(1)).join('/');
        stable = signature && signature === previous ? stable + 1 : 0;
        previous = signature;
      }
      assert.ok(bounds && stable >= 5, `Projected plot ${city}/${number} has stable bounds`);
      await page.mouse.click(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
      await page.getByText(new RegExp(`^区画 ${number}  ·`)).waitFor();
    };
    const chooseFacility = async name => {
      const option = page.getByRole('button', { name: `${name}を選ぶ`, exact: true });
      const change = page.getByRole('button', { name: '建設する施設を選ぶ', exact: true });
      // Flutter publishes semantics after the city navigation frame.
      await option.or(change).first().waitFor();
      if (await option.count() === 0) await click('建設する施設を選ぶ');
      await reach(option, `${name}を選ぶ`);
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
      await page.getByRole('button', { name: /8時間後の設備を詳しく/ }).click();
      await page.waitForTimeout(350);
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
    const advance = async (period = '開発 +1時間') => {
      await page.getByRole('button', { name: '開発用の時間送り', exact: true }).click();
      await page.getByRole('menuitem', { name: period, exact: true }).click();
      await page.waitForTimeout(350);
    };
    const closeDialog = async () => {
      await page.getByRole('button', { name: '閉じる', exact: true })
        .and(page.locator('[tabindex="0"]')).click();
    };
    const energyResearch = async name => {
      await page.getByRole('button', { name: '研究ツリー', exact: true }).click();
      const field = page.getByRole('checkbox', { name: 'エネルギー', exact: true })
        .or(page.getByRole('button', { name: 'エネルギー', exact: true })).first();
      await field.click();
      await page.getByRole('button', { name: '発見した範囲を表示', exact: true }).click();
      await page.getByRole('button', { name: new RegExp(`^${name}、`) }).click();
      await page.getByText(/^必要RP\s+\d[\d,]* RP$/).waitFor();
    };
    const unlock = async (name, id) => {
      await energyResearch(name);
      const points = (await snapshot()).researchPointUnits;
      const button = page.getByRole('button', { name: `${name}を解放`, exact: true });
      assert.ok(await button.isEnabled(), `${name} has its city conditions and RP`);
      await reach(button, `${name}を解放`);
      const saved = await snapshot();
      assert.ok(saved.research.includes(id));
      const plan = saved.plans.find(plan => plan.taskId === id);
      assert.equal(plan.status, 'completed');
      assert.equal(plan.remainingMs, 0);
      assert.equal(plan.iterationDurationMs, 0);
      assert.ok(saved.researchPointUnits < points, 'unlock consumes RP immediately');
    };
    const earn = async () => {
      await reserve('外部受注・精密機器', '3回');
      await advance();
      assert.ok((await snapshot()).plans.filter(plan => plan.taskId === 'factory_contract')
        .every(plan => plan.status === 'completed'));
    };
    fs.mkdirSync(output, { recursive: true });
    await page.goto(url);
    await ready(page);
    await page.waitForFunction(() => navigator.serviceWorker.controller !== null);
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForTimeout(1500);
    const initial = await snapshot();
    assert.equal(initial.contentVersion, 'district-11');
    assert.equal(initial.firstRunTutorial, 'completed');
    assert.ok(initial.research.includes('life_support'));
    assert.ok(initial.districts.some(d => d.cityId === 'earth_delta' && d.plotIndex === 1 && d.districtId === 'housing'));
    await page.screenshot({ path: path.join(output, 'strategy-web-earth.png') });
    await page.getByRole('button', { name: '国力', exact: true }).click();
    await page.getByText('国力と収支', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, 'product-web-resources.png') });
    await closeDialog();
    await page.getByRole('button', { name: 'ガイド', exact: true }).click();
    await page.getByText('開発ガイド・Tips', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, 'guidance-web-guide.png') });
    await closeDialog();
    console.log('CHECK OK: first housing and immediate research completed through the tutorial');

    // Ordinary manufacturing retains its repeat order and its paid current run.
    await reserve('外部受注・精密機器', '3回');
    await reserve('居住キット製造', '1回');
    await page.getByRole('button', { name: '設備・進行', exact: true }).click();
    await page.getByRole('button', { name: '稼働状況', exact: true }).click();
    const before = await snapshot();
    const contract = before.plans.find(plan => plan.taskId === 'factory_contract');
    assert.equal(contract.status, 'running');
    await click('居住キット製造を前へ');
    const reordered = await snapshot();
    assert.deepEqual(reordered.plans.filter(plan => ['factory_contract', 'habitat_kit'].includes(plan.taskId))
      .map(plan => plan.taskId), ['habitat_kit', 'factory_contract']);
    assert.equal(reordered.plans.find(plan => plan.id === contract.id).status, 'running');
    assert.equal(reordered.plans.find(plan => plan.id === contract.id).completedRuns, 0);
    await page.screenshot({ path: path.join(output, 'strategy-web-equipment.png') });
    await page.reload();
    await ready(page);
    assert.equal((await snapshot()).worldId, initial.worldId);
    assert.deepEqual((await snapshot()).plans.filter(plan => ['factory_contract', 'habitat_kit'].includes(plan.taskId))
      .map(plan => plan.taskId), ['habitat_kit', 'factory_contract']);
    await advance();
    let saved = await snapshot();
    assert.equal(saved.plans.find(plan => plan.id === contract.id).completedRuns, 3);
    assert.ok(saved.earthKits >= 1);
    assert.equal(saved.plans.find(plan => plan.taskId === 'habitat_kit').status, 'completed');
    console.log('CHECK OK: manufacturing repeats, reorder, paid run and reload');

    // A newly discovered research remains visible while its city condition is missing.
    await unlock('展開型ソーラーアレイ', 'deployable_solar_arrays');
    await energyResearch('拠点マイクログリッド');
    const cityGate = page.getByRole('button', { name: '拠点マイクログリッドを解放', exact: true });
    assert.ok(await cityGate.isDisabled());
    assert.ok(await page.getByText(/完成した発電地区.*0\/1/).count());
    assert.ok(!(await snapshot()).research.includes('urban_planning'));
    await page.screenshot({ path: path.join(output, 'v11-web-city-research-condition.png') });

    // Fund both quotes first, so the second attempt tests occupied capacity.
    await earn();
    // Build on the map now; another construction cannot reserve the occupied factory.
    await page.getByRole('button', { name: '都市開発', exact: true }).click();
    await chooseFacility('発電地区');
    await ground('デルタ湾岸', 13);
    await click('この区画で建設を開始');
    const solar = (await snapshot()).plans.find(plan => plan.taskId === 'district_solar');
    assert.equal(solar.status, 'running');
    assert.equal(solar.plotIndex, 12);
    await page.screenshot({ path: path.join(output, 'terrain-web-construction.png') });
    await chooseFacility('住宅地区');
    await ground('デルタ湾岸', 8);
    const beforeBlocked = await snapshot();
    await click('この区画で建設を開始');
    const afterBlocked = await snapshot();
    assert.deepEqual(afterBlocked.plans.map(plan => plan.id), beforeBlocked.plans.map(plan => plan.id));
    assert.deepEqual(afterBlocked.districts, beforeBlocked.districts);
    await inspectForecast('forecast-web-summary');
    await advance();
    saved = await snapshot();
    assert.ok(saved.districts.some(d => d.cityId === 'earth_delta' && d.plotIndex === 12 && d.districtId === 'solar'));
    assert.ok(!saved.plans.some(plan => plan.status === 'queued' && /^district_/.test(plan.taskId)));
    await unlock('拠点マイクログリッド', 'urban_planning');
    console.log('CHECK OK: city-specific research gate and immediate unlock after completed construction');

    await earn();
    await page.getByRole('button', { name: '都市開発', exact: true }).click();
    await chooseFacility('住宅地区');
    await ground('デルタ湾岸', 8);
    const beforeHousing = await snapshot();
    await click('この区画で建設を開始');
    const housing = (await snapshot()).plans.find(plan => plan.taskId === 'district_housing' && plan.plotIndex === 7);
    assert.equal(housing.status, 'running');
    await advance();
    saved = await snapshot();
    assert.equal(saved.population, beforeHousing.population + 60);
    assert.ok(saved.districts.some(d => d.cityId === 'earth_delta' && d.plotIndex === 7 && d.districtId === 'housing'));
    await page.getByRole('button', { name: '都市開発', exact: true }).click();
    await chooseFacility('研究地区');
    await ground('デルタ湾岸', 9);
    const beforeCancel = await snapshot();
    await click('配置をやめる');
    const afterCancel = await snapshot();
    assert.deepEqual(afterCancel.districts, beforeCancel.districts);
    assert.deepEqual(afterCancel.plans.map(plan => plan.id), beforeCancel.plans.map(plan => plan.id));
    await page.screenshot({ path: path.join(output, 'terrarium-web-whole.png') });
    console.log('CHECK OK: explicit construction, population growth and placement cancel without mutation');

    // Pause unused departments, then simulate a long absence through the visible dev clock.
    await page.getByRole('button', { name: '設備・進行', exact: true }).click();
    await page.getByRole('button', { name: '稼働状況', exact: true }).click();
    for (const name of ['共用工場', '共用宇宙港']) {
      const toggle = page.getByRole('switch', { name: `${name}の稼働`, exact: true })
        .or(page.getByRole('checkbox', { name: `${name}の稼働`, exact: true })).first();
      await reach(toggle, `${name}の稼働`);
    }
    const knowledge = (await snapshot()).research;
    let capped = await snapshot();
    let elapsedDays = 0;
    const reservesAreFull = state => {
      const population = state.population + state.marsResidents;
      return state.researchPointUnits >= (240 + population * 40) * 6000000 &&
        state.moneyUnits >= (10000 + population * 1000) * 60000;
    };
    while (!reservesAreFull(capped) && elapsedDays < 30) {
      await advance('開発 +1日');
      elapsedDays++;
      capped = await snapshot();
    }
    assert.ok(reservesAreFull(capped), `Both reserves fill within 30 development days; simulated=${elapsedDays}`);
    console.log(`CHECK OK: both reserve limits reached after ${elapsedDays} development days`);
    const population = capped.population + capped.marsResidents;
    assert.equal(capped.researchPointUnits, (240 + population * 40) * 6000000);
    assert.equal(capped.moneyUnits, (10000 + population * 1000) * 60000);
    assert.deepEqual(capped.research, knowledge, 'full reserves never choose new research');
    await advance('開発 +1日');
    assert.equal((await snapshot()).researchPointUnits, capped.researchPointUnits);
    assert.equal((await snapshot()).moneyUnits, capped.moneyUnits);
    await page.getByRole('button', { name: '機関運営', exact: true }).click();
    await page.getByRole('button', { name: '都市基盤', exact: true }).click();
    for (const name of ['研究者を1人増やす', '研究者を1人減らす', '人員配分を確定', '専門職の育成を予約']) {
      assert.equal(await page.getByRole('button', { name, exact: true }).count(), 0);
    }
    await page.screenshot({ path: path.join(output, 'agency-web-overview.png') });
    console.log('CHECK OK: population-linked RP and money limits; no staffing controls');

    await page.getByRole('button', { name: /^通知/ }).click();
    await page.getByText(/^完了通知 · 未読/).waitFor();
    await page.getByRole('button', { name: 'すべて既読にする', exact: true }).click();
    await page.screenshot({ path: path.join(output, 'guidance-web-completions.png') });
    await closeDialog();
    const acknowledged = await snapshot();
    assert.equal(acknowledged.readCompletionNoticeId, acknowledged.nextCompletionNoticeId - 1);
    if (process.env.MARS_VISUAL_STATE) {
      fs.writeFileSync(process.env.MARS_VISUAL_STATE, JSON.stringify({
        key, saved: await page.evaluate(storageKey => localStorage.getItem(storageKey), key),
      }));
    }

    // The second tab must stop before it can advance the same world.
    const second = await context.newPage();
    await second.goto(url);
    await second.locator('flt-semantics-host').getByText(/別のタブで使用中/).waitFor({ timeout: 60000 });
    await second.screenshot({ path: path.join(output, 'web-second-tab.png') });
    assert.equal(await second.getByRole('button', { name: '開発 +5分' }).count(), 0);
    await second.close();
    await page.reload();
    await ready(page);
    saved = await snapshot();
    assert.equal(saved.worldId, initial.worldId);
    assert.deepEqual(saved.research, capped.research);
    assert.deepEqual(saved.claimedRewards, acknowledged.claimedRewards);
    assert.deepEqual(saved.districts, acknowledged.districts);
    assert.equal(saved.readCompletionNoticeId, acknowledged.readCompletionNoticeId);

    // A cold offline reload must retain the same complete save and local assets.
    await context.setOffline(true);
    await page.reload();
    await ready(page);
    const offline = await snapshot();
    assert.equal(offline.worldId, initial.worldId);
    assert.deepEqual(offline.districts, acknowledged.districts);
    assert.deepEqual(offline.research, capped.research);
    assert.deepEqual(offline.claimedRewards, acknowledged.claimedRewards);
    assert.equal(offline.readCompletionNoticeId, acknowledged.readCompletionNoticeId);
    await page.getByRole('button', { name: '設備・進行', exact: true }).click();
    assert.ok(await page.getByRole('button', { name: '都市開発', exact: true }).isVisible());
    await context.setOffline(false);
    console.log('CHECK OK: two-tab lock, save/reward persistence and offline cold reload');

    for (const viewport of [{ width: 844, height: 390 }, { width: 568, height: 320 }]) {
      await page.setViewportSize(viewport);
      await page.getByRole('button', { name: '都市開発', exact: true }).click();
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(output, `v11-web-${viewport.width}-city.png`) });
      await page.getByRole('button', { name: '研究ツリー', exact: true }).click();
      const closeDetail = page.getByRole('button', { name: '研究詳細を閉じる', exact: true });
      if (await closeDetail.count()) await closeDetail.click();
      await page.getByRole('button', { name: '発見した範囲を表示', exact: true }).click();
      await page.screenshot({ path: path.join(output, `v11-web-${viewport.width}-research.png`) });
      await page.getByRole('button', { name: '機関運営', exact: true }).click();
      await page.getByRole('button', { name: '都市基盤', exact: true }).click();
      await page.screenshot({ path: path.join(output, `v11-web-${viewport.width}-foundation.png`) });
      assert.equal(await page.getByRole('button', { name: '人員配分を確定', exact: true }).count(), 0);
    }
    assert.deepEqual(errors, []);
    assert.deepEqual([...origins], [new URL(url).origin], `Unexpected external resources: ${externalRequests.join(', ')}`);
    result = { result: 'PASS', checks: [
      'first housing and immediate research tutorial through UI',
      'manufacturing repeat/reorder preserves the paid iteration and reload order',
      'research-specific city condition stays visible before it is met',
      'construction starts immediately or leaves no waiting reservation',
      'completed city facility enables immediate RP research',
      'population grows through housing and placement cancel creates no asset',
      'forecast does not materialize future constructions or research',
      'population-linked RP and money reserve limits after development-time absence',
      'no staff allocation or training controls',
      'completion history read state and reward persistence',
      'multi-tab lock and offline cold reload',
      'GPU/layout on 844x390 and 568x320 landscape',
      'no external resource hosts',
    ], origins: [...origins] };
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
