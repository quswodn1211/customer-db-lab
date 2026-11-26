# Ubuntu DB 서버와 Windows 클라이언트 실습

# <이 글씨 순서대로 하셈!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!>

전체 고객을 읽을 수 있는 계정으로 조회했을 때 **조회 결과에 미끼 고객이 몇 개 포함됐고 어느 PC가 조회했는지** 확인합니다. DB의 PostgreSQL 로그가 원본 기록입니다. DB의 별도 프로세스가 미끼 경보를 골라 curl로 게이트웨이에 POST합니다. 게이트웨이가 꺼져 있어도 조회와 DB 기록은 계속됩니다.

## 고객별 API 키 사용 경보

HoneyGen 고객 1명(CNO)당 키 하나를 발급합니다. 고객은 같은 GET /v1/me 경로에 자신의 키를 제시합니다. 일반 키는 해당 고객 정보만 반환하고, 미끼 키는 같은 형태로 응답하면서 DB에 HONEYTOKEN_API_USED 경보를 남깁니다. 접속 IP는 TCP 연결의 출발지에서 가져옵니다. 이 HTTP 구성은 격리된 내부 실습망에서 사용합니다.

**팀 게이트웨이**에서는 [팀 저장소의 block_server.py](https://github.com/jihuns22/network_TermProject/tree/main/defense/gateway/block)를 실행합니다. 같은 포트의 예전 gateway.py 대신 이 수신기를 사용하세요. 처음에는 아래처럼 방화벽 변경 없이 검증할 수 있습니다. HT_ALLOWED_SENDERS는 실제 DB의 내부 IP로 바꿉니다.

```bash
cd network_TermProject/defense/gateway/block
HT_ALLOWED_SENDERS=192.168.100.30 python3 block_server.py --dry-run --log "$HOME/honey-alerts.jsonl"
```

**DB VM**에서 업데이트한 server.py로 DB를 재시작합니다. .env에서 API_PORT=8090, GATEWAY_PORT=8080, ALERT_PATH=/alerts를 확인합니다. 팀 게이트웨이에 HT_SHARED_KEY가 설정돼 있으면 DB .env에도 같은 값을 추가하고 forward.py를 재시작합니다. 공유 키를 비워 두면 게이트웨이의 출발지 IP 허용 목록을 사용합니다.

```bash
cd /opt/customer-db-lab/ubuntu-db
# API 전용 OS 계정은 최초 한 번 생성
id honey_api || sudo adduser --system --group --no-create-home honey_api
# DB 기동 후 실행. 다시 실행해도 기존 API 키는 유지됩니다.
sudo -u postgres python3.5 customer_api.py --provision
# 별도 터미널에서 각각 실행
sudo -u honey_api python3.5 customer_api.py
sudo -u postgres python3.5 forward.py
```

honey_api 사용자가 소스 폴더와 .env를 읽을 수 있어야 합니다. API는 해당 계정으로 로컬 소켓에 접속하며, 운영 테이블을 직접 읽는 권한 없이 API 조회 함수만 실행합니다. 시나리오 비율을 바꾼 경우 새 DB에서 --provision을 실행하고 API를 재시작하세요. 실습 PC에서 DB VM의 TCP 8090으로 접속을 허용해야 합니다.

**키 배정 확인**은 DB VM의 관리자 psql에서 합니다. 선택한 시나리오(예: honeygen_5)에 접속하여 아래 쿼리를 실행합니다. 실제 배정 시에는 해당 고객의 키만 전달합니다. 키는 실습용 관리자 테이블에 보관되며 게이트웨이 이벤트에는 CNO와 이벤트 ID만으로 고객을 연결할 수 있습니다.

```sql
SELECT k.cno, k.api_key, (t.cno IS NOT NULL) AS is_honey
FROM honey.api_keys k LEFT JOIN honey.tokens t USING (cno)
ORDER BY is_honey DESC, k.cno;
```

**Windows 클라이언트**에서 정상 키와 미끼 키를 각각 한 번 입력합니다. 잘못된 키는 HTTP 401입니다.

```powershell
$key = Read-Host '테스트할 고객의 API 키'
curl.exe --noproxy "*" -i -H "Authorization: Bearer $key" http://192.168.100.30:8090/v1/me
```

**게이트웨이 확인**은 DB VM에서 먼저 curl --noproxy '*' http://192.168.100.53:8080/health 로 하고, 수신기 터미널 또는 로그에서 db_event가 HONEYTOKEN_API_USED이고 attacker_ip가 Windows PC 내부 IP인 alert를 확인합니다. 정상 키 사용은 이 경보를 만들지 않습니다. 실제 차단 모드에서는 팀 게이트웨이의 기존 IP 차단 정책도 함께 실행됩니다.

## 기준 고객 100명으로 HoneyGen 실행하기
# <3번>
아래 VM 설치·네트워크 절차를 따르고, DB VM의 ubuntu-db/.env에 다음 줄을 추가합니다. 2~100 사이 정수이며 5는 기준 고객 100명에 미끼 5명을 추가한다는 뜻입니다.

```dotenv
HONEY_PERCENT=5
```

기존 서버가 실행 중이면 아래 7절의 pg_ctl 명령으로 정상 종료한 뒤 DB VM에서 실행합니다.

```bash
cd /opt/customer-db-lab/ubuntu-db
sudo -u postgres python3.5 server.py
```

서버는 선택한 비율의 DB를 최초 한 번 생성합니다. 재시작하면 기존 결과를 재사용합니다. 비율을 12로 바꾸고 재시작하면 접속 대상은 honeygen_12입니다. 두 Windows IP에는 현재 선택한 HoneyGen 시나리오의 접속을 허용합니다. 이전 customers_2·5·10 시나리오는 아래 기존 실습 설명대로 사용할 수 있습니다.

```powershell
& 'C:\Program Files\PostgreSQL\19\bin\psql.exe' -h 192.168.100.30 -p 5433 -U business_reader -d honeygen_5 -W
```

```sql
SELECT count(*) FROM read_customers();
SELECT * FROM read_customers('email', false, 1, 0);
SELECT * FROM read_customers('full_name', true, 1, 0);
```

5%에서 첫 쿼리는 105행을 집계하고 미끼 5건의 조회 경보를 남깁니다. 두 번째와 세 번째 쿼리는 각각 ASN 및 YSU 접두사의 서로 다른 미끼 1행을 반환합니다. 경보 전송·게이트웨이 확인은 3절과 6절을 따릅니다. 기본 고객은 Windows와 동일하며, 두 언어의 난수 생성기 차이로 미끼의 구체적인 값은 달라질 수 있습니다.

## 1. 네트워크와 파일 배치

| 장비 | 예시 내부 IPv4 (/24) | 실행할 파일 | 연결 방향 |
|---|---|---|---|
| Ubuntu 16.04 DB | 192.168.100.30 | server.py, forward.py | 두 PC의 TCP 5433 접속 수신, 게이트웨이 TCP 8080으로 송신 |
| Ubuntu 게이트웨이 | 192.168.100.53 | gateway.py | 내부 인터페이스에서 DB의 POST 수신 |
| Windows PC 1 | 192.168.100.20 | psql.exe | DB TCP 5433으로 접속 |
| Windows PC 2 | 192.168.100.21 | psql.exe | DB TCP 5433으로 접속 |

네 장비의 내부 어댑터를 같은 VMware 내부 네트워크에 연결합니다. 게이트웨이는 내부 NIC의 주소를 사용합니다. OS 주소는 Ubuntu에서 `ip -4 addr`, Windows에서 `ipconfig`로 확인합니다. 예를 들어 DB가 실제로 192.168.70.130이고 PC들이 .133과 .134라면 세 값을 바꾸고, 게이트웨이의 실제 192.168.70.x 주소도 확인합니다.

Windows의 기존 사본 경로는 다음과 같습니다.

```powershell
cd C:\src\network_security_project\customer-db-lab\ubuntu-db
Get-ChildItem -Force
```

### 기존 Git 클론 업데이트
# <1번>
DB VM과 게이트웨이 VM에서 각각 `/opt/customer-db-lab`을 Git으로 클론했다면, GitHub의 main 브랜치에 변경 사항이 올라간 뒤 다음 명령을 실행합니다.

```bash
cd /opt/customer-db-lab
git pull --ff-only origin main
cd ubuntu-db
cp -n .env.example .env
nano .env
```

`cp -n`은 .env가 없을 때만 예시 파일을 복사합니다. 기존 .env를 사용 중이면 아래 세 항목 중 빠진 줄을 추가합니다. 이미 있는 키는 해당 줄에서 값을 수정합니다.

```dotenv
GATEWAY_IP=192.168.100.53
GATEWAY_PORT=8080
ALERT_PATH=/alerts
```

<img src="gateway-ip.png" alt="게이트웨이 내부 IP를 확인하세요" width="366">

192.168.100.53은 예시입니다. 게이트웨이 VM에서 `ip -4 addr`로 내부망 NIC의 실제 IPv4 주소를 확인하고 두 VM의 GATEWAY_IP에 같은 주소를 입력합니다. Ctrl+O, Enter로 저장하고 Ctrl+X로 종료한 뒤 2절의 패키지 확인과 3절의 실행 절차로 이동합니다.

### 폴더 복사 또는 ZIP으로 설치

수정된 `ubuntu-db` 폴더 전체를 두 Ubuntu VM의 `/opt/customer-db-lab/ubuntu-db`에 복사합니다. 프로젝트의 `example-results` 폴더는 필요 없습니다. DB 파일은 최초 실행 때 생성합니다.

배포 ZIP을 VM의 홈 폴더에 옮긴 경우 아래처럼 필요한 폴더만 풉니다. 기존 .env는 ZIP에 포함되어 있지 않습니다. 수정해 둔 소스가 있으면 먼저 별도 위치에 보관하세요.

```bash
sudo mkdir -p /opt/customer-db-lab
sudo unzip -o ~/customer-db-lab-ubuntu.zip 'ubuntu-db/*' -d /opt/customer-db-lab
```

두 Ubuntu VM에서 다음을 실행합니다. 기존 .env가 있으면 누락된 키를 .env.example에서 추가합니다.

```bash
cd /opt/customer-db-lab/ubuntu-db
cp -n .env.example .env
nano .env
ip -4 addr
```

```dotenv
DB_SERVER_IP=192.168.100.30
CLIENT_1_IP=192.168.100.20
CLIENT_2_IP=192.168.100.21
DB_PORT=5433
GATEWAY_IP=192.168.100.53
GATEWAY_PORT=8080
ALERT_PATH=/alerts
```

두 VM에 동일한 값을 저장합니다. nano는 Ctrl+O, Enter로 저장하고 Ctrl+X로 종료합니다. .env는 프로그램의 바인딩과 접속 허용값을 지정하므로 실제 NIC 주소는 먼저 OS에서 설정해야 합니다. HTTP 수신기는 DB의 출발지 IP를 확인합니다. 예시의 평문 HTTP와 IP 허용은 격리 실습망을 전제로 합니다.

## 2. Ubuntu 패키지 설치

격리하기 전 Ubuntu 16.04 amd64에서 설치합니다. 아래는 실습용 버전 핀입니다. `apt-cache madison`으로 설정된 저장소에서 제공하는 버전을 확인하세요. 이전 버전이 없는 저장소에서는 사용 가능한 Xenial 패키지의 전체 버전으로 핀을 바꿉니다. 더 최신 보안 패치가 이미 설치되어 있다면 그대로 사용합니다.

**DB VM**

```bash
sudo apt-get update
apt-cache madison postgresql-9.5 postgresql-client-9.5 python3.5 curl
sudo apt-get install postgresql-9.5=9.5.25-0ubuntu0.16.04.1 postgresql-client-9.5=9.5.25-0ubuntu0.16.04.1 python3.5=3.5.2-2ubuntu0~16.04.13 curl=7.47.0-1ubuntu2.19
dpkg-query -W postgresql-9.5 postgresql-client-9.5 python3.5 curl
id postgres
```

**게이트웨이 VM**에는 Python 표준 라이브러리를 사용하는 수신기만 실행합니다.

```bash
python3.5 --version
# Python 3.5가 없을 때
sudo apt-get update
sudo apt-get install python3.5=3.5.2-2ubuntu0~16.04.13
```

## 3. 게이트웨이, DB, 전달기 시작
# <2번>
세 터미널을 각각 열어 둡니다. 실행 계정이 소스 폴더에 접근하고 .env를 읽을 수 있어야 합니다.

**게이트웨이 터미널**

```bash
cd /opt/customer-db-lab/ubuntu-db
python3.5 gateway.py
```

수신기는 성공 시 HTTP 204를 반환하고 실행한 사용자의 `~/honey-alerts.sqlite`에 저장합니다. 실습 방화벽이 켜져 있으면 내부 NIC에서 DB IP가 보내는 TCP 8080을 허용합니다.

**DB 터미널 1**

```bash
cd /opt/customer-db-lab/ubuntu-db
sudo -u postgres python3.5 server.py
```

처음에는 business_reader의 비밀번호를 두 번 입력합니다. 기존 프로젝트와 별개인 `/var/lib/postgresql/customer-honey-v2`에 클러스터를 만듭니다. 예전 서버가 같은 내부 IP의 5433을 사용 중이면 그 서버를 먼저 정상 종료하거나 새 .env의 DB_PORT와 클라이언트 포트를 함께 변경합니다. DB 측 방화벽에서는 두 Windows IP에서 오는 TCP 5433을 허용합니다.

**DB 터미널 2**

```bash
cd /opt/customer-db-lab/ubuntu-db
sudo -u postgres python3.5 forward.py
```

전달기는 DB의 audit.csv에서 SQLSTATE HNY01인 LOG를 읽어 설정한 URL로 전송합니다. HTTP 2xx를 받은 뒤 파일 위치를 저장합니다. 전송 실패 시 3초 뒤 재시도하고, 재시작하면 저장된 위치에서 계속합니다. 응답 손실로 중복 전송되면 게이트웨이가 event_id로 한 번만 저장합니다. 실습 중에는 audit.csv를 교체하거나 비우지 마세요. 자동 순환을 끈 파일이므로 실습 종료 후 디스크 사용량을 확인하세요.

## 4. Windows 두 대에 PostgreSQL 클라이언트 설치

두 PC 각각에서 [PostgreSQL Windows 다운로드](https://www.postgresql.org/download/windows/)의 64비트 설치 프로그램을 실행합니다. 이 안내의 예시 버전은 PostgreSQL 19.0입니다. 구성 요소에서 **Command Line Tools**를 선택하면 psql.exe를 사용할 수 있습니다. 서버는 Ubuntu에서 실행하므로 PC에 별도 DB를 만들 필요가 없습니다. 이미 설치했다면 바로 PowerShell에서 확인합니다.

```powershell
$psql = 'C:\Program Files\PostgreSQL\19\bin\psql.exe'
& $psql --version
$db = '192.168.100.30'
$port = 5433
Test-NetConnection $db -Port $port
& $psql -X -h $db -p $port -U business_reader -d customers_5 -W
```

다른 버전이나 사용자 지정 경로라면 $psql을 수정합니다. TcpTestSucceeded가 True이면 암호를 입력합니다. 아래 SQL은 PowerShell이 아닌 customers_5 프롬프트에서 실행합니다.

```sql
SELECT current_database(), session_user, inet_client_addr();
SELECT * FROM public.read_customers('cno', false, 1, 1);
SELECT * FROM public.read_customers('email', false, 1, 0);
SELECT * FROM public.read_customers('full_name', true, 1, 0);
```

첫 줄의 IP가 각 PC의 주소와 일치하는지 확인합니다. 함수 인수는 **정렬 열, 내림차순 여부, 최대 행 수, 건너뛸 행 수** 순서입니다. 두 번째 줄은 중간 일반행 또는 추가 미끼를 읽습니다. 세 번째 줄은 AAA-000, 네 번째 줄은 ZZZ-999를 반환하며 각 1건의 경보가 발생합니다. psql 종료는 `\q`입니다.

## 5. 데이터와 권한

| 고객 열 | 조건 | 데이터 생성 방식 |
|---|---|---|
| CNO | varchar(10), 기본키, 영문 대문자 3자 + 하이픈 + 숫자 3자 | AAA-000, CUS-001 ~ CUS-098, ZZZ-999 |
| EMAIL | text, NOT NULL, 소문자·숫자 계정명과 @gmail.com | aa000, lab001 ~ lab098, zz999를 계정명으로 사용 |
| FULL_NAME | varchar(20), NOT NULL | Ahn Ara, Kim 001 ~ Kim 098, Zun Yuri |

세 열 모두 C 정렬 규칙을 사용합니다. 100행에서 세 열 중 어느 열로 정렬해도 오름차순 양 끝은 AAA-000과 ZZZ-999이고 내림차순이면 순서가 바뀝니다. Gmail 주소는 형식 실습용 문자열로 메일을 보내지 않습니다. 관리 전용 honey.tokens에 등록한 CNO가 판정 기준입니다. 고객 테이블에는 토큰 여부 열이 없습니다.

| DB | 전체 | 고정 미끼 | 추가 미끼 | 추가 미끼 선택 시드 |
|---|---:|---:|---:|---:|
| customers_2 | 100 | 2 | 0 | 44 (추가 선택 없음) |
| customers_5 | 100 | 2 | 3 | 47 |
| customers_10 | 100 | 2 | 8 | 52 |

schema.sql은 나머지 98개 CNO를 시드와 함께 해시해 정렬한 후 필요한 개수만 등록합니다. business_reader는 세 DB의 100행 모두를 함수로 읽을 수 있습니다. 원본 테이블과 토큰 목록에 대한 직접 조회 권한은 없습니다. PostgreSQL의 일반 SELECT에는 행 트리거가 없으므로 결과 범위 결정, 미끼 판정, 로그 기록을 함수 안에서 처리합니다. DB 관리자 postgres의 직접 테이블 조회는 별도 경로입니다.

## 6. 경보 검증
# <4번>
관측하기 쉬운 customers_2로 Windows에서 접속합니다. 아래 각 SQL을 한 번씩 실행하고 DB와 게이트웨이 로그를 확인합니다.

```sql
SELECT * FROM read_customers('cno', false, 1, 1);
SELECT * FROM read_customers('cno', false, 1, 0);
SELECT * FROM read_customers('cno', true, 1, 0);
SELECT count(*) FROM read_customers();
```

순서대로 **경보 0건, 1건(AAA-000), 1건(ZZZ-999), 2건**이 추가됩니다. 마지막 쿼리의 결과값은 100입니다. 함수 밖에 LIMIT이나 WHERE를 붙이면 함수가 먼저 더 많은 행을 처리할 수 있으므로 측정할 범위는 함수 인수로 지정하세요. 경보 시점은 DB 함수가 미끼행을 결과에 넣는 시점입니다. DB 로그만으로 클라이언트 수신 완료, 외부 반출량 또는 사용자의 신원을 확정할 수 없습니다. 정상적인 전체 조회도 경보를 발생시킵니다.

**DB 로그 관찰** (별도 Ubuntu 터미널)

```bash
sudo -u postgres tail -F /var/lib/postgresql/customer-honey-v2/audit.csv | grep --line-buffered HNY01
```

**게이트웨이 수신 확인** (수신기를 시작한 OS 사용자로 실행)

```bash
python3.5 -c "import sqlite3,os; db=sqlite3.connect(os.path.expanduser('~/honey-alerts.sqlite')); print('\n'.join(r[0] for r in db.execute('select payload from alerts order by rowid desc limit 10')))"
```

같은 event_id, cno, db, login, client_ip, time이 양쪽에 있는지 확인합니다. client_ip는 조회한 Windows PC이고, HTTP 연결의 발신지는 DB 서버입니다. 이 구성은 경보 수집까지 수행합니다. 자동 차단 정책은 포함하지 않습니다.

**Ubuntu에서 관리자 SQL 실행**

```bash
sudo -u postgres /usr/lib/postgresql/9.5/bin/psql -h /var/lib/postgresql/customer-honey-v2/socket -p 5433 -d customers_5
```

```sql
\d public.customers
SELECT count(*) FROM public.customers;
SELECT cno FROM honey.tokens ORDER BY cno;
\q
```

## 7. 문제 해결 및 종료

| 증상 | 확인할 내용 |
|---|---|
| sudo: unknown user: postgres | DB VM에서 postgresql-9.5 서버 패키지 설치 결과와 id postgres 확인 |
| Cannot assign requested address | 오류에 나온 IP와 해당 VM의 ip -4 addr 대조. DB는 DB_SERVER_IP, 게이트웨이는 GATEWAY_IP를 실제 내부 NIC에 맞춤 |
| Address already in use | ss -ltn으로 5433 또는 8080 점유 확인. 기존 실습 프로세스를 정상 종료하거나 포트 설정을 양쪽에서 변경 |
| Windows TCP 연결 실패 | VMware 내부망 이름, OS 주소·서브넷, DB 기동 상태, 방화벽 확인 |
| no pg_hba.conf entry / password authentication failed | CLIENT_1_IP·CLIENT_2_IP와 Windows ipconfig, DB 이름, business_reader 암호 확인. .env 변경 후 관련 프로세스 재시작 |
| permission denied for table customers | Windows에서 public.read_customers(...)로 접속 경로 확인 |
| DB 경보만 있고 게이트웨이에 없음 | 전달기 터미널 재시도 메시지, 두 .env의 내부 주소·경로, 게이트웨이 수신기와 방화벽 확인. 수신기의 403은 DB 출발지 IP 불일치 |

종료는 DB에서 먼저 아래 명령으로 조회 서버를 정상 종료하고 전송이 끝난 뒤 전달기와 게이트웨이 터미널에서 각각 Ctrl+C를 누릅니다. 다음 실행에서도 같은 클러스터, 전송 위치, 수신 DB를 사용합니다.

```bash
sudo -u postgres /usr/lib/postgresql/9.5/bin/pg_ctl -D /var/lib/postgresql/customer-honey-v2/data -m fast -w stop
```

참고 문서: [PostgreSQL 9.5 CSV 서버 로그](https://www.postgresql.org/docs/9.5/runtime-config-logging.html), [Ubuntu Xenial curl 패키지](https://lists.ubuntu.com/archives/xenial-changes/2021-March/029879.html).
