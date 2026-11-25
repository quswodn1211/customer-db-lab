# 고객 DB 허니토큰 실습

Windows PC 두 대에서 Ubuntu PostgreSQL 서버에 접속해 고객 데이터를 조회합니다. DB가 결과에 포함된 미끼의 고유번호를 감지하고 게이트웨이 내부 IP로 HTTP 경보를 보냅니다. 설치, Windows용 PostgreSQL 클라이언트, SQL 예제 및 경보 확인 절차는 [Ubuntu 서버와 Windows 클라이언트 실습 안내](ubuntu-db/README.md)에 있습니다.

| 실습 | 실행 위치 | 데이터와 관측 지점 |
|---|---|---|
| 현재 VM 실습 | Ubuntu DB, Ubuntu 게이트웨이, Windows 클라이언트 | 고객 100행, 3열, 미끼 2·5·10개. DB 조회 함수가 경보 기록 |
| 이전 단독 실험 | Windows PowerShell | 고객 100행, 4열, 미끼 1·5·10개. 모의 수신 프로그램이 첫 토큰을 확인 |

이전 결과를 재현하려면 Windows에서 저장소 루트로 이동합니다. PostgreSQL을 설치한 경우 아래 첫 명령을 사용하고, CSV만 사용할 때는 두 번째 명령을 사용합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\customer-lab.ps1
powershell -ExecutionPolicy Bypass -File .\customer-lab.ps1 -Offline
```

이 실험의 결과는 실행별 `runs` 폴더에, 기존 예시 결과는 `example-results`에 있습니다. VM 실습은 자체 SQL로 데이터를 생성합니다.
