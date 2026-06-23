/**
 * 버켄스탁 상품 이미지 자동 다운로드 v3
 * 핵심 전략:
 *  1. Sites-master-catalog-apac 경로 이미지만 사용 (Library 제외)
 *  2. 가장 자주 등장하는 product folder ID로 해당 상품 이미지만 필터
 *  3. 갤러리 내 이미지 순서 유지 (썸네일 클릭 후 수집)
 */

const { chromium } = require('C:/Users/home/AppData/Roaming/npm/node_modules/playwright');
const XLSX = require('C:/Users/home/AppData/Roaming/npm/node_modules/xlsx');
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const EXCEL_PATH = 'C:/Users/home/Downloads/Articoli (3).xls';
const SAVE_DIR = 'D:\\등록 브랜드 사진\\버켄스탁';
const BASE_URL = 'https://www.birkenstock.com';

const EXCLUDE_PATTERNS = [
  'privacy-policy', 'legal', 'faq', 'order-status', 'account',
  'cart', 'checkout', 'contact', 'about', 'stores', 'newsletter',
  'returns', 'shipping', 'customer', 'service', 'sitemap',
  'jobs', 'career', 'press', 'terms', 'imprint', 'accessibility',
  'cookie', 'search', 'wishlist', 'login', 'register',
];

function isProductUrl(url) {
  const lower = url.toLowerCase();
  for (const pat of EXCLUDE_PATTERNS) {
    if (lower.includes(pat)) return false;
  }
  return lower.includes('/kr/') && lower.includes('.html');
}

function getModelNumbers() {
  const wb = XLSX.readFile(EXCEL_PATH);
  const ws = wb.Sheets[wb.SheetNames[0]];
  const data = XLSX.utils.sheet_to_json(ws, { header: 1 });
  const models = new Set();
  for (let i = 1; i < data.length; i++) {
    const row = data[i];
    if (!row || !row[2]) continue;
    const val = String(row[2]).trim();
    const match = val.match(/^(\d+)/);
    if (match) models.add(match[1]);
  }
  return [...models];
}

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith('https') ? https : http;
    const file = fs.createWriteStream(dest);
    const req = proto.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.birkenstock.com/kr/',
      },
    }, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        file.close();
        fs.unlink(dest, () => {});
        downloadFile(res.headers.location, dest).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode !== 200) {
        file.close();
        fs.unlink(dest, () => {});
        reject(new Error(`HTTP ${res.statusCode}`));
        return;
      }
      res.pipe(file);
      file.on('finish', () => file.close(resolve));
    });
    req.on('error', (e) => { fs.unlink(dest, () => {}); reject(e); });
    req.setTimeout(20000, () => { req.destroy(); reject(new Error('timeout')); });
  });
}

async function dismissCookiePopup(page) {
  const selectors = [
    '#onetrust-accept-btn-handler',
    'button[id*="accept"]',
    'button[class*="accept"]',
    'button:has-text("동의")',
    'button:has-text("Accept")',
    'button:has-text("모두 수락")',
    'button:has-text("수락")',
    '[class*="cookie"] button',
    '[class*="consent"] button',
  ];
  for (const sel of selectors) {
    try {
      const btn = page.locator(sel).first();
      if (await btn.isVisible({ timeout: 1500 })) {
        await btn.click();
        await page.waitForTimeout(800);
        return;
      }
    } catch (_) {}
  }
}

async function getProductUrl(page, model) {
  await page.goto(`${BASE_URL}/kr/search?q=${model}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);
  await dismissCookiePopup(page);
  await page.waitForTimeout(1000);

  const cur = page.url();
  if (isProductUrl(cur)) return cur;

  const links = await page.evaluate(() =>
    Array.from(document.querySelectorAll('a[href]')).map((a) => a.href)
  );
  const found = links.filter(isProductUrl);
  return found[0] || null;
}

/**
 * 상품 페이지에서 실제 상품 이미지만 추출.
 * 전략: Sites-master-catalog-apac 경로 이미지 중 가장 많이 등장하는
 *        product folder ID를 메인 상품 ID로 보고, 해당 ID의 이미지만 선택.
 */
async function getProductImages(page, productUrl) {
  await page.goto(productUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);
  await dismissCookiePopup(page);
  await page.waitForTimeout(800);

  // 갤러리 썸네일 클릭 (lazy-load 트리거)
  const thumbSelectors = [
    '.product-thumbnails li button',
    '.pdp-gallery__thumbnails li button',
    '[class*="thumbnail"] button',
    '[class*="Thumbnail"] button',
    '[class*="gallery"] [class*="thumb"]',
  ];
  for (const sel of thumbSelectors) {
    const thumbs = await page.$$(sel);
    if (thumbs.length > 1) {
      for (const t of thumbs) {
        try { await t.click(); await page.waitForTimeout(350); } catch (_) {}
      }
      break;
    }
  }

  // 페이지 HTML 전체에서 CDN URL 추출
  const allUrls = await page.evaluate(() => {
    const html = document.documentElement.innerHTML;
    const re = /https:\/\/www\.birkenstock\.com\/dw\/image\/v2\/BLTQ_PRD\/on\/demandware\.static\/-\/Sites-master-catalog-apac[^"'\s,>]+\.jpg/g;
    return [...new Set(html.match(re) || [])];
  });

  if (allUrls.length === 0) return [];

  // URL에서 product folder ID 추출: .../default/[hash]/[ID]/[ID]_xxx.jpg
  const folderCount = {};
  for (const u of allUrls) {
    // /default/hash/FOLDER/FILE.jpg 패턴
    const m = u.match(/\/default\/[a-z0-9]+\/(\d+)\//i);
    if (m) {
      const id = m[1];
      folderCount[id] = (folderCount[id] || 0) + 1;
    }
  }

  if (Object.keys(folderCount).length === 0) {
    // 폴더 ID 없으면 전체 반환
    return allUrls.map((u) => toHighRes(u));
  }

  // 가장 많이 등장하는 folder ID = 메인 상품
  const topId = Object.entries(folderCount).sort((a, b) => b[1] - a[1])[0][0];
  console.log(`  → 상품 folder ID: ${topId} (${folderCount[topId]}개 이미지)`);

  // 해당 folder ID 이미지만 선택, 중복 제거
  const filtered = [...new Set(
    allUrls.filter((u) => u.includes(`/${topId}/`)).map(toHighRes)
  )];

  // 파일명 기준으로 정렬 (메인→top→side→pair→sole 등)
  const ORDER = ['_main', '.jpg', '_top', '_side', '_f_closeup', '_detail', '_pair', '_sole', '_f_look', '_m_look'];
  filtered.sort((a, b) => {
    const nameA = a.split('/').pop().split('?')[0];
    const nameB = b.split('/').pop().split('?')[0];
    const rankA = ORDER.findIndex((o) => nameA.includes(o));
    const rankB = ORDER.findIndex((o) => nameB.includes(o));
    return (rankA === -1 ? 99 : rankA) - (rankB === -1 ? 99 : rankB);
  });

  return filtered;
}

function toHighRes(url) {
  try {
    const u = new URL(url);
    u.searchParams.set('sw', '1200');
    u.searchParams.set('sh', '1200');
    u.searchParams.delete('sm');
    u.searchParams.set('q', '90');
    return u.toString();
  } catch (_) {
    return url;
  }
}

async function main() {
  const models = getModelNumbers();
  console.log(`\n✅ 총 ${models.length}개 모델: ${models.join(', ')}\n`);

  if (!fs.existsSync(SAVE_DIR)) fs.mkdirSync(SAVE_DIR, { recursive: true });

  const alreadyDone = new Set();
  for (const f of fs.readdirSync(SAVE_DIR)) {
    const m = f.match(/^(\d+)-\d+\./);
    if (m) alreadyDone.add(m[1]);
  }

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    locale: 'ko-KR',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8' },
  });

  const results = [];

  for (const model of models) {
    if (alreadyDone.has(model)) {
      console.log(`⏭  ${model} — 건너뜀`);
      results.push({ model, status: 'skip', count: 0 });
      continue;
    }

    console.log(`\n🔍 [${model}]`);
    const page = await context.newPage();

    try {
      const productUrl = await getProductUrl(page, model);
      if (!productUrl) {
        console.log(`  ❌ 상품 URL 없음`);
        await page.close();
        results.push({ model, status: 'not_found', count: 0 });
        continue;
      }
      console.log(`  → ${productUrl}`);

      const imageUrls = await getProductImages(page, productUrl);
      console.log(`  → 이미지 ${imageUrls.length}개`);

      if (imageUrls.length === 0) {
        console.log(`  ❌ 이미지 없음`);
        await page.close();
        results.push({ model, status: 'no_images', count: 0 });
        continue;
      }

      let downloaded = 0;
      for (let i = 0; i < imageUrls.length; i++) {
        const filename = `${model}-${i + 1}.jpg`;
        const dest = path.join(SAVE_DIR, filename);
        try {
          await downloadFile(imageUrls[i], dest);
          const size = fs.statSync(dest).size;
          if (size < 8000) {
            fs.unlinkSync(dest);
            console.log(`  ⚠ 너무 작음 제외 (${filename})`);
          } else {
            downloaded++;
            console.log(`  ✅ ${filename} (${Math.round(size / 1024)}KB)`);
          }
        } catch (e) {
          console.log(`  ⚠ 실패 (${filename}): ${e.message}`);
        }
      }

      // 번호 재정렬
      const saved = fs.readdirSync(SAVE_DIR)
        .filter((f) => f.startsWith(`${model}-`)).sort();
      saved.forEach((f, idx) => {
        const op = path.join(SAVE_DIR, f);
        const np = path.join(SAVE_DIR, `${model}-${idx + 1}.jpg`);
        if (op !== np) fs.renameSync(op, np);
      });

      results.push({ model, status: downloaded > 0 ? 'done' : 'failed', count: downloaded });
    } catch (e) {
      console.log(`  ❌ 오류: ${e.message}`);
      results.push({ model, status: 'error', count: 0, error: e.message });
    } finally {
      await page.close();
    }

    await new Promise((r) => setTimeout(r, 2000));
  }

  await browser.close();

  console.log('\n═══════════════════════════════════════');
  console.log('📊 결과 요약');
  console.log('═══════════════════════════════════════');
  for (const r of results) {
    const icon = r.status === 'done' ? '✅' : r.status === 'skip' ? '⏭ ' : '❌';
    console.log(`${icon} ${r.model.padEnd(12)} → ${r.count}개${r.error ? ' (' + r.error + ')' : ''}`);
  }
  const total = results.reduce((s, r) => s + r.count, 0);
  console.log(`\n🎉 완료! 총 ${total}개 이미지`);
  console.log(`📁 ${SAVE_DIR}`);
}

main().catch((e) => { console.error('Fatal:', e); process.exit(1); });
