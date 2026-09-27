param(
  [Parameter(Mandatory=$true)][string]$Class,
  [int]$MaxLines = 100000
)
# Extract the dexdump section for a class descriptor from D:\aiwork\apk\d24.txt
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File cls.ps1 -Class "Lcom/foo/Bar;"
$file = "D:\aiwork\apk\d24.txt"
$enc  = [System.Text.Encoding]::Unicode
$n = 0
$state = 0   # 0=searching, 1=in-class
$emitted = 0
$lines = New-Object System.Collections.Generic.List[string]
foreach($l in [System.IO.File]::ReadLines($file, $enc)){
  $n++
  if($l.StartsWith("  Class descriptor  :")){
    if($state -eq 1){ break }            # next class -> end of target
    if($l -match [regex]::Escape("'" + $Class + "'")){
      $state = 1
      $lines.Add("$n`t$l")
      continue
    }
  }
  if($state -eq 1){
    $lines.Add("$n`t$l")
    $emitted++
    if($emitted -ge $MaxLines){ break }
  }
}
if($state -eq 0){ Write-Output "CLASS NOT FOUND: $Class"; exit 2 }
$lines
