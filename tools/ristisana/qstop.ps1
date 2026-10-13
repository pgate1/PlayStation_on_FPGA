# E:\fpga-shared\qstop.ps1 - stop ONE of your own jobs: the process tree under the
# PID recorded in your registry file. Refuses other sessions' files. Never by name.
param([Parameter(Mandatory)][string]$Session, [Parameter(Mandatory)][string]$Reg)
$ErrorActionPreference = 'Stop'
$file = Get-Item -LiteralPath $Reg
if ($file.DirectoryName -ne 'E:\locks' -or $file.Name -notlike "$Session-*.txt") { throw "not your registry file: $Reg" }
$r = @{}; foreach ($l in Get-Content -LiteralPath $file.FullName) { if ($l -match '^([a-z_]+)=(.*)$') { $r[$Matches[1]] = $Matches[2] } }
$all = Get-CimInstance Win32_Process
function Tree($id) { $id; foreach ($c in $all | Where-Object { $_.ParentProcessId -eq $id }) { Tree $c.ProcessId } }
$root = [int]$r.pid
$rootProc = $all | Where-Object { $_.ProcessId -eq $root }
if (-not $rootProc -or "$($rootProc.CommandLine)" -notlike "*$Reg*") { "root pid $root is not this job's worker; nothing killed"; exit 1 }
$ids = @(Tree $root); [array]::Reverse($ids)
foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; "stopped $id" }
Remove-Item -LiteralPath $file.FullName -ErrorAction SilentlyContinue; "removed $($file.Name)"
