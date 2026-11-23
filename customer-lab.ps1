param([int]$Seed=42,[int]$Port=55432,[string]$Bin,[switch]$Offline)
$ErrorActionPreference='Stop'
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
    $rng=New-Object System.Random($Seed)
    $positions=1..100
    for ($i=99;$i -gt 0;$i--) {
        $j=$rng.Next($i+1)
        $positions[$i],$positions[$j]=$positions[$j],$positions[$i]
    }
    foreach ($percent in 1,5,10) {
        $env:PGPASSWORD=$admin
        $db="customers_$percent"
        $dir=New-Item -ItemType Directory (Join-Path $run "$percent-percent")
        if (!$Offline) { Sql lab_admin postgres "CREATE DATABASE $db" }
        $tokens=@()
        $rows=foreach ($i in 1..100) {
            $ref="REF-{0:D4}" -f $i
            if ($positions[0..($percent-1)] -contains $i) {
                $ref="REF-{0:D4}" -f (1000+$i)
                $tokens+=$ref
            }
            [pscustomobject]@{customer_ref=$ref;full_name="Customer $i";email="customer$i@example.test";tier=@('standard','premium')[$i%2]}
        }
        $rows | Export-Csv "$dir/customers.csv" -NoTypeInformation
        $tokens | Set-Content "$dir/tokens.txt"
        $values=($rows | ForEach-Object {"('$($_.customer_ref)','$($_.full_name)','$($_.email)','$($_.tier)')"}) -join ','
        if (!$Offline) {
        Sql lab_admin $db "CREATE TABLE customers(customer_ref text PRIMARY KEY,full_name text,email text,tier text); INSERT INTO customers VALUES $values; GRANT SELECT ON customers TO business_reader"
        $env:PGPASSWORD=$reader
        if ((Sql business_reader $db 'SELECT count(*) FROM customers') -ne '100') {throw 'Row count mismatch'}
        }
        $count=0
        foreach ($row in $rows) {
            if ($Offline) { $json=$row | ConvertTo-Json -Compress } else {
            $json=Sql business_reader $db "SELECT row_to_json(c) FROM customers c WHERE customer_ref='$($row.customer_ref)'"
            }
            Add-Content "$dir/received.jsonl" $json -Encoding utf8
            $count++
            $hit=$tokens -contains ($json | ConvertFrom-Json).customer_ref
            [pscustomobject]@{utc=[datetime]::UtcNow.ToString('o');seed=$Seed;percent=$percent;received=$count;customer_ref=$row.customer_ref;detected=$hit} | Export-Csv "$run/events.csv" -Append -NoTypeInformation
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

