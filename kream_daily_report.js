/**
 * 크림 일일 수익 리포트
 *
 * 1. 자동화파일.xlsb에서 specialshop 상품 로드 (Modello variante, Prezzo vendita, Made in)
 * 2. 검색결과 시트에서 KREAM 상품번호 매칭
 * 3. 당일 EUR/KRW 고시환율(송금보낼때) 조회
 * 4. 원가 계산: (EUR × 환율 + 30,000) × (1 + 관세) × 1.1
 * 5. 크림 최근거래가 스크래핑
 * 6. 마진 20% 이상 제품 HTML 리포트 출력
 */

const { chromium } = require('C:/Users/home/AppData/Roaming/npm/node_modules/playwright');
const XLSX    = require('C:/Users/home/AppData/Roaming/npm/node_modules/xlsx');
const https   = require('https');
const http    = require('http');
const fs      = require('fs');
const path    = require('path');

// ─── 설정 ────────────────────────────────────────────────────────────────────
const XLSB_DIR      = 'D:/!!!!!크림등록';
const REPORT_DIR    = 'D:/!!!!!크림등록/리포트';
const FIXED_COST    = 30_000;          // 고정비 (통관수수료 등)
const TARGET_MARGIN = 0.20;            // 목표 마진율 (20%)
const MAX_CONCURRENT= 3;               // 동시 크림 조회 수
const REQUEST_DELAY = 1500;            // 요청 간 딜레이 ms
const MIN_WONKA     = 30_000;          // 원가 최솟값 (이하는 스킵)

// EU 국가 목록 (이탈리아어/영어 모두 포함)
const EU_COUNTRIES = new Set([
  'ITALY','ITALIA','FRANCE','FRANCIA','GERMANY','GERMANIA','SPAIN','SPAGNA',
  'PORTUGAL','PORTOGALLO','NETHERLANDS','OLANDA','BELGIO','BELGIUM','AUSTRIA',
  'GREECE','GRECIA','DENMARK','DANIMARCA','SWEDEN','SVEZIA','FINLAND','FINLANDIA',
  'CZECH REPUBLIC','CZECHIA','CECA','HUNGARY','UNGHERIA','POLAND','POLONIA',
  'ROMANIA','BULGARIA','SLOVAKIA','SLOVACCHIA','SLOVENIA','CROATIA','CROAZIA',
  'LUXEMBOURG','LUSSEMBURGO','MALTA','ESTONIA','LATVIA','LETTONIA',
  'LITHUANIA','LITUANIA','IRELAND','IRLANDA','CYPRUS','CIPRO',
  'IT','FR','DE','ES','PT','NL','BE','AT','GR','DK','SE','FI',
  'CZ','HU','PL','RO','BG','SK','SI','HR','LU','MT','EE','LV','LT','IE','CY',
]);

// 0.8% 관세 카테고리 키워드 (크림 카테고리 문자열에서 매칭)
const LOW_TARIFF_KEYWORDS = ['가방','지갑','악세사리','액세서리','벨트','모자','스카프'];

// ─── 유틸 ─────────────────────────────────────────────────────────────────────
function isEU(madeIn) {
  if (!madeIn) return false;
  return EU_COUNTRIES.has(String(madeIn).toUpperCase().trim());
}

function getCustomsRate(madeIn, kreamCategory) {
  if (isEU(madeIn)) return 0;
  const cat = String(kreamCategory || '').toLowerCase();
  if (LOW_TARIFF_KEYWORDS.some(k => cat.includes(k))) return 0.008;
  return 0.13;
}

function parseEurPrice(raw) {
  // "EUR 98.3606" → 98.3606
  if (!raw) return null;
  const m = String(raw).replace(/EUR\s*/i, '').replace(',', '.').trim();
  const n = parseFloat(m);
  return isNaN(n) ? null : n;
}

function calcWonKa(eurPrice, rate, madeIn, kreamCategory) {
  const customs = getCustomsRate(madeIn, kreamCategory);
  const base    = eurPrice * rate + FIXED_COST;
  return Math.round(base * (1 + customs) * 1.1);
}

function fmt(n) {
  return Math.round(n).toLocaleString('ko-KR');
}

function delay(ms) {
  return new Promise(r => setTimeout(r, ms));
}

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    lib.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
      let data = '';
      res.on('data', d => { data += d; });
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

// ─── 환율 조회 ────────────────────────────────────────────────────────────────
async function getEurKrwRate() {
  console.log('💱 EUR/KRW 고시환율 조회 중...');

  // 1순위: 하나은행 API (송금보낼때 환율)
  try {
    const body = await fetchUrl('https://api.hanabank.com/api/product/exchangeList?currCd=EUR');
    const json = JSON.parse(body);
    const rate = json?.data?.[0]?.sellExchangeRate || json?.data?.[0]?.ttvSell;
    if (rate && rate > 100) {
      console.log(`  하나은행 송금환율: ${rate}`);
      return parseFloat(rate);
    }
  } catch {}

  // 2순위: 네이버 금융 API
  try {
    const body = await fetchUrl('https://api.stock.naver.com/api/exchange/FX_EURKRW');
    const json = JSON.parse(body);
    const rate = json?.closePrice || json?.price;
    if (rate && rate > 100) {
      console.log(`  네이버 환율: ${rate}`);
      return parseFloat(String(rate).replace(',', ''));
    }
  } catch {}

  // 3순위: exchangerate-api (국제 스팟, 참고용)
  try {
    const body = await fetchUrl('https://api.exchangerate-api.com/v4/latest/EUR');
    const json = JSON.parse(body);
    const rate = json?.rates?.KRW;
    if (rate && rate > 100) {
      console.log(`  ExchangeRate-API: ${rate} (스팟, 고시환율 아님)`);
      return parseFloat(rate);
    }
  } catch {}

  // 폴백: 수동 입력 안내
  const fallback = 1550;
  console.warn(`  ⚠ 환율 자동 조회 실패 → 기본값 ${fallback} 사용 (직접 수정 필요)`);
  return fallback;
}

// ─── xlsb 로드 ────────────────────────────────────────────────────────────────
function findLatestXlsb() {
  const files = fs.readdirSync(XLSB_DIR)
    .filter(f => /^자동화파일_\d+\.xlsb$/i.test(f))
    .map(f => ({ f, mtime: fs.statSync(path.join(XLSB_DIR, f)).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
  if (!files.length) throw new Error('자동화파일_*.xlsb 없음: ' + XLSB_DIR);
  console.log('📂 사용 파일:', files[0].f);
  return path.join(XLSB_DIR, files[0].f);
}

function loadXlsbData(xlsbPath) {
  console.log('📊 Excel 로드 중...');
  const wb = XLSX.readFile(xlsbPath);

  // ── 데이터부르기 시트 → 모델별 EUR 가격 + Made in ──
  const dataWs   = wb.Sheets['데이터부르기'];
  const dataRows  = XLSX.utils.sheet_to_json(dataWs, { header: 1, defval: '' });
  const dataHeader= dataRows[0].map(h => String(h).trim());

  const COL = {
    brand:    dataHeader.indexOf('Brand'),
    model:    dataHeader.indexOf('Modello variante'),
    prezzo:   dataHeader.indexOf('Prezzo vendita'),
    madeIn:   dataHeader.indexOf('Made in'),
    descr:    dataHeader.indexOf('Descrizione'),
    colore:   dataHeader.indexOf('Colore'),
  };

  // 모델별 첫 번째 행 데이터만 사용 (사이즈 중복 제거)
  const productMap = new Map(); // Modello variante → { brand, eurPrice, madeIn, descrizione, colore }
  for (let i = 1; i < dataRows.length; i++) {
    const row = dataRows[i];
    const model = String(row[COL.model] || '').trim();
    if (!model || productMap.has(model)) continue;

    const eurPrice = parseEurPrice(row[COL.prezzo]);
    if (!eurPrice || eurPrice <= 0) continue;

    productMap.set(model, {
      brand:    String(row[COL.brand] || '').trim(),
      eurPrice,
      madeIn:   String(row[COL.madeIn] || '').trim(),
      descrizione: String(row[COL.descr] || '').trim(),
      colore:   String(row[COL.colore] || '').trim(),
    });
  }
  console.log(`  데이터부르기: ${productMap.size}개 고유 모델`);

  // ── 검색결과 시트 → 모델 ↔ 크림 ID 매핑 ──
  const srWs     = wb.Sheets['검색결과'];
  const srRows   = XLSX.utils.sheet_to_json(srWs, { header: 1, defval: '' });
  const srHeader = srRows[0].map(h => String(h).trim());

  const SR = {
    modelSupplier: srHeader.indexOf('업체 모델번호'),
    kreamId:       srHeader.indexOf('KREAM 상품번호'),
    kreamModel:    srHeader.indexOf('KREAM 모델번호'),
    brandName:     srHeader.indexOf('브랜드명'),
    nameEn:        srHeader.indexOf('영문 상품명'),
    nameKo:        srHeader.indexOf('한글 상품명'),
    category:      srHeader.indexOf('카테고리'),
  };

  // kreamId → { supplierModel, nameEn, nameKo, category, brand }
  const kreamMap = new Map();
  for (let i = 1; i < srRows.length; i++) {
    const row      = srRows[i];
    const kreamId  = Number(row[SR.kreamId]);
    if (!kreamId || isNaN(kreamId)) continue;
    if (kreamMap.has(kreamId)) continue;

    const supplierModel = String(row[SR.modelSupplier] || '').trim();
    kreamMap.set(kreamId, {
      supplierModel,
      nameEn:   String(row[SR.nameEn] || '').trim(),
      nameKo:   String(row[SR.nameKo] || '').trim(),
      category: String(row[SR.category] || '').trim(),
      brand:    String(row[SR.brandName] || '').trim(),
    });
  }
  console.log(`  검색결과: ${kreamMap.size}개 고유 크림 상품`);

  return { productMap, kreamMap };
}

// ─── 크림 최근거래가 조회 ─────────────────────────────────────────────────────
async function getKreamRecentPrice(context, kreamId) {
  const url  = `https://kream.co.kr/products/${kreamId}`;
  const page = await context.newPage();

  try {
    // API 응답 가로채기
    let apiPrice = null;
    page.on('response', async (response) => {
      const resUrl = response.url();
      if (resUrl.includes('/api/v2/products/' + kreamId) ||
          resUrl.includes('/products/' + kreamId) && resUrl.includes('api')) {
        try {
          const json = await response.json().catch(() => null);
          if (!json) return;
          // 크림 API 구조: recent_trade_price, lowest_ask, etc.
          const price =
            json?.product?.recent_price ||
            json?.recent_price ||
            json?.data?.recent_price ||
            json?.product?.lowest_ask?.price ||
            json?.lowest_ask?.price;
          if (price && price > 0) apiPrice = price;
        } catch {}
      }
    });

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20_000 });
    await page.waitForTimeout(2000);

    // API 인터셉트로 가격을 잡은 경우
    if (apiPrice) return apiPrice;

    // DOM에서 가격 추출 (즉시구매가 또는 최근거래가)
    const priceText = await page.evaluate(() => {
      // 다양한 셀렉터 시도
      const selectors = [
        '.product_info .price',
        '.buy_price',
        '[class*="price"]:not([class*="original"])',
        '.price_info .price',
        'strong.price',
      ];
      for (const sel of selectors) {
        const el = document.querySelector(sel);
        if (el) {
          const txt = el.textContent.replace(/[^\d]/g, '');
          if (txt.length >= 4) return txt;
        }
      }
      // fallback: 페이지에서 숫자+원 패턴 찾기
      const matches = document.body.innerText.match(/(\d{1,3}(?:,\d{3})+)원/g);
      if (matches && matches.length > 0) {
        const nums = matches.map(m => parseInt(m.replace(/[^\d]/g, '')));
        const valid = nums.filter(n => n >= 5000 && n <= 50_000_000);
        return valid.length > 0 ? String(valid[0]) : null;
      }
      return null;
    });

    if (priceText) return parseInt(priceText);
    return null;
  } catch (err) {
    // timeout이나 네트워크 오류
    return null;
  } finally {
    await page.close().catch(() => {});
  }
}

// ─── 병렬 처리 헬퍼 ──────────────────────────────────────────────────────────
async function runWithConcurrency(items, concurrency, fn) {
  const results = [];
  const queue   = [...items];
  let done = 0;

  async function worker() {
    while (queue.length > 0) {
      const item = queue.shift();
      const result = await fn(item);
      results.push(result);
      done++;
      if (done % 10 === 0) {
        process.stdout.write(`\r  진행: ${done}/${items.length} (결과 ${results.filter(r => r?.qualifies).length}개 발견)`);
      }
      await delay(REQUEST_DELAY);
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => worker()));
  return results;
}

// ─── HTML 리포트 생성 ─────────────────────────────────────────────────────────
function generateHtmlReport(hits, rate, totalChecked, today) {
  const rows = hits.map((h, i) => `
    <tr>
      <td>${i + 1}</td>
      <td><a href="https://kream.co.kr/products/${h.kreamId}" target="_blank">${h.kreamId}</a></td>
      <td><strong>${h.brand}</strong></td>
      <td>${h.supplierModel}</td>
      <td>${h.nameKo || h.nameEn}</td>
      <td>${h.madeIn || '-'}</td>
      <td>${h.category}</td>
      <td style="text-align:right">${h.eurPrice.toFixed(2)} €</td>
      <td style="text-align:right">${fmt(h.wonKa)}원</td>
      <td style="text-align:right;font-weight:bold;color:#1a73e8">${fmt(h.kreamPrice)}원</td>
      <td style="text-align:right;color:${h.margin >= 0.3 ? '#d32f2f' : '#388e3c'};font-weight:bold">
        +${(h.margin * 100).toFixed(1)}%
      </td>
      <td style="text-align:right">${fmt(h.kreamPrice - h.wonKa)}원</td>
    </tr>`).join('');

  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>크림 수익 리포트 ${today}</title>
<style>
  body { font-family: 'Apple SD Gothic Neo', '맑은 고딕', sans-serif; margin: 0; padding: 24px; background: #f5f5f5; }
  h1 { font-size: 20px; color: #111; margin-bottom: 4px; }
  .meta { font-size: 13px; color: #666; margin-bottom: 20px; }
  .summary { display: flex; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }
  .card { background: #fff; border-radius: 12px; padding: 16px 24px; box-shadow: 0 1px 4px rgba(0,0,0,.1); min-width: 160px; }
  .card .label { font-size: 12px; color: #888; margin-bottom: 4px; }
  .card .value { font-size: 22px; font-weight: 700; color: #111; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,.1); }
  th { background: #111; color: #fff; padding: 10px 12px; font-size: 12px; text-align: left; white-space: nowrap; }
  td { padding: 9px 12px; font-size: 13px; border-bottom: 1px solid #f0f0f0; vertical-align: middle; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f9f9f9; }
  a { color: #1a73e8; text-decoration: none; }
  a:hover { text-decoration: underline; }
</style>
</head>
<body>
<h1>📊 크림 수익 리포트 — ${today}</h1>
<p class="meta">EUR/KRW 환율: <strong>${fmt(rate)}</strong>원 &nbsp;|&nbsp; 조회 상품: <strong>${totalChecked}</strong>개 &nbsp;|&nbsp; 20% 이상: <strong>${hits.length}</strong>개</p>
<div class="summary">
  <div class="card"><div class="label">조회 상품</div><div class="value">${totalChecked}</div></div>
  <div class="card"><div class="label">수익 20%+</div><div class="value" style="color:#388e3c">${hits.length}</div></div>
  <div class="card"><div class="label">수익 30%+</div><div class="value" style="color:#d32f2f">${hits.filter(h => h.margin >= 0.3).length}</div></div>
  <div class="card"><div class="label">환율 (EUR/KRW)</div><div class="value">${fmt(rate)}</div></div>
</div>
<table>
  <thead>
    <tr>
      <th>#</th><th>크림ID</th><th>브랜드</th><th>모델번호</th><th>상품명</th>
      <th>원산지</th><th>카테고리</th><th>EUR가격</th><th>원가</th><th>크림 최근거래가</th><th>마진율</th><th>수익</th>
    </tr>
  </thead>
  <tbody>${rows || '<tr><td colspan="12" style="text-align:center;padding:40px;color:#999">조건에 맞는 제품이 없습니다.</td></tr>'}</tbody>
</table>
</body>
</html>`;
}

// ─── 메인 ─────────────────────────────────────────────────────────────────────
async function main() {
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  console.log(`\n🚀 크림 일일 수익 리포트 시작 — ${today}`);
  console.log('='.repeat(60));

  // 리포트 폴더 생성
  if (!fs.existsSync(REPORT_DIR)) fs.mkdirSync(REPORT_DIR, { recursive: true });

  // 1. 환율 조회
  const rate = await getEurKrwRate();
  console.log(`  EUR/KRW: ${fmt(rate)}원`);

  // 2. xlsb 로드
  const xlsbPath = findLatestXlsb();
  const { productMap, kreamMap } = loadXlsbData(xlsbPath);

  // 3. 조인: kreamId → product 정보 + 원가
  const targets = [];
  for (const [kreamId, kreamInfo] of kreamMap.entries()) {
    const prod = productMap.get(kreamInfo.supplierModel);
    if (!prod) continue; // 데이터부르기에 없는 모델

    const wonKa = calcWonKa(prod.eurPrice, rate, prod.madeIn, kreamInfo.category);
    if (wonKa < MIN_WONKA) continue;

    targets.push({
      kreamId,
      supplierModel: kreamInfo.supplierModel,
      brand:         kreamInfo.brand || prod.brand,
      nameEn:        kreamInfo.nameEn,
      nameKo:        kreamInfo.nameKo,
      category:      kreamInfo.category,
      madeIn:        prod.madeIn,
      eurPrice:      prod.eurPrice,
      wonKa,
    });
  }

  console.log(`\n🎯 원가 계산 완료: ${targets.length}개 대상`);
  console.log(`   예시 원가 분포:`);
  const buckets = [0, 50000, 100000, 200000, 500000];
  for (let i = 0; i < buckets.length - 1; i++) {
    const cnt = targets.filter(t => t.wonKa >= buckets[i] && t.wonKa < buckets[i+1]).length;
    console.log(`   ${fmt(buckets[i])}~${fmt(buckets[i+1])}원: ${cnt}개`);
  }
  const cnt500 = targets.filter(t => t.wonKa >= 500000).length;
  console.log(`   500,000원+: ${cnt500}개`);

  // 4. 크림 가격 조회
  console.log(`\n🔍 크림 최근거래가 조회 시작...`);
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-blink-features=AutomationControlled'],
  });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    viewport: { width: 1280, height: 800 },
  });

  const hits = [];

  const results = await runWithConcurrency(targets, MAX_CONCURRENT, async (target) => {
    const kreamPrice = await getKreamRecentPrice(context, target.kreamId);
    if (!kreamPrice || kreamPrice <= 0) return { qualifies: false };

    const margin = (kreamPrice - target.wonKa) / target.wonKa;
    const qualifies = margin >= TARGET_MARGIN;

    return { ...target, kreamPrice, margin, qualifies };
  });

  await browser.close();
  console.log(''); // 진행표시 줄바꿈

  // 결과 필터링 & 정렬 (마진 높은 순)
  const qualified = results
    .filter(r => r?.qualifies)
    .sort((a, b) => b.margin - a.margin);

  // 5. 리포트 생성
  const reportPath = path.join(REPORT_DIR, `kream_report_${today}.html`);
  const html = generateHtmlReport(qualified, rate, targets.length, today);
  fs.writeFileSync(reportPath, html, 'utf8');

  // JSON 원본 저장
  const jsonPath = path.join(REPORT_DIR, `kream_report_${today}.json`);
  fs.writeFileSync(jsonPath, JSON.stringify({ rate, date: today, total: targets.length, hits: qualified }, null, 2), 'utf8');

  console.log('\n' + '='.repeat(60));
  console.log(`✅ 완료!`);
  console.log(`   조회: ${targets.length}개 / 20%+: ${qualified.length}개 / 30%+: ${qualified.filter(h => h.margin >= 0.3).length}개`);
  console.log(`   리포트: ${reportPath}`);

  if (qualified.length > 0) {
    console.log('\n📋 TOP 10 수익 상품:');
    qualified.slice(0, 10).forEach((h, i) => {
      console.log(`  ${i+1}. [${h.brand}] ${h.nameKo || h.nameEn}`);
      console.log(`     원가 ${fmt(h.wonKa)}원 → 크림 ${fmt(h.kreamPrice)}원 (+${(h.margin*100).toFixed(1)}%) / 수익 ${fmt(h.kreamPrice - h.wonKa)}원`);
    });
  }
}

main().catch(err => {
  console.error('\n❌ 오류:', err.message);
  process.exit(1);
});
