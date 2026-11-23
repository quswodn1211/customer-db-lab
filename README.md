# PostgreSQL 고객 DB 실습

고객 DB(customer_core)와 미끼 DB(customer_archive)에 서로 다른 고객 참조번호를 넣고, 읽기 계정 archive_reader가 미끼 데이터만 조회할 수 있는지 확인하는 실습입니다.

## Windows에서 실행

PostgreSQL 서버와 명령줄 도구를 설치한 뒤, 이 저장소 폴더에서 일반 사용자 PowerShell을 열고 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\customer-lab.ps1
```

스크립트는 실행할 때마다 새 데이터 폴더를 만들고 로컬 주소 127.0.0.1:55432에서 PostgreSQL을 시작합니다. 각 DB에 고객 2명을 넣은 뒤 미끼 표식 조회, 고객 DB 접속 거부, 미끼 테이블 쓰기 거부를 검사합니다. 차단 테스트에서는 오류 문구가 각각 DB 접속 권한과 테이블 쓰기 권한을 가리키는지 확인하세요. 마지막에 열린 psql에서 직접 조회할 수 있습니다.

```sql
SELECT customer_ref, full_name FROM customers ORDER BY customer_ref;
```

미끼 DB의 예상 참조번호는 REF-4C8R-6T3N과 REF-9F2H-5J7S입니다. psql에서 `\q`를 입력하면 스크립트가 실습 서버를 종료합니다.

## Ubuntu에서 사용

PostgreSQL의 CREATE DATABASE, CREATE TABLE, INSERT, GRANT, REVOKE, SELECT 구문은 Ubuntu에서도 사용할 수 있습니다. Windows 스크립트에는 .exe 파일과 Windows 전용 경로가 포함되어 있어 Ubuntu에서 자동 구축하려면 실행 부분을 변경해야 합니다.

PostgreSQL이 설치되어 실행 중인 Ubuntu DB VM의 **터미널**에서 관리자 계정으로 접속합니다.

```bash
sudo -u postgres psql -d postgres
```

**postgres=# 프롬프트**가 나타나면 아래 SQL로 현재 DB와 계정을 확인합니다.

```sql
SELECT current_database(), current_user;
```

두 값이 모두 postgres이면 관리자 접속에 성공한 것입니다. 새 실습 환경에서는 이 세션에서 역할과 DB를 생성한 후 각 DB로 연결하여 테이블 생성, 데이터 삽입, 권한 설정을 진행합니다.

| 입력 위치 | 사용할 명령 |
|---|---|
| Ubuntu 터미널 | sudo, psql, GitHub CLI가 설치된 경우 gh auth login 및 gh repo create |
| psql 프롬프트 | CREATE, INSERT, GRANT, REVOKE, SELECT 등의 SQL. 문장 끝에 세미콜론을 붙입니다. |
| psql 프롬프트 | `\connect customer_archive`로 생성된 미끼 DB에 연결하고 `\q`로 종료합니다. 이 명령에는 세미콜론을 붙이지 않습니다. |
