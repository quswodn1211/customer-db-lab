param([int]$Seed=42,[int]$Port=55432,[string]$Bin,[switch]$Offline,
      [Parameter(Mandatory=$true)][ValidatePattern('^(?:[2-9]|[1-9][0-9]|100)$')][string]$Percent)
& (Join-Path $PSScriptRoot 'windows-honeygen/customer-lab.ps1') @PSBoundParameters
