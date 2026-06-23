/**
 * 브랜드별 XLS 파일 합치기 → UOMO 1개 + DONNA 1개
 */

const XLSX = require('C:/Users/home/AppData/Roaming/npm/node_modules/xlsx');
const fs = require('fs');
const path = require('path');

const DOWNLOAD_DIR = 'D:/!!!!!크림등록';
const TODAY = '20260621';

function mergeSection(section) {
  const pattern = new RegExp(`^${TODAY}_${section}_\\d+_.*\\.xls$`, 'i');
  const files = fs.readdirSync(DOWNLOAD_DIR)
    .filter(f => pattern.test(f))
    .sort();

  console.log(`\n📋 ${section}: ${files.length}개 파일 합치는 중...`);

  const allRows = [];
  let headers = null;

  for (let i = 0; i < files.length; i++) {
    const filePath = path.join(DOWNLOAD_DIR, files[i]);
    try {
      const wb = XLSX.readFile(filePath, { type: 'file', cellDates: true });
      const ws = wb.Sheets[wb.SheetNames[0]];
      const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });

      if (rows.length === 0) continue;

      // 첫 파일에서 헤더 추출
      if (!headers) {
        headers = rows[0];
        allRows.push(headers);
      }

      // 데이터 행만 추가 (헤더 제외)
      const dataRows = rows.slice(1).filter(r => r.some(c => c !== ''));
      allRows.push(...dataRows);

      if ((i + 1) % 50 === 0 || i + 1 === files.length) {
        process.stdout.write(`\r  [${i+1}/${files.length}] ${allRows.length - 1}개 행 수집`);
      }
    } catch (e) {
      console.log(`\n  ⚠ ${files[i]}: ${e.message.substring(0, 50)}`);
    }
  }

  console.log(`\n  총 ${allRows.length - 1}개 행`);

  // 새 워크북 생성
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet(allRows);
  XLSX.utils.book_append_sheet(wb, ws, section);

  const outPath = path.join(DOWNLOAD_DIR, `${TODAY}_${section}_전체.xls`);
  XLSX.writeFile(wb, outPath, { bookType: 'xls' });
  const size = fs.statSync(outPath).size;
  console.log(`  ✅ 저장: ${outPath} (${Math.round(size / 1024)} KB)`);
  return outPath;
}

console.log('🔀 파일 합치기 시작...');
mergeSection('UOMO');
mergeSection('DONNA');
console.log('\n🎉 완료!');
