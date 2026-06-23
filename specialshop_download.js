/**
 * specialshop.atelier98.net GENERA EXCEL 전자동 다운로드
 * UOMO + DONNA 전체 브랜드 → Articoli.xls (서버 원본 포맷)
 */

const { chromium } = require('C:/Users/home/AppData/Roaming/npm/node_modules/playwright');
const fs = require('fs');
const path = require('path');

const DOWNLOAD_DIR = 'D:/!!!!!크림등록';
const LOGIN_URL = 'https://specialshop.atelier98.net/it/register.html?idg=log';
const EMAIL = 'moongsshop1@naver.com';
const PASSWORD = '190054326';
const TODAY = new Date().toISOString().slice(0,10).replace(/-/g,'');

async function login(page) {
  await page.goto(LOGIN_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.fill('input[name="UserID"]', EMAIL);
  await page.fill('input[name="Password"]', PASSWORD);
  await page.locator('input[type="submit"]').click({ noWaitAfter: true, timeout: 5000 });
  for (let i = 0; i < 120; i++) {
    await page.waitForTimeout(500);
    if (!page.url().includes('register.html')) return true;
  }
  return false;
}

async function getBrands(page, section) {
  await page.goto(`https://specialshop.atelier98.net/it/${section}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  // DESIGNER 섹션 펼치기
  await page.evaluate(() => {
    const el = document.getElementById('designer');
    if (el) el.style.display = 'block';
  });

  return page.evaluate(() => {
    const designerDiv = document.getElementById('designer');
    if (!designerDiv) return [];
    return Array.from(designerDiv.querySelectorAll('a[href*="idt="]')).map(a => ({
      name: a.textContent.trim(),
      href: a.href,
      idt: new URL(a.href).searchParams.get('idt'),
    }));
  });
}

async function downloadBrandExcel(page, brandHref, brandName, section, index) {
  await page.goto(brandHref, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1200);

  // 버튼 정보
  const info = await page.evaluate(() => {
    const btn = document.getElementById('generaexcel');
    const scripts = Array.from(document.scripts).map(s => s.textContent).join('\n');
    const match = scripts.match(/generaexcel[\s\S]*?url\s*=\s*'([^']+)'/);
    const btnText = btn ? btn.textContent.trim() : '';
    const countMatch = btnText.match(/(\d+)/);
    return {
      excelUrl: match ? match[1] : null,
      count: countMatch ? parseInt(countMatch[1]) : 0,
      btnText,
      visible: !!btn,
    };
  });

  if (!info.visible || !info.excelUrl) {
    return { status: 'no_btn', count: 0 };
  }

  const safeName = brandName.replace(/[\/\\:*?"<>|]/g, '_').substring(0, 40);
  const filename = `${TODAY}_${section}_${String(index).padStart(3,'0')}_${safeName}.xls`;
  const savePath = path.join(DOWNLOAD_DIR, filename);

  // 이미 다운로드된 경우 건너뜀
  if (fs.existsSync(savePath)) {
    return { status: 'skip', count: info.count, file: filename };
  }

  // 다운로드
  try {
    const dlPromise = page.waitForEvent('download', { timeout: 180000 });
    await page.locator('#generaexcel').click({ noWaitAfter: true, timeout: 5000 });
    const dl = await dlPromise;
    await dl.saveAs(savePath);
    const size = fs.statSync(savePath).size;
    return { status: 'ok', count: info.count, file: filename, size };
  } catch (e) {
    return { status: 'fail', count: info.count, error: e.message.substring(0, 60) };
  }
}

async function main() {
  // 출력 디렉토리 확인
  if (!fs.existsSync(DOWNLOAD_DIR)) fs.mkdirSync(DOWNLOAD_DIR, { recursive: true });

  const browser = await chromium.launch({ headless: false, args: ['--no-sandbox'] });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    acceptDownloads: true,
    locale: 'it-IT',
  });
  const page = await context.newPage();

  try {
    // 로그인
    console.log('🔐 로그인...');
    const ok = await login(page);
    if (!ok) { console.log('❌ 로그인 실패'); await browser.close(); return; }
    console.log('✅ 로그인 성공');

    const summary = {};

    for (const section of ['uomo', 'donna']) {
      console.log(`\n═══════════════════════════════`);
      console.log(`📋 ${section.toUpperCase()} 브랜드 목록 수집...`);
      const brands = await getBrands(page, section);
      console.log(`  총 ${brands.length}개 브랜드 발견`);
      summary[section] = { total: brands.length, ok: 0, fail: 0, skip: 0 };

      for (let i = 0; i < brands.length; i++) {
        const brand = brands[i];
        process.stdout.write(`  [${i+1}/${brands.length}] ${brand.name.padEnd(35)} `);

        const result = await downloadBrandExcel(page, brand.href, brand.name, section.toUpperCase(), i+1);

        if (result.status === 'ok') {
          console.log(`✅ ${result.count}개 → ${Math.round(result.size/1024)}KB`);
          summary[section].ok++;
        } else if (result.status === 'skip') {
          console.log(`⏭  이미 존재`);
          summary[section].skip++;
        } else if (result.status === 'no_btn') {
          console.log(`⚠  버튼 없음 (0개)`);
          summary[section].fail++;
        } else {
          console.log(`❌ 실패: ${result.error}`);
          summary[section].fail++;
        }

        // 서버 과부하 방지
        await page.waitForTimeout(1500);
      }

      const s = summary[section];
      console.log(`\n  ${section.toUpperCase()} 완료: ✅${s.ok} 성공 | ⏭${s.skip} 스킵 | ❌${s.fail} 실패`);
    }

    console.log('\n🎉 전체 완료!');
    console.log(`📁 저장 위치: ${DOWNLOAD_DIR}`);

    // 파일 목록
    const files = fs.readdirSync(DOWNLOAD_DIR).filter(f => f.startsWith(TODAY) && f.endsWith('.xls'));
    console.log(`\n총 ${files.length}개 파일 생성:`);
    files.slice(0, 10).forEach(f => console.log(`  - ${f}`));
    if (files.length > 10) console.log(`  ... 외 ${files.length - 10}개`);

  } catch (e) {
    console.error('❌ Fatal:', e.message);
  } finally {
    await browser.close();
  }
}

main();
