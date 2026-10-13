# E:\fpga-shared\qworker.ps1 - started detached by qrun.ps1; do not call directly.
param([Parameter(Mandatory)][string]$Reg)
$ProgressPreference = 'SilentlyContinue'
$r = @{}
foreach ($line in Get-Content -LiteralPath $Reg) { if ($line -match '^([a-z_]+)=(.*)$') { $r[$Matches[1]] = $Matches[2] } }
$env:PATH = 'E:\altera\quartus\bin64;' + $env:PATH
$code = 255
try {
    Add-Content -LiteralPath $r.log -Encoding ASCII -Value ('[qrun] start {0:s} pid={1} reg={2} cmd={3}' -f (Get-Date), $PID, $Reg, $r.command)
    Set-Location -LiteralPath $r.workdir
    cmd.exe /d /c "($($r.command)) >> `"$($r.log)`" 2>&1"
    $code = $LASTEXITCODE
} finally {
    Add-Content -LiteralPath $r.log -Encoding ASCII -Value ('[qrun] end {0:s} exit={1}' -f (Get-Date), $code)
    Set-Content -LiteralPath ($r.log + '.done') -Encoding ASCII -Value $code
    Remove-Item -LiteralPath $Reg -ErrorAction SilentlyContinue
}
exit $code
