# Test du helper : chaque valeur doit etre relue a l'identique.
$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:TEMP ("envtest_" + [Guid]::NewGuid().ToString("N") + ".env")
"IRC_NETWORK_NAME=MonReseau`r`nCONNECT_PASSWORD=CHANGEME`r`nDEFAULT_TOPIC=x`r`n" | Set-Content -LiteralPath $tmp -NoNewline
$cases = @{
  'CONNECT_PASSWORD' = 'Pa$$w0rd'
  'DEFAULT_TOPIC'    = "C'est le salon #1 & on y parle de <tout> !"
  'IRC_NETWORK_NAME' = 'Réseau "privé" éàü'
  'NEW_KEY'          = 'a=b=c'
}
$ok = $true
foreach ($k in $cases.Keys) {
  $env:TESTVAL = $cases[$k]
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'set-env.ps1') -Key $k -ValueFrom TESTVAL -EnvFile $tmp
  if ($LASTEXITCODE -ne 0) { Write-Host "[ECHEC] set-env a renvoye $LASTEXITCODE pour $k"; $ok = $false; continue }
  $back = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'get-env.ps1') -Key $k -EnvFile $tmp
  if ($back -ceq $cases[$k]) { Write-Host ("[OK]    {0,-17} = {1}" -f $k, $back) }
  else { Write-Host ("[ECHEC] {0,-17} attendu <{1}> obtenu <{2}>" -f $k, $cases[$k], $back); $ok = $false }
}
$bytes = [IO.File]::ReadAllBytes($tmp)
$hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)
Write-Host ("[INFO]  encodage : UTF-8 sans BOM = {0}, lignes CRLF = {1}" -f (-not $hasBom), ([Text.Encoding]::UTF8.GetString($bytes) -match "`r`n"))
Remove-Item -LiteralPath $tmp -Force
if (-not $ok) { exit 1 }
Write-Host "[OK] helper .env valide"
