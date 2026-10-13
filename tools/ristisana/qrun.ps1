# E:\fpga-shared\qrun.ps1 - the ONE shared launcher for Quartus work on ristisana.
# Owner: Pocket PSX session (lead). Rules: E:\fpga-shared\RULES.txt.
#
# Admits a job only when free RAM >= 6 GB and fewer than 4 live jobs exist,
# registers it in E:\locks\<Session>-<n>.txt, and starts it DETACHED from the
# ssh session (Win32_Process.Create), so a dropped ssh link does not kill it.
# Returns at once; poll with qstatus.ps1 or the log. Never kills anything.
#
# Example (from ssh):
#   powershell -NoProfile -File E:\fpga-shared\qrun.ps1 -Session pocket-psx `
#     -WorkDir E:\psx\diag -Command "quartus_sh --flow compile ap_core"
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{1,30}$')][string]$Session,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$Command,
    [string]$Log,
    [int]$MaxWaitMinutes = 120
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Locks = 'E:\locks'
$MinFreeGB = 6
$MaxJobs = 4
$StaleHours = 3

if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { throw "WorkDir not found: $WorkDir" }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
New-Item -ItemType Directory -Force -Path $Locks | Out-Null
if (-not $Log) { $Log = Join-Path $WorkDir ('qrun-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)) }

function Read-Reg($file) {
    $h = @{}
    foreach ($line in Get-Content -LiteralPath $file -ErrorAction SilentlyContinue) {
        if ($line -match '^([a-z_]+)=(.*)$') { $h[$Matches[1]] = $Matches[2] }
    }
    $h
}
function Test-Live($file) {
    $r = Read-Reg $file.FullName
    if ($file.LastWriteTime -lt (Get-Date).AddHours(-$StaleHours) -and -not $r.pid) { return $false }
    $pids = @("$($r.pid)" -split '[ ,]+' | Where-Object { $_ -match '^\d+$' })
    if (-not $pids) { return ($file.LastWriteTime -gt (Get-Date).AddMinutes(-2)) }  # being written
    foreach ($p in $pids) { if (Get-Process -Id $p -ErrorAction SilentlyContinue) { return $true } }
    $false
}

$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
while ($true) {
    # Exclusive open of the admission file serialises admission across all
    # sessions; Windows releases it even if this process dies.
    $gate = $null
    try { $gate = [IO.File]::Open("$Locks\.admission", 'OpenOrCreate', 'ReadWrite', 'None') } catch { }
    if ($gate) {
        try {
            $live = @(Get-ChildItem -LiteralPath $Locks -Filter *.txt | Where-Object { Test-Live $_ })
            $os = Get-CimInstance Win32_OperatingSystem
            $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
            if ($live.Count -lt $MaxJobs -and $freeGB -ge $MinFreeGB) {
                $n = 1
                while (Test-Path -LiteralPath "$Locks\$Session-$n.txt") { $n++ }
                $reg = "$Locks\$Session-$n.txt"
                @("session=$Session", "workdir=$WorkDir", "command=$Command", "log=$Log",
                  ('started={0:s}' -f (Get-Date)), 'pid=') | Set-Content -LiteralPath $reg -Encoding ASCII
                $worker = Join-Path $PSScriptRoot 'qworker.ps1'
                $cl = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -Reg "{1}"' -f $worker, $reg
                $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
                    -Arguments @{ CommandLine = $cl; CurrentDirectory = $WorkDir }
                if ($res.ReturnValue -ne 0) { Remove-Item -LiteralPath $reg; throw "Win32_Process.Create failed: $($res.ReturnValue)" }
                (Get-Content -LiteralPath $reg) -replace '^pid=$', "pid=$($res.ProcessId)" | Set-Content -LiteralPath $reg -Encoding ASCII
                "STARTED reg=$reg pid=$($res.ProcessId) log=$Log free_gb=$freeGB live_before=$($live.Count)"
                exit 0
            }
            "WAIT live=$($live.Count)/$MaxJobs free_gb=$freeGB (need >= $MinFreeGB)"
        } finally { $gate.Dispose() }
    } else { 'WAIT admission busy' }
    if ((Get-Date) -gt $deadline) { 'GAVE UP waiting for a slot'; exit 3 }
    Start-Sleep -Seconds 30
}
