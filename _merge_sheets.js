const XLSX = require('C:/Users/home/AppData/Roaming/npm/node_modules/xlsx');
const fs = require('fs');
const dir = 'D:/!!!!!크림등록';

function sanitizeSheetName(name) {
  return name.replace(/[\/\\?\*\[\]:]/g, '_').substring(0, 31);
}

function mergeWithSheets(section) {
  const files = fs.readdirSync(dir)
    .filter(f => new RegExp('^20260621_' + section + '_\\d+_').test(f))
    .sort();

  console.log('\n' + section + ': ' + files.length + '개 파일 처리 시작...');

  const outWb = XLSX.utils.book_new();
  const usedNames = {};
  let ok = 0, fail = 0;

  for (let i = 0; i < files.length; i++) {
    const f = files[i];
    try {
      const wb = XLSX.readFile(dir + '/' + f);
      const ws = wb.Sheets[wb.SheetNames[0]];

      const brandName = f.replace(/^20260621_[A-Z]+_\d+_/, '').replace(/\.xls$/i, '');
      let sheetName = sanitizeSheetName(brandName);

      if (usedNames[sheetName]) {
        usedNames[sheetName]++;
        sheetName = sanitizeSheetName(brandName.substring(0, 28)) + '_' + usedNames[sheetName];
      } else {
        usedNames[sheetName] = 1;
      }

      XLSX.utils.book_append_sheet(outWb, ws, sheetName);
      ok++;
      if ((i + 1) % 50 === 0 || i + 1 === files.length) {
        process.stdout.write('\r  [' + (i+1) + '/' + files.length + '] ' + ok + '개 완료');
      }
    } catch (e) {
      console.log('\n  실패: ' + f + ' - ' + e.message.substring(0, 60));
      fail++;
    }
  }

  console.log('\n  완료: ' + ok + '개 성공, ' + fail + '개 실패');

  const outPath = dir + '/20260621_' + section + '_브랜드별합본.xls';
  XLSX.writeFile(outWb, outPath, { bookType: 'xls' });
  const size = Math.round(fs.statSync(outPath).size / 1024);
  console.log('  저장: ' + outPath + ' (' + size + 'KB)');
}

mergeWithSheets('UOMO');
mergeWithSheets('DONNA');
console.log('\n완료!');
