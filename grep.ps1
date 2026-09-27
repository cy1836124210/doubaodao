param(
  [Parameter(Mandatory=$true)][string]$Pattern,
  [int]$Limit = 400,
  [int]$Show = 0,
  [switch]$Regex
)
# Fast case-sensitive scan of the UTF-16 dump with 1-based line numbers.
$file = "D:\aiwork\apk\d24.txt"
$enc  = [System.Text.Encoding]::Unicode
$n = 0
$hits = 0
foreach($l in [System.IO.File]::ReadLines($file, $enc)){
  $n++
  $ok = if($Regex){ $l -match $Pattern } else { $l.Contains($Pattern) }
  if($ok){
    $hits++
    if($hits -le $Limit){
      if($Show -gt 0){
        Write-Output ("{0}: {1}" -f $n, $l)
      } else {
        Write-Output $n
      }
    }
  }
}
Write-Output ("### TOTAL HITS: {0}" -f $hits)
