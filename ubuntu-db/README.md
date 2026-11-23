# Ubuntu DB 서버 실습

DB VM의 VMware 어댑터와 두 클라이언트의 어댑터를 같은 labnet-in에 연결합니다. DB VM에 192.168.100.30/24, PC 1에 .20/24, PC 2에 .21/24를 설정한 예시입니다. 주소가 다르면 아래 .env에서 바꿉니다. .env는 PostgreSQL 수신 주소와 접속 허용 목록을 지정합니다. VM 운영체제의 IP는 별도로 설정합니다.

## DB VM에서 실행

저장소 전체를 postgres 사용자가 읽을 수 있는 위치에 놓습니다(예: /opt/customer-db-lab). ubuntu-db 폴더만 복사하면 상위 example-results 데이터가 빠집니다. 격리망으로 전환하기 전에 PostgreSQL 서버와 Python 3 패키지를 준비합니다.

```bash
sudo apt-get install postgresql python3
cd /opt/customer-db-lab/ubuntu-db
cp .env.example .env
nano .env
ip -4 addr
sudo -u postgres python3 server.py
```

최초 실행 때 business_reader 비밀번호를 두 번 입력합니다. 전용 클러스터와 데이터는 /var/lib/postgresql/customer-honey-lab에 보관합니다. 기본 포트 5433으로 터미널에서 서버를 계속 실행합니다. Ctrl+C로 종료한 뒤 같은 명령으로 재시작하면 기존 DB를 사용합니다. 두 PC의 IP 변경도 .env를 수정하고 재시작하면 적용됩니다. 호스트 방화벽이 활성 상태라면 지정한 두 IP에서 DB 포트로 들어오는 TCP를 허용합니다.

## 두 PC에서 확인

각 PC에 PostgreSQL 클라이언트를 설치하고 터미널에서 아래 명령을 실행합니다. .env를 변경했다면 주소와 포트를 맞춥니다.

```bash
psql -h 192.168.100.30 -p 5433 -U business_reader -d customers_5 -W
```

```sql
SELECT current_database(), current_user, inet_client_addr();
SELECT count(*) FROM customers;
SELECT customer_ref, full_name, email, tier FROM customers LIMIT 5;
```

두 PC에서 inet_client_addr()가 각각 자신의 내부망 IP이고 count가 100이면 정상입니다. customers_1, customers_5, customers_10은 각각 100행 중 1, 5, 10개가 미끼인 독립 시나리오입니다. 두 PC는 같은 전체 조회 계정을 사용합니다. 서버는 DB 조회를 제공하며 이전 PowerShell의 로컬 수신 로그 집계와 게이트웨이의 탐지·차단은 별도 단계입니다.
