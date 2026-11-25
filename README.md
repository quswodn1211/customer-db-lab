# Windows 고객 DB · HoneyGen 실습

압축을 풀고 이 폴더에서 PowerShell을 엽니다. 기본 고객은 windows-honeygen/customers-base.csv의 가상 고객 100명입니다. 비율은 기준 고객 수 대비 추가량입니다. 5를 입력하면 고객 100명과 새 미끼 5명, 총 105명이 됩니다. 정수 2~100을 입력할 수 있습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\customer-lab.ps1 -Percent 5 -Offline
```

PostgreSQL의 실제 조회까지 테스트하려면 PostgreSQL의 bin 폴더(initdb.exe, pg_ctl.exe, psql.exe 포함)가 설치된 상태에서 -Offline을 빼세요. 기본 포트는 55432이며 -Port로 바꿀 수 있습니다. -Seed 123으로 표본을 바꿀 수 있습니다. 로컬 임시 클러스터는 실행 후 종료됩니다.

실행 결과의 windows-honeygen/runs 폴더에는 실험별로 전체 customers.csv, 관리용 tokens.txt, PostgreSQL용 customers.sql, 첫 미끼까지 읽은 received.jsonl과 events.csv가 생깁니다. 모의 수신은 섞인 순서로 진행합니다. 실제 외부 전송을 측정하지 않습니다. 별도 DB에서 직접 실험하려면 빈 실습 DB에 customers.sql을 psql의 \i 명령으로 불러옵니다. 예를 들어 SELECT * FROM customers ORDER BY email DESC LIMIT 1; 의 CNO를 tokens.txt와 대조하세요. SQL 파일의 정렬 규칙은 C입니다.

생성기는 기준 고객의 성씨·이름·번호 접두사와 이메일 숫자 접미사 사용 빈도를 표본 추출합니다. 기존 이름·이메일·고유번호와 중복되는 후보를 다시 뽑습니다. 양 끝 두 행은 별도의 성씨와 지점 코드를 사용해 세 열의 양 끝을 동시에 차지합니다. Gmail 주소는 실습용 조합이며 발송용 주소가 아닙니다. 논문과 구현 범위는 [연구 요약 PDF](HoneyGen-guide.pdf)에 정리했습니다.

기존 VM 절차는 [Ubuntu DB 안내](ubuntu-db/README.md)에 있습니다.
