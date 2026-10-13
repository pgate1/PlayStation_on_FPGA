# E:\fpga-shared\qstatus.ps1 - read-only view of shared Quartus usage on ristisana.
$ProgressPreference = 'SilentlyContinue'
$os = Get-CimInstance Win32_OperatingSystem
'{0:s}  free_gb={1:N1}/{2:N1}  rules: E:\fpga-shared\RULES.txt' -f (Get-Date), ($os.FreePhysicalMemory/1MB), ($os.TotalVisibleMemorySize/1MB)
'--- registry E:\locks'
foreach ($f in Get-ChildItem -LiteralPath E:\locks -Filter *.txt -ErrorAction SilentlyContinue) {
    $r = @{}; foreach ($l in Get-Content -LiteralPath $f.FullName) { if ($l -match '^([a-z_]+)=(.*)$') { $r[$Matches[1]] = $Matches[2] } }
    $alive = @("$($r.pid)" -split '[ ,]+' | Where-Object { $_ -match '^\d+$' -and (Get-Process -Id $_ -ErrorAction SilentlyContinue) })
    '{0,-24} {1,-5} pid={2} since={3:HH:mm} dir={4}' -f $f.Name, ($(if ($alive) {'LIVE'} else {'stale'})), $r.pid, $f.LastWriteTime, $r.workdir
}
'--- quartus processes'
Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'quartus*' } | ForEach-Object {
    $c = "$($_.CommandLine)"; '{0,6} parent={1,6} {2,-16} {3}' -f $_.ProcessId, $_.ParentProcessId, $_.Name, $c.Substring(0, [Math]::Min(110, $c.Length)) }
