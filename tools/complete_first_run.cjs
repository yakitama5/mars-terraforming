// 呼び出し元の専用context内だけで操作する。保存値を書き換えない。
const steps = [
  '住宅地区',
  '区画 2（海岸）を選択',
  '着工する',
  'ルナに完成を頼む',
  '研究へ進む',
  '技術を解放する',
  'ガイドと開発を続ける',
];

const button = (page, name) => page.getByRole('button', { name, exact: true });

// リロードで途中の工程へ戻った場合も、通常ナビゲーションを待つ前に検出する。
function firstRunControl(page) {
  return steps.map(name => button(page, name)).reduce((left, right) => left.or(right)).first();
}

async function completeFirstRun(page) {
  const game = button(page, '設備・進行');
  await game.or(firstRunControl(page)).first().waitFor({ timeout: 60000 });
  if (await game.isVisible()) return false; // 初回案内のない既存世界。

  for (let remaining = steps.length; remaining > 0; remaining--) {
    await firstRunControl(page).waitFor({ timeout: 60000 });
    let current;
    for (const name of steps) {
      const candidate = button(page, name);
      if (await candidate.isVisible()) {
        current = { name, candidate };
        break;
      }
    }
    if (!current) throw new Error('初回案内で操作できる次の手順が見つかりません');
    await current.candidate.click({ timeout: 60000 });
    // 保存確定と次の画面を待ち、古いボタンをもう一度押さない。
    await current.candidate.waitFor({ state: 'hidden', timeout: 60000 });
    if (current.name === 'ガイドと開発を続ける') {
      const guide = page.getByText('開発ガイド・Tips', { exact: true });
      await guide.waitFor({ timeout: 60000 });
      await button(page, '閉じる').and(page.locator('[tabindex="0"]')).click();
      await guide.waitFor({ state: 'hidden' });
      await game.waitFor({ timeout: 60000 });
      return true;
    }
  }
  throw new Error('初回案内が規定の7操作で完了しませんでした');
}

module.exports = { completeFirstRun, firstRunControl };
