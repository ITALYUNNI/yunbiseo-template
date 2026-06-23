// 브랜드 1개 테스트: acne studios (idt=1980000794)
const { chromium } = require('C:/Users/home/AppData/Roaming/npm/node_modules/playwright');
const fs = require('fs');
const path = require('path');

const DOWNLOAD_DIR = 'D:/!!!!!크림등록';
const LOGIN_URL = 'https://specialshop.atelier98.net/it/register.html?idg=log';
const EMAIL = 'moongsshop1@naver.com';
const PASSWORD = '190054326';

async function main() {
  const browser = await chromium.launch({ headless: false, args: ['--no-sandbox'] });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    acceptDownloads: true,
  });
  const page = await context.newPage();

  try {
    // 로그인
    await page.goto(LOGIN_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(1500);
    await page.fill('input[name="UserID"]', EMAIL);
    await page.fill('input[name="Password"]', PASSWORD);
    await page.locator('input[type="submit"]').click({ noWaitAfter: true, timeout: 5000 });
    for (let i = 0; i < 120; i++) {
      await page.waitForTimeout(500);
      if (!page.url().includes('register.html')) break;
    }
    console.log('✅ 로그인:', page.url());

    // acne studios 브랜드 페이지
    const brandUrl = 'https://specialshop.atelier98.net/it/uomo?idt=1980000794';
    console.log('\n📥 브랜드 페이지 접속:', brandUrl);
    await page.goto(brandUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);

    // 상품 수 및 GENERA EXCEL 버튼 확인
    const info = await page.evaluate(() => {
      const btn = document.getElementById('generaexcel');
      const scripts = Array.from(document.scripts).map(s => s.textContent).join('\n');
      const match = scripts.match(/generaexcel[\s\S]*?url\s*=\s*'([^']+)'/);
      const bodyText = document.body.innerText;
      const countMatch = bodyText.match(/(\d+)\s*Articoli?/i);
      return {
        btnText: btn ? btn.textContent.trim() : '없음',
        excelUrl: match ? match[1] : null,
        count: countMatch ? countMatch[0] : '?',
        bodyPreview: bodyText.substring(0, 200),
      };
    });

    console.log('버튼:', info.btnText);
    console.log('Excel URL:', info.excelUrl);
    console.log('상품 수:', info.count);

    if (info.excelUrl) {
      console.log('\n💾 GENERA EXCEL 클릭...');
      const dlPromise = page.waitForEvent('download', { timeout: 180000 });
      await page.locator('#generaexcel').click({ noWaitAfter: true, timeout: 5000 });
      console.log('클릭 완료. 다운로드 대기 (최대 3분)...');

      const dl = await dlPromise;
      const suggested = dl.suggestedFilename();
      console.log('다운로드 파일명:', suggested);

      const savePath = path.join(DOWNLOAD_DIR, `TEST_acne_studios_${suggested}`);
      await dl.saveAs(savePath);
      const size = fs.statSync(savePath).size;
      console.log(`✅ 저장: ${savePath} (${Math.round(size/1024)} KB)`);
    }

    await page.waitForTimeout(3000);
    await browser.close();
  } catch (e) {
    console.error('오류:', e.message);
    await browser.close().catch(() => {});
  }
}

main();
