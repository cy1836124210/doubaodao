param(
  [Parameter(Mandatory=$true)][string]$Class,
  [Parameter(Mandatory=$true)][string]$Method,
  [Parameter(Mandatory=$true)][string[]]$Regs
)
# Print every instruction in a method that writes or reads the given registers.
$sec = & "$PSScriptRoot\cls.ps1" -Class $Class
$inMethod = $false
foreach($line in $sec){
  if($line -match "\s+name\s+: '([^']*)'"){
    if($matches[1] -eq $Method){ $inMethod = $true } elseif($inMethod){ break }
    continue
  }
  if(-not $inMethod){ continue }
  # <lineno>\t<addr>: <hexunits> |<offset>: <instruction> // <comment>
  if($line -notmatch "^\s*\d+\t([0-9a-f]{6,}):\s*([0-9a-f ]*?)\s*\|([0-9a-f]{4}):\s*(.*)$"){ continue }
  $off  = $matches[3]
  $hex  = $matches[2].Trim()
  $rest = $matches[4]
  $insn = $rest; $cmt = ""
  if($rest.Contains('//')){ $insn = $rest.Substring(0,$rest.IndexOf('//')).Trim(); $cmt = $rest.Substring($rest.IndexOf('//')+2).Trim() }
  if($insn -eq ""){ continue }
  $mn = ($insn -split '\s+')[0]

  # destination register (first operand) for common opcodes
  $dest = $null
  if($hex.Length -ge 4){
    $b1 = $hex.Substring(0,2); $b0 = $hex.Substring(2,2)
    if($mn -match '^move-result'){ $dest = 'v' + [Convert]::ToInt32($b1,16) }
    elseif($mn -match '^move-object|^move'){ $dest = 'v' + [Convert]::ToInt32($b0,16) }
    elseif($mn -match '^(const|new-instance|new-array|check-cast|instance-of|sget|aget|iget|array-length|not-|neg-|int-to-|long-to-|add-int|sub-int|and-int|or-int|xor-int|shl-int|shr-int|ushr-int|mul-int|div-int|rem-int|add-int|rsub-int|cmp)'){
      if($mn -notmatch '/range|/from16|/high16'){ $dest = 'v' + [Convert]::ToInt32($b0,16) }
    }
  }
  $writes = ($dest -and ($Regs -contains $dest))
  $reads  = $false
  foreach($r in $Regs){ if($insn -match ("(^|[,\s{])" + [regex]::Escape($r) + "($|[,\s}]|$)")){ $reads = $true } }
  if($writes -or $reads){
    $tag = if($writes){"WRITE"}else{"read "}
    Write-Output ("{0} {1} {2,-26} {3}   // {4}" -f $off,$tag,$insn,$cmt,$dest)
  }
}
