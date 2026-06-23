---
description: D:/!!!!!크림등록 폴더의 브랜드별 XLS 파일을 UOMO/DONNA 전체 합본(행 통합)으로 만듭니다
---

`D:/!!!!!크림등록` 폴더에 있는 날짜별 브랜드 XLS 파일들을 읽어, UOMO와 DONNA 각각 모든 행을 하나의 시트로 합친 `전체.xls` 파일을 생성해줘.

## 규칙

- 날짜(TODAY)는 폴더 안 파일명에서 자동으로 읽어온다 (`20260621` 형식, 가장 최신 날짜 사용).
- 합칠 대상 파일 패턴: `{TODAY}_UOMO_{번호}_{브랜드명}.xls`, `{TODAY}_DONNA_{번호}_{브랜드명}.xls`
- 헤더(1행)는 첫 번째 파일에서 한 번만 가져오고, 이후 파일은 데이터 행만 추가한다.
- 완전히 빈 행은 제외한다.
- 출력 파일: `{TODAY}_UOMO_전체.xls`, `{TODAY}_DONNA_전체.xls` (같은 폴더에 저장, 기존 파일 덮어쓰기)
- xlsx 라이브러리 경로: `C:/Users/home/AppData/Roaming/npm/node_modules/xlsx`
- 작업 완료 후 UOMO/DONNA 각각 몇 개 파일, 몇 행이 합쳐졌는지 알려준다.

## 실행 방법

`D:/DOCUMENTS/specialshop_merge.js` 파일이 있으면 그 파일을 실행한다.
없으면 아래 로직으로 Node.js 스크립트를 작성해 실행한다:

1. `D:/!!!!!크림등록` 폴더에서 파일 목록을 읽어 TODAY 날짜를 추출한다.
2. UOMO, DONNA 각각 번호 패턴(`_\d+_`)으로 파일을 필터링 후 정렬한다.
3. 각 파일의 첫 번째 시트를 읽어 행을 누적한다 (헤더는 최초 1회만).
4. `XLSX.utils.aoa_to_sheet` + `XLSX.writeFile(..., { bookType: 'xls' })` 로 저장한다.
