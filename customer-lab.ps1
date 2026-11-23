param([string]$Bin, [int]$Port=55432)
$ErrorActionPreference='Stop'
if (!$Bin) {
    $found=Get-Command initdb.exe -ErrorAction SilentlyContinue
    if ($found) { $Bin=Split-Path $found.Source }
    else { $Bin=(Get-ChildItem "$env:ProgramFiles\PostgreSQL\*\bin\initdb.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).DirectoryName }
}
if (!$Bin -or !(Test-Path "$Bin\initdb.exe")) { throw 'Install PostgreSQL for Windows (server and command line tools), or pass -Bin.' }
$root=Join-Path $env:LOCALAPPDATA ('CustomerLab-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$data=Join-Path $root data
$pwdfile=Join-Path $root init-password
$admin=[guid]::NewGuid().ToString('N')
$reader=[guid]::NewGuid().ToString('N')
$oldPass=$env:PGPASSWORD
$started=$false
function Query($user,$db,$sql) {
    & "$Bin\psql.exe" -X -w -h 127.0.0.1 -p $Port -U $user -d $db -v ON_ERROR_STOP=1 -At -c $sql
    if ($LASTEXITCODE) { throw "Query failed on $db" }
}
try {
    Set-Content $pwdfile $admin -Encoding ascii
    & "$Bin\initdb.exe" -D $data -U lab_admin -A scram-sha-256 "--pwfile=$pwdfile" -E UTF8 --no-locale
    if ($LASTEXITCODE) {throw 'initdb failed'}
    Remove-Item -LiteralPath $pwdfile
    & "$Bin\pg_ctl.exe" -D $data -l "$root\server.log" -o "-h 127.0.0.1 -p $Port" -w start
    if ($LASTEXITCODE) {throw 'Startup failed. Check server.log or try another -Port.'}
    $started=$true
    $env:PGPASSWORD=$admin
    Query lab_admin postgres "CREATE ROLE archive_reader LOGIN PASSWORD '$reader'"
    foreach ($db in 'customer_core','customer_archive') {
        Query lab_admin postgres "CREATE DATABASE $db"
        Query lab_admin postgres "REVOKE ALL ON DATABASE $db FROM PUBLIC"
        $refs=if ($db -eq 'customer_core') {'REF-7Q4M-2X9K','REF-8N5T-3W6P'} else {'REF-4C8R-6T3N','REF-9F2H-5J7S'}
        Query lab_admin $db "REVOKE CREATE ON SCHEMA public FROM PUBLIC; CREATE TABLE customers(customer_ref text PRIMARY KEY, full_name text NOT NULL, email text NOT NULL, tier text NOT NULL); INSERT INTO customers VALUES ('$($refs[0])','Min Kim','min@customer.example','standard'),('$($refs[1])','Jin Lee','jin@customer.example','premium');"
        if ((Query lab_admin $db 'SELECT count(*) FROM customers') -ne '2') {throw 'Seed verification failed'}
    }
    Query lab_admin customer_archive 'GRANT CONNECT ON DATABASE customer_archive TO archive_reader; GRANT USAGE ON SCHEMA public TO archive_reader; GRANT SELECT ON customers TO archive_reader'
    $env:PGPASSWORD=$reader
    $rows=Query archive_reader customer_archive 'SELECT customer_ref FROM customers ORDER BY customer_ref'
    if (($rows -join ',') -ne 'REF-4C8R-6T3N,REF-9F2H-5J7S') {throw 'Token mismatch'}
    foreach ($test in @(@('customer_core','SELECT 1'),@('customer_archive',"INSERT INTO customers VALUES ('probe','test','test@example.test','standard')"))) {
        & "$Bin\psql.exe" -X -w -h 127.0.0.1 -p $Port -U archive_reader -d $test[0] -c $test[1]
        if (!$LASTEXITCODE) {throw 'Expected denial, but operation succeeded'}
    }
    Write-Host "PASS: seeded both databases, verified decoy tokens and both denials. Files: $root"
    Write-Host 'Opening the read-only decoy session. Try SELECT * FROM customers; then type \q to stop.'
    & "$Bin\psql.exe" -X -w -h 127.0.0.1 -p $Port -U archive_reader -d customer_archive
} finally {
    if ($started) { & "$Bin\pg_ctl.exe" -D $data -m fast -w stop }
    if (Test-Path $pwdfile) { Remove-Item -LiteralPath $pwdfile }
    $env:PGPASSWORD=$oldPass
}
