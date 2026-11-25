param([int]$Seed=42,[int]$Port=55432,[string]$Bin,[switch]$Offline,
      [Parameter(Mandatory=$true)][ValidatePattern('^(?:[2-9]|[1-9][0-9]|100)$')][string]$Percent)
$ErrorActionPreference='Stop'
$Percent = [int]$Percent
if (!$Offline -and !$Bin) { $Bin=(Get-ChildItem "$env:ProgramFiles\PostgreSQL\*\bin\initdb.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).DirectoryName }
$run=New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot ("runs/"+[guid]::NewGuid().ToString("N")))
$cluster=Join-Path $env:TEMP ("pg-honey-"+[guid]::NewGuid().ToString("N"))
$admin=[guid]::NewGuid().ToString("N")
$reader=[guid]::NewGuid().ToString("N")
$pw=Join-Path $run 'init-password'
$old=$env:PGPASSWORD
$started=$false
function Sql($user,$db,$query) {
    & "$Bin\psql.exe" -X -w -h 127.0.0.1 -p $Port -U $user -d $db -v ON_ERROR_STOP=1 -At -c $query
    if ($LASTEXITCODE) { throw "Query failed in $db" }
}
try {
    if (!$Offline) {
    Set-Content $pw $admin -Encoding ascii
    & "$Bin\initdb.exe" -D $cluster -U lab_admin -A scram-sha-256 "--pwfile=$pw" -E UTF8 --no-locale | Out-Null
    if ($LASTEXITCODE) { throw 'initdb failed' }
    Remove-Item $pw
    & "$Bin\pg_ctl.exe" -D $cluster -l "$cluster/server.log" -o "-h 127.0.0.1 -p $Port" -w start
    if ($LASTEXITCODE) { throw 'Server startup failed' }
    $started=$true
    $env:PGPASSWORD=$admin
    Sql lab_admin postgres "CREATE ROLE business_reader LOGIN PASSWORD '$reader'"
    }
    & {
        $scenarioSeed=[int]((([long]$Seed + $percent) % 2147483647 + 2147483647) % 2147483647)
        $rng=New-Object System.Random($scenarioSeed)
        $base=@(Import-Csv (Join-Path $PSScriptRoot 'customers-base.csv'))
        if ($base.Count -ne 100) {throw 'Expected 100 reference customers'}
        $names=@{}; $ids=@{}; $emails=@{}
        foreach ($r in $base) {
            $names.Add($r.FULL_NAME,$true)
            $ids.Add($r.CNO,$true)
            $emails.Add($r.EMAIL,$true)
        }
        # Sample observed surname, given name, branch prefix and email suffix styles.
        # Reserve one plausible surname and branch before/after the reference ranges.
        $tokens=@()
        $generated=foreach ($i in 0..($Percent-1)) {
            $tries=0
            do {
                if (++$tries -gt 10000) {throw 'Could not satisfy uniqueness constraints'}
                $sample=$base[$rng.Next(100)]
                $family=$sample.FULL_NAME.Split(' ')[0]
                $given=$base[$rng.Next(100)].FULL_NAME.Split(' ')[1]
                $prefix=$sample.CNO.Substring(0,3)
                if ($i -eq 0) {$family='Ahn'; $prefix='ASN'}
                if ($i -eq 1) {$family='Yun'; $prefix='YSU'}
                $name="$family $given"
                $cno='{0}-{1:D3}' -f $prefix,$rng.Next(100,1000)
                $suffix=''
                if ($base[$rng.Next(100)].EMAIL -match '[0-9]@') {$suffix=[string]$rng.Next(10,100)}
                $email=($family+$given).ToLowerInvariant()+$suffix+'@gmail.com'
            } while ($names.ContainsKey($name) -or $ids.ContainsKey($cno) -or $emails.ContainsKey($email))
            $names[$name]=$true; $ids[$cno]=$true; $emails[$email]=$true
            $tokens+=$cno
            [pscustomobject]@{CNO=$cno;EMAIL=$email;FULL_NAME=$name}
        }
        $rows=@($base)+@($generated)
        for ($i=$rows.Count-1;$i -gt 0;$i--) {
            $j=$rng.Next($i+1)
            $rows[$i],$rows[$j]=$rows[$j],$rows[$i]
        }
        foreach ($col in 'CNO','EMAIL','FULL_NAME') {
            [string[]]$keys=$rows | ForEach-Object {$_.$col}
            [Array]::Sort($keys,[StringComparer]::Ordinal)
            if ($keys[0] -ne $generated[0].$col -or $keys[-1] -ne $generated[1].$col) {
                throw "Sorted endpoint check failed for $col"
            }
        }
        $env:PGPASSWORD=$admin
        $db="customers_$percent"
        $dir=New-Item -ItemType Directory (Join-Path $run "$percent-percent")
        if (!$Offline) { Sql lab_admin postgres "CREATE DATABASE $db" }
        $rows | Export-Csv "$dir/customers.csv" -NoTypeInformation
        $tokens | Set-Content "$dir/tokens.txt"
        $values=($rows | ForEach-Object {
            $fields=foreach ($v in $_.CNO,$_.EMAIL,$_.FULL_NAME) {"'" + $v.Replace("'","''") + "'"}
            '(' + ($fields -join ',') + ')'
        }) -join ','
        $sqlFile=Join-Path $dir 'customers.sql'
        @"
BEGIN;
CREATE TABLE customers(
    cno varchar(10) COLLATE "C" PRIMARY KEY CHECK(cno ~ '^[A-Z]{3}-[0-9]{3}$'),
    email text COLLATE "C" NOT NULL,
    full_name varchar(20) COLLATE "C" NOT NULL
);
INSERT INTO customers VALUES $values;
COMMIT;
"@ | Set-Content $sqlFile -Encoding ascii
        if (!$Offline) {
            & "$Bin\psql.exe" -X -w -h 127.0.0.1 -p $Port -U lab_admin -d $db -v ON_ERROR_STOP=1 -f $sqlFile
            if ($LASTEXITCODE) {throw 'SQL import failed'}
            Sql lab_admin $db 'GRANT SELECT ON customers TO business_reader'
            $env:PGPASSWORD=$reader
            if ([int](Sql business_reader $db 'SELECT count(*) FROM customers') -ne (100 + $Percent)) {
                throw 'Row count mismatch'
            }
            foreach ($col in 'cno','email','full_name') {
                foreach ($direction in 'ASC','DESC') {
                    $edge=Sql business_reader $db "SELECT cno FROM customers ORDER BY $col $direction LIMIT 1"
                    if ($tokens -notcontains $edge) {throw "Missing endpoint for $col $direction"}
                }
            }
        }
        $count=0
        foreach ($row in $rows) {
            if ($Offline) { $json=$row | ConvertTo-Json -Compress } else {
            $json=Sql business_reader $db "SELECT row_to_json(c) FROM customers c WHERE cno='$($row.cno)'"
            }
            Add-Content "$dir/received.jsonl" $json -Encoding utf8
            $count++
            $hit=$tokens -contains ($json | ConvertFrom-Json).cno
            [pscustomobject]@{utc=[datetime]::UtcNow.ToString('o');seed=$scenarioSeed;percent=$percent;received=$count;cno=$row.cno;detected=$hit} | Export-Csv "$run/events.csv" -Append -NoTypeInformation
            if ($hit) {break}
        }
        if (!$hit -or @(Get-Content "$dir/received.jsonl").Count -ne $count) {throw 'Receipt verification failed'}
        Write-Host "$percent% : before=$($count-1) including_token=$count"
    }
    Write-Host "Results: $run"
} finally {
    if ($started) { & "$Bin\pg_ctl.exe" -D $cluster -m fast -w stop }
    if (Test-Path $pw) { Remove-Item $pw }
    $env:PGPASSWORD=$old
}
