param(
  [Parameter(Mandatory=$true)][string]$Class,
  [Parameter(Mandatory=$true)][string]$Method,   # exact e.g. 'process' or 'o'
  [string]$TypeLike = "",
  [string[]]$Regs = @(),
  [switch]$All
)
# Parse a dexdump class section and print offset / mnemonic / operands,
# flagging destination registers for data-flow tracing.
$sec = & "$PSScriptRoot\cls.ps1" -Class $Class
$inMethod = $false
$hdrSeen = 0
foreach($line in $sec){
  if($line -match "\s+name\s+: '([^']*)'"){
    if($matches[1] -eq $Method){ $inMethod = $true } else { if($inMethod){ break } }
    continue
  }
  if($inMethod){
    if($line -match "\s+type\s+: '([^']*)'"){
      if($TypeLike -ne "" -and $matches[1] -notlike $TypeLike){ $inMethod=$false; continue }
      continue
    }
    if($line -match "^\s*\d+\t\d+\s+([0-9a-f]{6,}):\s+[0-9a-f ]+\|([0-9a-f]{4}):\s+([0-9a-f]+)\s+(.*?)\s*//\s*(.*)$"){
      $off=$matches[2]; $hex=$matches[3]; $mn=$matches[4]; $cm=$matches[5]
      $dest = ""
      # decode destination registers from the 16-bit units
      if($mn -match '^(move|move-object|move-result|move-result-object|move-result-wide|move-exception|check-cast|instance-of|new-instance|new-array|sget|sget-object|sget-boolean|sget-wide|const|const-string|const-wide|const-class|not-int|neg-int|int-to-|array-length|throw|return|if-|goto|cmp|invoke|monitor|nop|fill|packed|sparse|add-|sub-|mul-|div-|rem-|and-|or-|xor-|shl-|shr-|ushr-|rsub|aget|aput|iput|iget|sput|aput-object|aget-object)'){
        switch -regex ($mn){
          '^move-result' { $dest = "v$([Convert]::ToInt32($hex.Substring(0,2),16))" }
          '^move-object' { $dest = "v$([Convert]::ToInt32($hex.Substring(2,2),16))" }
          '^move'        { $dest = "v$([Convert]::ToInt32($hex.Substring(2,2),16))" }
          '^check-cast|^instance-of|^new-instance|^new-array|^const-string|^const-class|^sget' {
                           $dest = "v$([Convert]::ToInt32($hex.Substring(2,2),16))" }
          '^const|^not-|^neg-|^int-to-|^long-to-|^float-to-|^double-to-|^array-length|^new-array' {
                           $dest = "v$([Convert]::ToInt32($hex.Substring(2,2),16))" }
          default        { $dest = "" }
        }
      }
      if($All -or $Regs.Count -eq 0 -or ($dest -and ($Regs -contains $dest))){
        Write-Output ("{0}`t{1}`t{2}`t{3}`t{4}" -f $off,$mn,$dest,$cm,$line)
      }
    }
  }
}
