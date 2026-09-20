Set-StrictMode -Version 2.0

$script:TransPosixMode = 'Explain'
$script:TransPosixCoreEnabled = $false
$script:TransPosixOptionalEnabled = $false
$script:TransPosixSavedAliases = @{}
$script:TransPosixCoreModule = $null
$script:TransPosixOptionalModule = $null

function ConvertTo-TransPosixLiteral {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '$null' }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function New-TransPosixTranslation {
    param($Source, $Name, $Code, [string[]]$Explanation, [string[]]$Warnings,
          [string[]]$Unsupported, $Plan)
    $canExecute = ($null -ne $Plan -and @($Unsupported).Count -eq 0)
    [pscustomobject]@{
        PSTypeName = 'TransPosix.Translation'; SourceCommand = $Source
        CommandName = $Name; PowerShellCommand = $Code
        Explanation = @($Explanation); Warnings = @($Warnings)
        Unsupported = @($Unsupported); CanExecute = $canExecute
        ExecutionPlan = $Plan; Executor = $null
    }
}

function Get-TransPosixCommandHelp {
    param([Parameter(Mandatory=$true)][ValidateSet('ls','cat','cp','mv','rm','mkdir','grep','find','head','tail','sort','date','tac','uniq','wc','which','touch')][string]$CommandName)
    if($CommandName -eq 'ls') { return @'
[TransPosix] ls - supported subset
Usage: ls [-a|--all] [-R|--recursive] [PATH ...]
Returns FileSystemInfo objects, which already contain detailed properties such as Mode, Length, LastWriteTime, LinkType, and Target. -a maps to Get-ChildItem -Force.
'@ }
    if($CommandName -eq 'cat') { return @'
[TransPosix] cat - supported subset
Usage: cat [-n|--number] [FILE ...]
Pipeline: PIPELINE | cat [-n]
-n returns objects with LineNumber and Line properties; numbering continues across files.
'@ }
    if($CommandName -eq 'cp') { return @'
[TransPosix] cp - supported subset
Usage: cp [-r|-R|--recursive] [-f|--force] SOURCE ... DESTINATION
Uses literal paths. Multiple sources require an existing destination directory.
'@ }
    if($CommandName -eq 'mv') { return @'
[TransPosix] mv - supported subset
Usage: mv [-f|--force] SOURCE ... DESTINATION
Uses literal paths. Multiple sources require an existing destination directory.
'@ }
    if($CommandName -eq 'rm') { return @'
[TransPosix] rm - supported subset
Usage: rm [-r|-R|--recursive] [-f|--force] PATH ...
Uses literal paths. -f ignores missing paths; recursive removal requires -r or -R.
'@ }
    if($CommandName -eq 'mkdir') { return @'
[TransPosix] mkdir - supported subset
Usage: mkdir [-p|--parents] DIRECTORY ...
-p accepts existing directories. PowerShell's New-Item already creates missing parent directories; -Force supplies the existing-directory behavior.
'@ }
    if($CommandName -eq 'grep') {
        return @'
[TransPosix] grep - supported subset

Usage:
  grep [options] PATTERN [PATH ...]
  PIPELINE | grep PATTERN

Supported options:
  -h, --help                 Show this help
  -i, --ignore-case          Ignore case
  -v, --invert-match         Return non-matching lines
  -l, --files-with-matches   Return only paths of matching files
  -r, -R, --recursive        Search directories recursively
  -F, --fixed-strings        Treat the pattern as a fixed string, not a regex

Examples:
  grep -Ri TODO .
  Get-Content app.log | grep ERROR

Not supported: -L, -c, -E, -w, -x, -m, -q, --include, --exclude
'@
    }
    if($CommandName -eq 'find') { return @'
[TransPosix] find - supported subset

Usage:
  find [PATH] [conditions]

Supported options and conditions:
  -h, --help       Show this help
  -type f|d        Select files or directories
  -name GLOB       Match a case-sensitive name glob
  -iname GLOB      Match a case-insensitive name glob
  -maxdepth N      Limit depth relative to the starting path
  -mtime N|+N|-N   Compare modification time in days
  -size N|+N|-N    Compare size (units: c, k, M, G)

Examples:
  find . -type f -name '*.xml'
  find . -type f -mtime -7

Conditions are combined with implicit AND only.
Not supported: -delete, -exec, -path, -mindepth, -o/-or, !/-not, parentheses
'@
    }
    if($CommandName -eq 'head') { return @'
[TransPosix] head - supported subset
Usage: head [-n NUM|--lines NUM] [FILE ...]
Pipeline: PIPELINE | head [-n NUM]
Default: 10 items. Byte options and negative counts are not supported.
'@ }
    if($CommandName -eq 'tail') { return @'
[TransPosix] tail - supported subset
Usage: tail [-n NUM|--lines NUM] [-f|--follow] [FILE ...]
Pipeline: PIPELINE | tail [-n NUM]
Default: 10 items. Follow is valid only for file input; byte options are unsupported.
'@ }
    if($CommandName -eq 'sort') { return @'
[TransPosix] sort - supported subset
Usage: sort [-r] [-n] [-u] [-t CHAR] [-k N] [FILE ...]
Pipeline extension: PIPELINE | sort PROPERTY
Options: --reverse, --numeric-sort, --unique, --field-separator CHAR
'@ }
    if($CommandName -eq 'date') { return @'
[TransPosix] date - supported subset
Usage: date [-u|--utc] [+FORMAT] [-d|--date EXPRESSION]
Expressions: now, today, tomorrow, yesterday, N days ago, N hours ago
Formats: %Y, %m, %d, %H, %M, %S, %%
'@
    }
    if($CommandName -eq 'tac') { return @'
[TransPosix] tac - supported subset
Usage: tac [FILE ...]
Pipeline: PIPELINE | tac
No options are supported. The complete input is buffered in memory.
'@ }
    if($CommandName -eq 'uniq') { return @'
[TransPosix] uniq - supported subset
Usage: uniq [-c|--count] [FILE]
Pipeline: PIPELINE | uniq [-c]
Only adjacent duplicate items are grouped.
'@ }
    if($CommandName -eq 'wc') { return @'
[TransPosix] wc - supported subset
Usage: wc [-l|--lines] [-w|--words] [FILE ...]
Pipeline: PIPELINE | wc [-l] [-w]
Without an option, both line and word counts are returned. Byte and character counts are unsupported.
'@ }
    if($CommandName -eq 'which') { return @'
[TransPosix] which - supported subset
Usage: which [-a|--all] COMMAND ...
Returns Get-Command objects. Without -a, only the first match is returned per name.
'@ }
    return @'
[TransPosix] touch - supported subset
Usage: touch [-c|--no-create] FILE ...
Creates missing files or updates LastWriteTime on existing files.
'@
}

function Split-TransPosixCommandLine {
    param([Parameter(Mandatory = $true)][string]$CommandLine)
    $items = New-Object System.Collections.ArrayList
    $token = New-Object System.Text.StringBuilder
    $quote = [char]0; $tokenStarted = $false
    for ($i = 0; $i -lt $CommandLine.Length; $i++) {
        $c = $CommandLine[$i]
        if ($quote -ne [char]0) {
            if ($c -eq $quote) { $quote = [char]0; $tokenStarted = $true }
            else { [void]$token.Append($c); $tokenStarted = $true }
            continue
        }
        if ($c -eq "'" -or $c -eq '"') { $quote = $c; $tokenStarted = $true; continue }
        if ([char]::IsWhiteSpace($c)) {
            if ($tokenStarted) { [void]$items.Add($token.ToString()); [void]$token.Clear(); $tokenStarted = $false }
            continue
        }
        [void]$token.Append($c); $tokenStarted = $true
    }
    if ($quote -ne [char]0) { throw '[TransPosix] Unclosed quote in command line.' }
    if ($tokenStarted) { [void]$items.Add($token.ToString()) }
    Write-Output -NoEnumerate $items.ToArray()
}

function Test-TransPosixUnsafeSyntax {
    param([string]$CommandLine)
    $quote = [char]0
    for ($i = 0; $i -lt $CommandLine.Length; $i++) {
        $c = $CommandLine[$i]
        if ($quote -ne [char]0) { if ($c -eq $quote) { $quote = [char]0 }; continue }
        if ($c -eq "'" -or $c -eq '"') { $quote = $c; continue }
        if ($c -eq "`n" -or $c -eq "`r" -or $c -eq '|' -or $c -eq ';' -or
            $c -eq '`' -or $c -eq '<' -or $c -eq '>') { return $true }
        if ($c -eq '$' -and $i + 1 -lt $CommandLine.Length -and $CommandLine[$i + 1] -eq '(') { return $true }
        if ($c -eq '&' -and $i + 1 -lt $CommandLine.Length -and $CommandLine[$i + 1] -eq '&') { return $true }
    }
    return $false
}

function ConvertFrom-PosixGrep {
    param([string]$Source, [string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()}
    if(@($Arguments).Count -eq 1 -and @('-h','--help') -contains $Arguments[0]) {
        $helpPlan=[pscustomobject]@{Operation='ShowHelp';CommandName='grep'}
        return New-TransPosixTranslation $Source 'grep' '# TransPosix grep help' @() @() @() $helpPlan
    }
    $ignore = $false; $invert = $false; $filesOnly = $false
    $recursive = $false; $fixed = $false; $operands = @(); $end = $false; $unsupported = @()
    foreach ($arg in $Arguments) {
        if (-not $end -and $arg -eq '--') { $end = $true; continue }
        if (-not $end -and $arg.StartsWith('--')) {
            switch ($arg) {
                '--ignore-case' { $ignore = $true } '--invert-match' { $invert = $true }
                '--files-with-matches' { $filesOnly = $true }
                '--recursive' { $recursive = $true } '--fixed-strings' { $fixed = $true }
                default { $unsupported += "[TransPosix] Unsupported grep option: $arg" }
            }; continue
        }
        if (-not $end -and $arg.Length -gt 1 -and $arg[0] -eq '-' -and $arg -ne '-') {
            foreach ($ch in $arg.Substring(1).ToCharArray()) {
                switch -CaseSensitive ($ch) {
                    'i' { $ignore = $true } 'v' { $invert = $true }
                    'l' { $filesOnly = $true } 'r' { $recursive = $true } 'R' { $recursive = $true }
                    'F' { $fixed = $true } default { $unsupported += "[TransPosix] Unsupported grep option: -$ch" }
                }
            }; continue
        }
        $operands += $arg
    }
    if ($operands.Count -lt 1) { $unsupported += '[TransPosix] grep requires a PATTERN.' }
    $pattern = if ($operands.Count) { $operands[0] } else { '' }
    [string[]]$paths = if (@($operands).Count -gt 1) { @($operands[1..(@($operands).Count - 1)]) } else { @() }
    if ($recursive -and ($null -eq $paths -or $paths.Length -eq 0)) { $paths = @('.') }
    $select = "Select-String -Pattern $(ConvertTo-TransPosixLiteral $pattern)"
    if (-not $ignore) { $select += ' -CaseSensitive' }
    if ($fixed) { $select += ' -SimpleMatch' }; if ($invert) { $select += ' -NotMatch' }
    if ($null -ne $paths -and $paths.Length -gt 0 -and -not $recursive) { $select += ' -LiteralPath ' + (($paths | ForEach-Object { ConvertTo-TransPosixLiteral $_ }) -join ', ') }
    if ($recursive) {
        $get = 'Get-ChildItem -LiteralPath ' + (($paths | ForEach-Object { ConvertTo-TransPosixLiteral $_ }) -join ', ') + ' -Recurse -File'
        $code = "$get |`n    $select"
    } else { $code = $select }
    if ($filesOnly) { $code += " |`n    Select-Object -ExpandProperty Path -Unique" }
    $explain = @('PowerShell uses Select-String for grep-like searches. TransPosix adds -CaseSensitive by default for POSIX grep behavior; -i uses the native case-insensitive default.', 'Every MatchInfo result already exposes its line number through the LineNumber property, so a separate -n option is unnecessary.')
    $plan = if (@($unsupported).Count) { $null } else { [pscustomobject]@{ Operation='Grep'; Pattern=$pattern; Paths=$paths; Recursive=$recursive; Fixed=$fixed; Invert=$invert; FilesOnly=$filesOnly; IgnoreCase=$ignore } }
    New-TransPosixTranslation $Source 'grep' $code $explain @('[TransPosix] This is not a complete GNU grep implementation.') $unsupported $plan
}

function ConvertFrom-PosixFind {
    param([string]$Source, [string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()}
    if(@($Arguments).Count -eq 1 -and @('-h','--help') -contains $Arguments[0]) {
        $helpPlan=[pscustomobject]@{Operation='ShowHelp';CommandName='find'}
        return New-TransPosixTranslation $Source 'find' '# TransPosix find help' @() @() @() $helpPlan
    }
    $path = '.'; $type = $null; $name = $null; $iname = $false; $maxDepth = $null
    $mtime = $null; $size = $null; $unsupported = @(); $i = 0
    if ($Arguments.Count -gt 0 -and -not $Arguments[0].StartsWith('-')) { $path = $Arguments[0]; $i = 1 }
    while ($i -lt $Arguments.Count) {
        $arg = $Arguments[$i]
        if ($arg -eq '--') { $unsupported += '[TransPosix] find does not support additional operands after --.'; break }
        if (@('-type','-name','-iname','-maxdepth','-mtime','-size') -contains $arg) {
            if ($i + 1 -ge $Arguments.Count) { $unsupported += "[TransPosix] $arg requires a value."; break }
            $value = $Arguments[$i + 1]; $i += 2
            switch ($arg) {
                '-type' { if (@('f','d') -notcontains $value) { $unsupported += '[TransPosix] -type supports only f or d.' } else { $type = $value } }
                '-name' { $name = $value } '-iname' { $name = $value; $iname = $true }
                '-maxdepth' { $parsed = 0; if (-not [int]::TryParse($value, [ref]$parsed) -or $parsed -lt 0) { $unsupported += '[TransPosix] -maxdepth requires a non-negative integer.' } else { $maxDepth = $parsed } }
                '-mtime' { if ($value -notmatch '^[+-]?\d+$') { $unsupported += '[TransPosix] -mtime requires an integer.' } else { $mtime = $value } }
                '-size' { if ($value -notmatch '^[+-]?\d+(c|k|M|G)?$') { $unsupported += '[TransPosix] -size requires an integer with an optional c, k, M, or G unit.' } else { $size = $value } }
            }; continue
        }
        $unsupported += "[TransPosix] Unsupported find expression or option: $arg"; $i++
    }
    $get = "Get-ChildItem -LiteralPath $(ConvertTo-TransPosixLiteral $path) -Recurse"
    if ($type -eq 'f') { $get += ' -File' } elseif ($type -eq 'd') { $get += ' -Directory' }
    if ($name -and -not $iname) { $get += " -Filter $(ConvertTo-TransPosixLiteral $name)" }
    $filters = @()
    if ($iname) { $filters += "`$_.Name -like $(ConvertTo-TransPosixLiteral $name)" }
    if ($maxDepth -ne $null) { $filters += "# Depth relative to the starting path -le $maxDepth (calculated cross-platform)" }
    if ($mtime) { $op = if ($mtime[0] -eq '+') {'-lt'} else {'-gt'}; $days = [int]$mtime.TrimStart('+','-'); $filters += "`$_.LastWriteTime $op (Get-Date).AddDays(-$days)" }
    if ($size) { $filters += "# Compare Length with ${size}" }
    $code = $get; if (@($filters).Count) { $code += " |`n    Where-Object { " + ($filters -join '; ') + ' }' }
    $explain = @('PowerShell uses Get-ChildItem for find-like enumeration. Conditions are combined with implicit AND.', 'Case behavior varies by platform, so -name uses an explicit case-sensitive comparison and -iname uses an explicit case-insensitive comparison.')
    $plan = if (@($unsupported).Count) { $null } else { [pscustomobject]@{ Operation='Find'; Path=$path; Type=$type; Name=$name; IgnoreCase=$iname; MaxDepth=$maxDepth; MTime=$mtime; Size=$size } }
    New-TransPosixTranslation $Source 'find' $code $explain @('[TransPosix] The complete POSIX find expression language is not supported.') $unsupported $plan
}

function ConvertFrom-PosixHead {
    param([string]$Source, [string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()}
    if(@($Arguments).Count -eq 1 -and @('-h','--help') -contains $Arguments[0]) {
        return New-TransPosixTranslation $Source 'head' '# TransPosix head help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='head'})
    }
    $lines=10; $paths=@(); $unsupported=@(); $i=0; $end=$false
    while($i -lt @($Arguments).Count) {
        $arg=$Arguments[$i]
        if(-not $end -and $arg -eq '--'){$end=$true;$i++;continue}
        if(-not $end -and ($arg -eq '-n' -or $arg -eq '--lines')) {
            if($i+1 -ge $Arguments.Count){$unsupported+='[TransPosix] head -n/--lines requires a value.';break}
            $value=$Arguments[$i+1];$i+=2; $parsed=0
            if(-not [int]::TryParse($value,[ref]$parsed) -or $parsed -lt 0){$unsupported+='[TransPosix] head line count must be a non-negative integer.'}else{$lines=$parsed};continue
        }
        if(-not $end -and $arg -match '^--lines=(.*)$'){$parsed=0;if(-not [int]::TryParse($Matches[1],[ref]$parsed)-or $parsed-lt 0){$unsupported+='[TransPosix] head line count must be a non-negative integer.'}else{$lines=$parsed};$i++;continue}
        if(-not $end -and $arg.StartsWith('-') -and $arg -ne '-'){$unsupported+="[TransPosix] Unsupported head option: $arg";$i++;continue}
        $paths+=$arg;$i++
    }
    $code=if(@($paths).Count){"Get-Content -LiteralPath " + (($paths|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ') + " -TotalCount $lines"}else{"Select-Object -First $lines"}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Head';Paths=[string[]]$paths;Lines=$lines}}
    New-TransPosixTranslation $Source 'head' $code @('File input uses Get-Content -TotalCount. Pipeline input uses Select-Object -First and preserves objects.') @('[TransPosix] Byte-oriented head options are not supported.') $unsupported $plan
}

function ConvertFrom-PosixTail {
    param([string]$Source, [string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()}
    if(@($Arguments).Count -eq 1 -and @('-h','--help') -contains $Arguments[0]) {
        return New-TransPosixTranslation $Source 'tail' '# TransPosix tail help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='tail'})
    }
    $lines=10;$follow=$false;$paths=@();$unsupported=@();$i=0;$end=$false
    while($i-lt @($Arguments).Count){$arg=$Arguments[$i];if(-not $end-and $arg-eq '--'){$end=$true;$i++;continue}
        if(-not $end-and ($arg-eq '-n'-or $arg-eq '--lines')){if($i+1-ge $Arguments.Count){$unsupported+='[TransPosix] tail -n/--lines requires a value.';break};$value=$Arguments[$i+1];$i+=2;$parsed=0;if(-not [int]::TryParse($value,[ref]$parsed)-or $parsed-lt 0){$unsupported+='[TransPosix] tail line count must be a non-negative integer.'}else{$lines=$parsed};continue}
        if(-not $end-and $arg-match '^--lines=(.*)$'){$parsed=0;if(-not [int]::TryParse($Matches[1],[ref]$parsed)-or $parsed-lt 0){$unsupported+='[TransPosix] tail line count must be a non-negative integer.'}else{$lines=$parsed};$i++;continue}
        if(-not $end-and @('-f','--follow')-contains $arg){$follow=$true;$i++;continue}
        if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-'){$unsupported+="[TransPosix] Unsupported tail option: $arg";$i++;continue};$paths+=$arg;$i++}
    if($follow-and @($paths).Count-eq 0){$unsupported+='[TransPosix] tail --follow requires file input and cannot be used with pipeline input.'}
    $code=if(@($paths).Count){"Get-Content -LiteralPath " + (($paths|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ') + " -Tail $lines" + $(if($follow){' -Wait'}else{''})}else{"Select-Object -Last $lines"}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Tail';Paths=[string[]]$paths;Lines=$lines;Follow=$follow}}
    New-TransPosixTranslation $Source 'tail' $code @('File input uses Get-Content -Tail. Pipeline input uses Select-Object -Last and preserves objects.') @('[TransPosix] Byte-oriented tail options and GNU-compatible file recreation tracking are not supported.') $unsupported $plan
}

function ConvertFrom-PosixSort {
    param([string]$Source,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()}
    if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){return New-TransPosixTranslation $Source 'sort' '# TransPosix sort help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='sort'})}
    $reverse=$false;$numeric=$false;$unique=$false;$key=$null;$separator=$null;$paths=@();$unsupported=@();$i=0;$end=$false
    while($i-lt @($Arguments).Count){$arg=$Arguments[$i];if(-not $end-and $arg-eq '--'){$end=$true;$i++;continue}
        if(-not $end-and @('-r','--reverse')-contains $arg){$reverse=$true;$i++;continue};if(-not $end-and @('-n','--numeric-sort')-contains $arg){$numeric=$true;$i++;continue};if(-not $end-and @('-u','--unique')-contains $arg){$unique=$true;$i++;continue}
        if(-not $end-and ($arg-eq '-k')){if($i+1-ge $Arguments.Count){$unsupported+='[TransPosix] sort -k requires a field number.';break};$value=$Arguments[$i+1];$i+=2;$parsed=0;if(-not [int]::TryParse($value,[ref]$parsed)-or $parsed-lt 1){$unsupported+='[TransPosix] sort -k supports one positive, 1-based field number.'}else{$key=$parsed};continue}
        if(-not $end-and $arg-match '^-k(.+)$'){$parsed=0;if(-not [int]::TryParse($Matches[1],[ref]$parsed)-or $parsed-lt 1){$unsupported+='[TransPosix] sort -k supports one positive, 1-based field number.'}else{$key=$parsed};$i++;continue}
        if(-not $end-and @('-t','--field-separator')-contains $arg){if($i+1-ge $Arguments.Count){$unsupported+='[TransPosix] sort -t/--field-separator requires one character.';break};$value=$Arguments[$i+1];$i+=2;if($value.Length-ne 1){$unsupported+='[TransPosix] sort field separator must be exactly one character.'}else{$separator=$value};continue}
        if(-not $end-and $arg-match '^-t(.+)$'){$value=$Matches[1];if($value.Length-ne 1){$unsupported+='[TransPosix] sort field separator must be exactly one character.'}else{$separator=$value};$i++;continue}
        if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-'){$unsupported+="[TransPosix] Unsupported sort option: $arg";$i++;continue};$paths+=$arg;$i++}
    if($null-ne $separator-and $null-eq $key){$unsupported+='[TransPosix] sort -t requires -k in this supported subset.'}
    $prefix=if(@($paths).Count){'Get-Content -LiteralPath '+(($paths|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ')+" |`n    "}else{''};$sort='Sort-Object'
    if($null-ne $key){$idx=$key-1;$sort+=" { (`$_ -split $(ConvertTo-TransPosixLiteral $separator), -1)[$idx]";if($numeric){$sort='Sort-Object { [double](($_ -split '+(ConvertTo-TransPosixLiteral $separator)+", -1)[$idx]) }"}else{$sort+=' }'}}elseif($numeric){$sort+=' { [double]$_ }'}
    if($reverse){$sort+=' -Descending'};if($unique){$sort+=' -Unique'};$code=$prefix+$sort
    $warnings=@('[TransPosix] This is not a complete POSIX sort implementation.');if($null-ne $key){$warnings+='[TransPosix] Lines missing the selected field sort as null. For CSV data, prefer Import-Csv | Sort-Object PropertyName.'}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Sort';Paths=[string[]]$paths;Reverse=$reverse;Numeric=$numeric;Unique=$unique;Key=$key;Separator=$separator;Property=$null}}
    New-TransPosixTranslation $Source 'sort' $code @('PowerShell uses Sort-Object. Pipeline object sorting by property is a TransPosix extension, not POSIX behavior.') $warnings $unsupported $plan
}

function ConvertTo-TransPosixDateFormat {
    param([string]$Format)
    $builder=New-Object System.Text.StringBuilder
    for($i=0;$i-lt $Format.Length;$i++){
        if($Format[$i]-ne '%'){[void]$builder.Append($Format[$i]);continue}
        if($i+1-ge $Format.Length){throw '[TransPosix] A trailing % in a date format is unsupported.'};$i++
        switch -CaseSensitive ($Format[$i]){'Y'{[void]$builder.Append('yyyy')}'m'{[void]$builder.Append('MM')}'d'{[void]$builder.Append('dd')}'H'{[void]$builder.Append('HH')}'M'{[void]$builder.Append('mm')}'S'{[void]$builder.Append('ss')}'%'{[void]$builder.Append('%')}default{throw "[TransPosix] Unsupported date format specifier: %$($Format[$i])"}}
    }
    $builder.ToString()
}

function ConvertFrom-PosixDate {
    param([string]$Source,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()}
    if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){return New-TransPosixTranslation $Source 'date' '# TransPosix date help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='date'})}
    $utc=$false;$format=$null;$expression=$null;$unsupported=@();$i=0
    while($i-lt @($Arguments).Count){$arg=$Arguments[$i]
        if(@('-u','--utc')-contains $arg){$utc=$true;$i++;continue}
        if($arg-eq '-d'-or $arg-eq '--date'){if($i+1-ge $Arguments.Count){$unsupported+='[TransPosix] date -d/--date requires an expression.';break};$expression=$Arguments[$i+1];$i+=2;continue}
        if($arg-match '^--date=(.*)$'){$expression=$Matches[1];$i++;continue}
        if($arg.StartsWith('+')){if($null-ne $format){$unsupported+='[TransPosix] date accepts only one format.'}else{$format=$arg.Substring(1)};$i++;continue}
        $unsupported+="[TransPosix] Unsupported date option or operand: $arg";$i++}
    $kind='Now';$amount=0
    if($null-ne $expression){switch($expression.ToLowerInvariant()){'now'{$kind='Now'}'today'{$kind='Today'}'tomorrow'{$kind='Days';$amount=1}'yesterday'{$kind='Days';$amount=-1}default{if($expression-match '^(\d+) days ago$'){$kind='Days';$amount=-[int]$Matches[1]}elseif($expression-match '^(\d+) hours ago$'){$kind='Hours';$amount=-[int]$Matches[1]}else{$unsupported+="[TransPosix] Unsupported date expression: $expression"}}}}
    $psFormat=$null;if($null-ne $format){try{$psFormat=ConvertTo-TransPosixDateFormat $format}catch{$unsupported+=$_.Exception.Message}}
    $base=if($utc){'(Get-Date).ToUniversalTime()'}else{'Get-Date'};switch($kind){'Today'{$code="($base).Date"}'Days'{$code="($base).AddDays($amount)"}'Hours'{$code="($base).AddHours($amount)"}default{$code=$base}}
    if($null-ne $psFormat){if($utc-or $kind-ne 'Now'){$code="($code).ToString($(ConvertTo-TransPosixLiteral $psFormat))"}else{$code="Get-Date -Format $(ConvertTo-TransPosixLiteral $psFormat)"}}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Date';Utc=$utc;Kind=$kind;Amount=$amount;Format=$psFormat}}
    New-TransPosixTranslation $Source 'date' $code @('PowerShell represents dates as DateTime objects. Formatting returns a string.', 'UTC uses (Get-Date).ToUniversalTime() for Windows PowerShell 5.1 compatibility.') @('[TransPosix] Only the documented date expressions and format specifiers are supported.') $unsupported $plan
}

function ConvertFrom-PosixTac {
    param([string]$Source,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()};if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){return New-TransPosixTranslation $Source 'tac' '# TransPosix tac help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='tac'})}
    $paths=@();$unsupported=@();$end=$false;foreach($arg in $Arguments){if(-not $end-and $arg-eq '--'){$end=$true;continue};if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-'){$unsupported+="[TransPosix] Unsupported tac option: $arg"}else{$paths+=$arg}}
    $inputCode=if(@($paths).Count){'Get-Content -LiteralPath '+(($paths|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ')}else{'<pipeline input>'};$code='$items = @('+$inputCode+")`n[array]::Reverse(`$items)`n`$items"
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Tac';Paths=[string[]]$paths}}
    New-TransPosixTranslation $Source 'tac' $code @('tac buffers all input, reverses the array, and preserves pipeline objects.') @('[TransPosix] Large input can consume substantial memory.') $unsupported $plan
}

function ConvertFrom-PosixUniq {
    param([string]$Source,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()};if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){return New-TransPosixTranslation $Source 'uniq' '# TransPosix uniq help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='uniq'})}
    $count=$false;$paths=@();$unsupported=@();$end=$false;foreach($arg in $Arguments){if(-not $end-and $arg-eq '--'){$end=$true;continue};if(-not $end-and @('-c','--count')-contains $arg){$count=$true;continue};if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-'){$unsupported+="[TransPosix] Unsupported uniq option: $arg"}else{$paths+=$arg}}
    if(@($paths).Count-gt 1){$unsupported+='[TransPosix] uniq supports at most one file in this version.'};$code=if(@($paths).Count){"Get-Content -LiteralPath $(ConvertTo-TransPosixLiteral $paths[0]) | # group adjacent equal items"}else{'# Group adjacent equal pipeline items'};if($count){$code+=' and return Count/Value objects'}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Uniq';Paths=[string[]]$paths;Count=$count}}
    New-TransPosixTranslation $Source 'uniq' $code @('Like POSIX uniq, only adjacent equal items are grouped. This is not whole-input deduplication.') @() $unsupported $plan
}

function ConvertFrom-PosixWc {
    param([string]$Source,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()};if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){return New-TransPosixTranslation $Source 'wc' '# TransPosix wc help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='wc'})}
    $lines=$false;$words=$false;$paths=@();$unsupported=@();$end=$false;foreach($arg in $Arguments){if(-not $end-and $arg-eq '--'){$end=$true;continue};if(-not $end-and @('-l','--lines')-contains $arg){$lines=$true;continue};if(-not $end-and @('-w','--words')-contains $arg){$words=$true;continue};if(-not $end-and $arg-match '^-[lw]{2}$'){foreach($ch in $arg.Substring(1).ToCharArray()){if($ch-eq 'l'){$lines=$true}else{$words=$true}};continue};if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-'){$unsupported+="[TransPosix] Unsupported wc option: $arg"}else{$paths+=$arg}}
    if(-not $lines-and -not $words){$lines=$true;$words=$true};$code=if(@($paths).Count){'Get-Content -LiteralPath '+(($paths|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ')+' | # count lines and words'}else{'# Count pipeline lines and words'}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Wc';Paths=[string[]]$paths;Lines=$lines;Words=$words}}
    New-TransPosixTranslation $Source 'wc' $code @('wc returns structured PowerShell objects instead of display-only count strings.') @('[TransPosix] Byte and character counts are intentionally unsupported to avoid encoding ambiguity.') $unsupported $plan
}

function ConvertFrom-PosixWhich {
    param([string]$Source,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()};if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){return New-TransPosixTranslation $Source 'which' '# TransPosix which help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='which'})}
    $all=$false;$names=@();$unsupported=@();$end=$false;foreach($arg in $Arguments){if(-not $end-and $arg-eq '--'){$end=$true;continue};if(-not $end-and @('-a','--all')-contains $arg){$all=$true;continue};if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-'){$unsupported+="[TransPosix] Unsupported which option: $arg"}else{$names+=$arg}};if(@($names).Count-eq 0){$unsupported+='[TransPosix] which requires at least one command name.'}
    $code='Get-Command '+(($names|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ');if(-not $all){$code+=' | Select-Object -First 1 # per command name'}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Which';Names=[string[]]$names;All=$all}}
    New-TransPosixTranslation $Source 'which' $code @('PowerShell uses Get-Command and preserves CommandInfo objects.') @() $unsupported $plan
}

function ConvertFrom-PosixTouch {
    param([string]$Source,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()};if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){return New-TransPosixTranslation $Source 'touch' '# TransPosix touch help' @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName='touch'})}
    $noCreate=$false;$paths=@();$unsupported=@();$end=$false;foreach($arg in $Arguments){if(-not $end-and $arg-eq '--'){$end=$true;continue};if(-not $end-and @('-c','--no-create')-contains $arg){$noCreate=$true;continue};if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-'){$unsupported+="[TransPosix] Unsupported touch option: $arg"}else{$paths+=$arg}};if(@($paths).Count-eq 0){$unsupported+='[TransPosix] touch requires at least one file path.'}
    $code='# For each literal path: create a missing file or set LastWriteTime to Get-Date';if($noCreate){$code+='; do not create missing files'}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation='Touch';Paths=[string[]]$paths;NoCreate=$noCreate}}
    New-TransPosixTranslation $Source 'touch' $code @('Existing files are updated through FileInfo.LastWriteTime. Missing files are created with New-Item.') @('[TransPosix] Symbolic-link-specific behavior and separate access/modification time options are unsupported.') $unsupported $plan
}

function ConvertFrom-PosixCoreFileCommand {
    param([string]$Source,[ValidateSet('ls','cat','cp','mv','rm','mkdir')][string]$CommandName,[string[]]$Arguments)
    if($null-eq $Arguments){$Arguments=@()}
    if(@($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]) {
        return New-TransPosixTranslation $Source $CommandName "# TransPosix $CommandName help" @() @() @() ([pscustomobject]@{Operation='ShowHelp';CommandName=$CommandName})
    }
    $all=$false;$recursive=$false;$force=$false;$number=$false;$parents=$false;$operands=@();$unsupported=@();$end=$false
    foreach($arg in $Arguments) {
        if(-not $end-and $arg-eq '--'){$end=$true;continue}
        if(-not $end-and $arg.StartsWith('-')-and $arg-ne '-') {
            $valid=$true
            if($arg.StartsWith('--')) {
                switch($arg) {
                    '--all' { if($CommandName-eq 'ls'){$all=$true}else{$valid=$false} }
                    '--recursive' { if(@('ls','cp','rm')-contains $CommandName){$recursive=$true}else{$valid=$false} }
                    '--force' { if(@('cp','mv','rm')-contains $CommandName){$force=$true}else{$valid=$false} }
                    '--number' { if($CommandName-eq 'cat'){$number=$true}else{$valid=$false} }
                    '--parents' { if($CommandName-eq 'mkdir'){$parents=$true}else{$valid=$false} }
                    default {$valid=$false}
                }
            } else {
                foreach($ch in $arg.Substring(1).ToCharArray()) {
                    switch -CaseSensitive ($ch) {
                        'a' {if($CommandName-eq 'ls'){$all=$true}else{$valid=$false}}
                        'R' {if(@('ls','cp','rm')-contains $CommandName){$recursive=$true}else{$valid=$false}}
                        'r' {if(@('cp','rm')-contains $CommandName){$recursive=$true}else{$valid=$false}}
                        'f' {if(@('cp','mv','rm')-contains $CommandName){$force=$true}else{$valid=$false}}
                        'n' {if($CommandName-eq 'cat'){$number=$true}else{$valid=$false}}
                        'p' {if($CommandName-eq 'mkdir'){$parents=$true}else{$valid=$false}}
                        default {$valid=$false}
                    }
                }
            }
            if(-not $valid){$unsupported+="[TransPosix] Unsupported $CommandName option: $arg"};continue
        }
        $operands+=$arg
    }
    if(@('cp','mv')-contains $CommandName-and @($operands).Count-lt 2){$unsupported+="[TransPosix] $CommandName requires at least one source and a destination."}
    if($CommandName-eq 'rm'-and @($operands).Count-eq 0){$unsupported+='[TransPosix] rm requires at least one path.'}
    if($CommandName-eq 'mkdir'-and @($operands).Count-eq 0){$unsupported+='[TransPosix] mkdir requires at least one directory path.'}
    $code=switch($CommandName) {
        'ls' {'Get-ChildItem -LiteralPath ' + $(if(@($operands).Count){($operands|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', '}else{"'.'"}) + $(if($all){' -Force'}else{''}) + $(if($recursive){' -Recurse'}else{''}) + $(if(-not $all){" |`n    Where-Object Name -NotLike '.*'"}else{''})}
        'cat' {'Get-Content' + $(if(@($operands).Count){' -LiteralPath '+(($operands|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ')}else{' # pipeline input'})}
        'cp' {'Copy-Item -LiteralPath <SOURCE> -Destination <DESTINATION>' + $(if($recursive){' -Recurse'}else{''}) + $(if($force){' -Force'}else{''})}
        'mv' {'Move-Item -LiteralPath <SOURCE> -Destination <DESTINATION>' + $(if($force){' -Force'}else{''})}
        'rm' {'Remove-Item -LiteralPath '+(($operands|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ') + $(if($recursive){' -Recurse'}else{''}) + $(if($force){' -Force'}else{''})}
        'mkdir' {'New-Item -ItemType Directory -Path '+(($operands|ForEach-Object{ConvertTo-TransPosixLiteral $_})-join ', ') + $(if($parents){' -Force'}else{''})}
    }
    $explanation=switch($CommandName){'ls'{@('PowerShell returns FileSystemInfo objects rather than preformatted text. TransPosix filters dot-prefixed names unless -a is used because Windows does not treat dot names as hidden.','Detailed information is already available through properties such as Mode, Length, LastWriteTime, LinkType, and Target.')} 'cat'{@('Get-Content reads files as a stream of lines. Pipeline input remains a stream of PowerShell objects.')} 'mkdir'{@('PowerShell uses New-Item -ItemType Directory. New-Item already creates missing parents; -p maps to -Force so existing directories are accepted.')} default {@("PowerShell uses $(@{cp='Copy-Item';mv='Move-Item';rm='Remove-Item'}[$CommandName]) with literal paths.")}}
    $plan=if(@($unsupported).Count){$null}else{[pscustomobject]@{Operation=$CommandName.Substring(0,1).ToUpper()+$CommandName.Substring(1);Paths=[string[]]$operands;All=$all;Recursive=$recursive;Force=$force;Number=$number;Parents=$parents}}
    New-TransPosixTranslation $Source $CommandName $code $explanation @('[TransPosix] This is an educational subset, not a complete POSIX implementation.') $unsupported $plan
}

function ConvertFrom-PosixCommand {
    [CmdletBinding()] param([Parameter(Mandatory=$true,Position=0)][string]$CommandLine)
    if (Test-TransPosixUnsafeSyntax $CommandLine) { throw '[TransPosix] Shell syntax such as pipelines, chaining, substitution, redirection, semicolons, or newlines was rejected for safety.' }
    [string[]]$tokens = Split-TransPosixCommandLine $CommandLine
    if ($tokens.Count -eq 0) { throw '[TransPosix] The command line is empty.' }
    $args = if ($tokens.Count -gt 1) { @($tokens[1..($tokens.Count - 1)]) } else { @() }
    switch -CaseSensitive ($tokens[0]) {
        'ls' { ConvertFrom-PosixCoreFileCommand $CommandLine ls $args }
        'cat' { ConvertFrom-PosixCoreFileCommand $CommandLine cat $args }
        'cp' { ConvertFrom-PosixCoreFileCommand $CommandLine cp $args }
        'mv' { ConvertFrom-PosixCoreFileCommand $CommandLine mv $args }
        'rm' { ConvertFrom-PosixCoreFileCommand $CommandLine rm $args }
        'mkdir' { ConvertFrom-PosixCoreFileCommand $CommandLine mkdir $args }
        'grep' { ConvertFrom-PosixGrep $CommandLine $args }
        'find' { ConvertFrom-PosixFind $CommandLine $args }
        'head' { ConvertFrom-PosixHead $CommandLine $args }
        'tail' { ConvertFrom-PosixTail $CommandLine $args }
        'sort' { ConvertFrom-PosixSort $CommandLine $args }
        'date' { ConvertFrom-PosixDate $CommandLine $args }
        'tac' { ConvertFrom-PosixTac $CommandLine $args }
        'uniq' { ConvertFrom-PosixUniq $CommandLine $args }
        'wc' { ConvertFrom-PosixWc $CommandLine $args }
        'which' { ConvertFrom-PosixWhich $CommandLine $args }
        'touch' { ConvertFrom-PosixTouch $CommandLine $args }
        default { New-TransPosixTranslation $CommandLine $tokens[0] '' @() @() @("[TransPosix] Unsupported command: $($tokens[0])") $null }
    }
}

function Get-TransPosixDepth {
    param([string]$Root, [string]$Child)
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $childPath = [System.IO.Path]::GetFullPath($Child)
    $relative = $childPath.Substring($rootPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not $relative) { return 0 }
    return @($relative -split '[\\/]').Count
}

function Invoke-TransPosixPlan {
    param($Plan, [object[]]$InputObject, [bool]$HasPipeline)
    if ($Plan.Operation -eq 'ShowHelp') { return Get-TransPosixCommandHelp $Plan.CommandName }
    if ($Plan.Operation -eq 'Ls') {
        $paths=if(@($Plan.Paths).Count){$Plan.Paths}else{@('.')};$params=@{LiteralPath=$paths}
        if($Plan.All){$params.Force=$true};if($Plan.Recursive){$params.Recurse=$true}
        $items=Get-ChildItem @params
        if(-not $Plan.All){$items=$items|Where-Object {$_.Name -notlike '.*'}}
        return $items
    }
    if ($Plan.Operation -eq 'Cat') {
        $items=if($HasPipeline){@($InputObject)}elseif(@($Plan.Paths).Count){@(Get-Content -LiteralPath $Plan.Paths)}else{throw '[TransPosix] cat requires a file path or pipeline input.'}
        if(-not $Plan.Number){return $items};$lineNumber=0;foreach($item in $items){$lineNumber++;[pscustomobject]@{PSTypeName='TransPosix.NumberedLine';LineNumber=$lineNumber;Line=$item}};return
    }
    if (@('Cp','Mv') -contains $Plan.Operation) {
        $paths=@($Plan.Paths);$destination=$paths[$paths.Count-1];$sources=@($paths[0..($paths.Count-2)])
        if($sources.Count-gt 1-and -not (Test-Path -LiteralPath $destination -PathType Container)){throw "[TransPosix] Multiple sources require an existing destination directory: $destination"}
        foreach($source in $sources){if(-not(Test-Path -LiteralPath $source)){throw "[TransPosix] Source path does not exist: $source"}}
        foreach($source in $sources){$params=@{LiteralPath=$source;Destination=$destination};if($Plan.Force){$params.Force=$true};if($Plan.Operation-eq 'Cp'){if($Plan.Recursive){$params.Recurse=$true};Copy-Item @params}else{Move-Item @params}};return
    }
    if ($Plan.Operation -eq 'Rm') {
        foreach($path in $Plan.Paths){if(-not(Test-Path -LiteralPath $path)){if($Plan.Force){continue};throw "[TransPosix] Path does not exist: $path"};$params=@{LiteralPath=$path};if($Plan.Recursive){$params.Recurse=$true};if($Plan.Force){$params.Force=$true};Remove-Item @params};return
    }
    if ($Plan.Operation -eq 'Mkdir') {
        foreach($path in $Plan.Paths){if((Test-Path -LiteralPath $path)-and -not $Plan.Parents){throw "[TransPosix] Directory already exists: $path"};$params=@{ItemType='Directory';Path=$path;ErrorAction='Stop'};if($Plan.Parents){$params.Force=$true};New-Item @params};return
    }
    if ($Plan.Operation -eq 'Grep') {
        $params = @{ Pattern=$Plan.Pattern }; if(-not $Plan.IgnoreCase){$params.CaseSensitive=$true};if ($Plan.Fixed) { $params.SimpleMatch=$true }; if ($Plan.Invert) { $params.NotMatch=$true }
        if ($HasPipeline) { $result = $InputObject | Select-String @params }
        elseif ($Plan.Recursive) { $result = Get-ChildItem -LiteralPath $Plan.Paths -Recurse -File | Select-String @params }
        elseif (@($Plan.Paths).Count) { $params.LiteralPath=$Plan.Paths; $result = Select-String @params }
        else { throw '[TransPosix] grep requires a file path or pipeline input.' }
        if ($Plan.FilesOnly) { return $result | Select-Object -ExpandProperty Path -Unique }; return $result
    }
    if ($Plan.Operation -eq 'Find') {
        if (-not (Test-Path -LiteralPath $Plan.Path)) { throw "[TransPosix] Starting path does not exist: $($Plan.Path)" }
        $items = Get-ChildItem -LiteralPath $Plan.Path -Recurse
        if ($Plan.Type -eq 'f') { $items = $items | Where-Object { -not $_.PSIsContainer } }
        if ($Plan.Type -eq 'd') { $items = $items | Where-Object { $_.PSIsContainer } }
        if ($Plan.Name) { if ($Plan.IgnoreCase) { $items = $items | Where-Object { $_.Name -like $Plan.Name } } else { $items = $items | Where-Object { $_.Name -clike $Plan.Name } } }
        if ($Plan.MaxDepth -ne $null) { $root=$Plan.Path; $depth=[int]$Plan.MaxDepth; $items = $items | Where-Object { (Get-TransPosixDepth $root $_.FullName) -le $depth } }
        if ($Plan.MTime) { $text=[string]$Plan.MTime; $days=[int]$text.TrimStart('+','-'); $cutoff=(Get-Date).AddDays(-$days); if ($text.StartsWith('+')) { $items=$items|Where-Object {$_.LastWriteTime -lt $cutoff} } else { $items=$items|Where-Object {$_.LastWriteTime -gt $cutoff} } }
        if ($Plan.Size) {
            $text=[string]$Plan.Size; $sign=''
            if ($text[0] -eq '+' -or $text[0] -eq '-') {$sign=$text[0];$text=$text.Substring(1)}
            $unit=$text.Substring($text.Length-1); $factor=1
            if ($unit -match '[ckMG]') {$text=$text.Substring(0,$text.Length-1); switch -CaseSensitive ($unit) {'c'{$factor=1}'k'{$factor=1KB}'M'{$factor=1MB}'G'{$factor=1GB}}}
            $bytes=[double]$text*$factor
            if($sign -eq '+'){$items=$items|Where-Object {-not $_.PSIsContainer -and $_.Length -gt $bytes}}
            elseif($sign -eq '-'){$items=$items|Where-Object {-not $_.PSIsContainer -and $_.Length -lt $bytes}}
            else{$items=$items|Where-Object {-not $_.PSIsContainer -and $_.Length -eq $bytes}}
        }
        return $items
    }
    if ($Plan.Operation -eq 'Head') {
        if($HasPipeline){return $InputObject|Select-Object -First $Plan.Lines}
        if(@($Plan.Paths).Count){return Get-Content -LiteralPath $Plan.Paths -TotalCount $Plan.Lines}
        throw '[TransPosix] head requires a file path or pipeline input.'
    }
    if ($Plan.Operation -eq 'Tail') {
        if($HasPipeline){if($Plan.Follow){throw '[TransPosix] tail --follow cannot be used with pipeline input.'};return $InputObject|Select-Object -Last $Plan.Lines}
        if(@($Plan.Paths).Count){$p=@{LiteralPath=$Plan.Paths;Tail=$Plan.Lines};if($Plan.Follow){$p.Wait=$true};return Get-Content @p}
        throw '[TransPosix] tail requires a file path or pipeline input.'
    }
    if ($Plan.Operation -eq 'Sort') {
        $items=if($HasPipeline){@($InputObject)}elseif(@($Plan.Paths).Count){@(Get-Content -LiteralPath $Plan.Paths)}else{@()}
        if(-not $HasPipeline-and @($Plan.Paths).Count-eq 0){throw '[TransPosix] sort requires a file path or pipeline input.'}
        $sortParams=@{};if($Plan.Reverse){$sortParams.Descending=$true};if($Plan.Unique){$sortParams.Unique=$true}
        if($Plan.Property){return $items|Sort-Object -Property $Plan.Property @sortParams}
        if($null-ne $Plan.Key){$index=[int]$Plan.Key-1;$pattern=[regex]::Escape([string]$Plan.Separator)
            if($Plan.Numeric){foreach($item in $items){$fields=@([regex]::Split([string]$item,$pattern));$number=0.0;if($index-ge $fields.Count-or -not [double]::TryParse($fields[$index],[ref]$number)){throw "[TransPosix] Cannot numerically sort value or missing field in: $item"}};return $items|Sort-Object -Property { [double](@([regex]::Split([string]$_,$pattern))[$index]) } @sortParams}
            return $items|Sort-Object -Property { $fields=@([regex]::Split([string]$_,$pattern));if($index-lt $fields.Count){$fields[$index]}else{$null} } @sortParams
        }
        if($Plan.Numeric){foreach($item in $items){$number=0.0;if(-not [double]::TryParse([string]$item,[ref]$number)){throw "[TransPosix] Cannot numerically sort value: $item"}};return $items|Sort-Object -Property {[double]$_} @sortParams}
        return $items|Sort-Object @sortParams
    }
    if ($Plan.Operation -eq 'Date') {
        $value=Get-Date;if($Plan.Utc){$value=$value.ToUniversalTime()}
        switch($Plan.Kind){'Today'{$value=$value.Date}'Days'{$value=$value.AddDays([double]$Plan.Amount)}'Hours'{$value=$value.AddHours([double]$Plan.Amount)}}
        if($null-ne $Plan.Format){return $value.ToString($Plan.Format)};return $value
    }
    if ($Plan.Operation -eq 'Tac') {
        $items=if($HasPipeline){@($InputObject)}elseif(@($Plan.Paths).Count){@(Get-Content -LiteralPath $Plan.Paths)}else{throw '[TransPosix] tac requires a file path or pipeline input.'};[array]::Reverse($items);return $items
    }
    if ($Plan.Operation -eq 'Uniq') {
        $items=if($HasPipeline){@($InputObject)}elseif(@($Plan.Paths).Count){@(Get-Content -LiteralPath $Plan.Paths[0])}else{throw '[TransPosix] uniq requires a file path or pipeline input.'};if($items.Count-eq 0){return}
        $current=$items[0];$count=1
        for($i=1;$i-lt $items.Count;$i++){if([object]::Equals($current,$items[$i])){$count++}else{if($Plan.Count){[pscustomobject]@{PSTypeName='TransPosix.UniqCount';Count=$count;Value=$current}}else{$current};$current=$items[$i];$count=1}}
        if($Plan.Count){[pscustomobject]@{PSTypeName='TransPosix.UniqCount';Count=$count;Value=$current}}else{$current};return
    }
    if ($Plan.Operation -eq 'Wc') {
        $sets=@();if($HasPipeline){$sets+=,[pscustomobject]@{File=$null;Items=@($InputObject)}}elseif(@($Plan.Paths).Count){foreach($path in $Plan.Paths){$sets+=,[pscustomobject]@{File=$path;Items=@(Get-Content -LiteralPath $path)}}}else{throw '[TransPosix] wc requires a file path or pipeline input.'}
        foreach($set in $sets){$wordCount=0;if($Plan.Words){foreach($line in $set.Items){$text=[string]$line;if(-not [string]::IsNullOrWhiteSpace($text)){$wordCount+=@($text.Trim()-split '\s+').Count}}};$result=[ordered]@{PSTypeName='TransPosix.WordCount';File=$set.File};if($Plan.Lines){$result.Lines=@($set.Items).Count};if($Plan.Words){$result.Words=$wordCount};[pscustomobject]$result};return
    }
    if ($Plan.Operation -eq 'Which') {
        foreach($name in $Plan.Names){$matches=@(Get-Command $name -All -ErrorAction SilentlyContinue);if($Plan.All){$matches}else{$matches|Select-Object -First 1}};return
    }
    if ($Plan.Operation -eq 'Touch') {
        $now=Get-Date;foreach($path in $Plan.Paths){if(Test-Path -LiteralPath $path -PathType Leaf){$item=Get-Item -LiteralPath $path;$item.LastWriteTime=$now;$item}elseif(-not $Plan.NoCreate){New-Item -ItemType File -Path $path -Force}};return
    }
}

function Format-TransPosixTranslation {
    param($Translation, [string]$Mode)
    if ($Mode -eq 'Quiet') { return }
    if ($Mode -eq 'Compact') { Write-Information "[TransPosix] $($Translation.PowerShellCommand)" -InformationAction Continue; return }
    Write-Information "[TransPosix] POSIX: $($Translation.SourceCommand)" -InformationAction Continue
    Write-Information "[TransPosix] PowerShell:`n$($Translation.PowerShellCommand)" -InformationAction Continue
    foreach ($line in $Translation.Explanation) { Write-Information "[TransPosix] Explanation: $line" -InformationAction Continue }
    foreach ($line in $Translation.Warnings) { Write-Warning $line }
}

function Wait-TransPosixExplainExecution {
    param([string]$Mode)
    if($Mode -eq 'Explain') {
        $null = Read-Host '[TransPosix] Press Enter to run the translated command and display its results'
    }
}

function Invoke-TransPosix {
    [CmdletBinding(DefaultParameterSetName='Default')]
    param([Parameter(Mandatory=$true,Position=0)][string]$CommandLine, [switch]$TranslateOnly,
          [switch]$Explain, [switch]$Compact, [switch]$Quiet)
    $selected = @($Explain,$Compact,$Quiet | Where-Object { $_.IsPresent }).Count
    if ($selected -gt 1) { throw '[TransPosix] -Explain, -Compact, and -Quiet are mutually exclusive.' }
    $mode=$script:TransPosixMode; if($Explain){$mode='Explain'}elseif($Compact){$mode='Compact'}elseif($Quiet){$mode='Quiet'}
    $translation=ConvertFrom-PosixCommand $CommandLine
    if($translation.CanExecute -and $translation.ExecutionPlan.Operation -eq 'ShowHelp') {
        return Invoke-TransPosixPlan $translation.ExecutionPlan @() $false
    }
    Format-TransPosixTranslation $translation $mode
    if (-not $translation.CanExecute) { throw ($translation.Unsupported -join ' ') }
    if ($TranslateOnly) { return $translation }
    Wait-TransPosixExplainExecution $mode
    Invoke-TransPosixPlan $translation.ExecutionPlan @() $false
}

function Set-TransPosixMode { [CmdletBinding()]param([Parameter(Mandatory=$true,Position=0)][ValidateSet('Explain','Compact','Quiet')][string]$Mode) $script:TransPosixMode=$Mode }
function Get-TransPosixMode { [CmdletBinding()]param() $script:TransPosixMode }

function Invoke-TransPosixCoreFileDirect {
    param([string]$CommandName,[string[]]$Arguments,[object[]]$InputObject,[bool]$HasPipeline)
    if($null-ne $Arguments-and @($Arguments).Count-eq 1-and @('-h','--help')-contains $Arguments[0]){Get-TransPosixCommandHelp $CommandName;return}
    $t=ConvertFrom-PosixCoreFileCommand "$CommandName (direct PowerShell invocation)" $CommandName $Arguments
    if(-not $t.CanExecute){throw($t.Unsupported-join ' ')}
    Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan $InputObject $HasPipeline
}
function Invoke-TransPosixLsDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Alias('a')][switch]$All,[Alias('R')][switch]$Recursive,[Alias('h')][switch]$Help)
    if($Help){Get-TransPosixCommandHelp ls;return};$args=@();if($All){$args+='-a'};if($Recursive){$args+='-R'};if($Path){$args+=@($Path)};Invoke-TransPosixCoreFileDirect ls $args @() $false
}
function Invoke-TransPosixCatDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Alias('n')][switch]$Number,[Parameter(ValueFromPipeline=$true)][object]$InputObject,[Alias('h')][switch]$Help)
    begin{$all=@();$has=$false};process{if($PSBoundParameters.ContainsKey('InputObject')){$has=$true;$all+=$InputObject}};end{if($Help){Get-TransPosixCommandHelp cat;return};$args=@();if($Number){$args+='-n'};if($Path){$args+=@($Path)};Invoke-TransPosixCoreFileDirect cat $args $all $has}
}
function Invoke-TransPosixCpDirect {
    [CmdletBinding()]param([Alias('r')][switch]$Recursive,[Alias('f')][switch]$Force,[Alias('h')][switch]$Help,[Parameter(Position=0,ValueFromRemainingArguments=$true)][string[]]$Path)
    if($Help){Get-TransPosixCommandHelp cp;return};$args=@();if($Recursive){$args+='-r'};if($Force){$args+='-f'};if($Path){$args+=@($Path)};Invoke-TransPosixCoreFileDirect cp $args @() $false
}
function Invoke-TransPosixMvDirect {
    [CmdletBinding()]param([Alias('f')][switch]$Force,[Alias('h')][switch]$Help,[Parameter(Position=0,ValueFromRemainingArguments=$true)][string[]]$Path)
    if($Help){Get-TransPosixCommandHelp mv;return};$args=@();if($Force){$args+='-f'};if($Path){$args+=@($Path)};Invoke-TransPosixCoreFileDirect mv $args @() $false
}
function Invoke-TransPosixRmDirect {
    [CmdletBinding()]param([Alias('r')][switch]$Recursive,[Alias('f')][switch]$Force,[Alias('h')][switch]$Help,[Parameter(Position=0,ValueFromRemainingArguments=$true)][string[]]$Path)
    if($Help){Get-TransPosixCommandHelp rm;return};$args=@();if($Recursive){$args+='-r'};if($Force){$args+='-f'};if($Path){$args+=@($Path)};Invoke-TransPosixCoreFileDirect rm $args @() $false
}
function Invoke-TransPosixMkdirDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Alias('p')][switch]$Parents,[Alias('h')][switch]$Help)
    if($Help){Get-TransPosixCommandHelp mkdir;return};$args=@();if($Parents){$args+='-p'};if($Path){$args+=@($Path)};Invoke-TransPosixCoreFileDirect mkdir $args @() $false
}

function Invoke-TransPosixGrepDirect {
    [CmdletBinding()] param([Parameter(Position=0)][string]$Pattern, [Parameter(Position=1)][string[]]$Path,
        [Parameter(ValueFromPipeline=$true)][object]$InputObject, [switch]$IgnoreCase,[switch]$InvertMatch,
        [switch]$FilesWithMatches,[switch]$Recursive,[switch]$FixedStrings,[Alias('h')][switch]$Help)
    begin { $all=@(); $has=$false }
    process {
        if($PSBoundParameters.ContainsKey('InputObject')) {
            $has=$true
            $all += $InputObject
        }
    }
    end {
        if($Help) { Get-TransPosixCommandHelp grep; return }
        if(-not $PSBoundParameters.ContainsKey('Pattern')) { throw '[TransPosix] grep requires a PATTERN. Use -h to display help.' }
        $arguments = @()
        if($IgnoreCase){$arguments += '-i'}
        if($InvertMatch){$arguments += '-v'}
        if($FilesWithMatches){$arguments += '-l'}
        if($Recursive){$arguments += '-R'}
        if($FixedStrings){$arguments += '-F'}
        $arguments += $Pattern
        if($null -ne $Path -and @($Path).Count){$arguments += @($Path)}
        $translation = ConvertFrom-PosixGrep 'grep (direct PowerShell invocation)' $arguments
        if($translation.ExecutionPlan.Operation -eq 'ShowHelp') {
            Invoke-TransPosixPlan $translation.ExecutionPlan @() $false
            return
        }
        Format-TransPosixTranslation $translation $script:TransPosixMode
        Wait-TransPosixExplainExecution $script:TransPosixMode
        Invoke-TransPosixPlan $translation.ExecutionPlan $all $has
    }
}
function Invoke-TransPosixFindDirect {
    [CmdletBinding()] param([Parameter(Position=0)][string]$Path='.',[ValidateSet('f','d')][string]$Type,[string]$Name,[string]$IName,[ValidateRange(0,2147483647)][int]$MaxDepth,[string]$MTime,[string]$Size,[Alias('h')][switch]$Help)
    if($Help) { Get-TransPosixCommandHelp find; return }
    $arguments = @($Path)
    if($Type){$arguments += @('-type',$Type)}
    if($Name){$arguments += @('-name',$Name)}
    if($IName){$arguments += @('-iname',$IName)}
    if($PSBoundParameters.ContainsKey('MaxDepth')){$arguments += @('-maxdepth',[string]$MaxDepth)}
    if($PSBoundParameters.ContainsKey('MTime')){$arguments += @('-mtime',$MTime)}
    if($PSBoundParameters.ContainsKey('Size')){$arguments += @('-size',$Size)}
    $translation = ConvertFrom-PosixFind 'find (direct PowerShell invocation)' $arguments
    if(-not $translation.CanExecute) { throw ($translation.Unsupported -join ' ') }
    if($translation.ExecutionPlan.Operation -eq 'ShowHelp') {
        Invoke-TransPosixPlan $translation.ExecutionPlan @() $false
        return
    }
    Format-TransPosixTranslation $translation $script:TransPosixMode
    Wait-TransPosixExplainExecution $script:TransPosixMode
    Invoke-TransPosixPlan $translation.ExecutionPlan @() $false
}

function Invoke-TransPosixHeadDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Alias('n')][ValidateRange(0,2147483647)][int]$Lines=10,[Parameter(ValueFromPipeline=$true)][object]$InputObject,[Alias('h')][switch]$Help)
    begin{$all=@();$has=$false}
    process{if($PSBoundParameters.ContainsKey('InputObject')){$has=$true;$all+=$InputObject}}
    end{
        if($Help-or ($null-ne $Path-and @($Path).Count-eq 1-and @('-h','--help')-contains $Path[0])){Get-TransPosixCommandHelp head;return}
        $args=@('-n',[string]$Lines);if($null-ne $Path){$args+=@($Path)};$t=ConvertFrom-PosixHead 'head (direct PowerShell invocation)' $args
        Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan $all $has
    }
}

function Invoke-TransPosixTailDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Alias('n')][ValidateRange(0,2147483647)][int]$Lines=10,[Alias('f')][switch]$Follow,[Parameter(ValueFromPipeline=$true)][object]$InputObject,[Alias('h')][switch]$Help)
    begin{$all=@();$has=$false}
    process{if($PSBoundParameters.ContainsKey('InputObject')){$has=$true;$all+=$InputObject}}
    end{
        if($Help-or ($null-ne $Path-and @($Path).Count-eq 1-and @('-h','--help')-contains $Path[0])){Get-TransPosixCommandHelp tail;return}
        if($Follow-and $has){throw '[TransPosix] tail --follow cannot be used with pipeline input.'}
        $args=@('-n',[string]$Lines);if($Follow){$args+='-f'};if($null-ne $Path){$args+=@($Path)};$t=ConvertFrom-PosixTail 'tail (direct PowerShell invocation)' $args
        if(-not $t.CanExecute){throw ($t.Unsupported-join ' ')};Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan $all $has
    }
}

function Invoke-TransPosixSortDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string]$KeyOrPath,[Alias('r')][switch]$Reverse,[Alias('n')][switch]$NumericSort,[Alias('u')][switch]$Unique,[Alias('k')][int]$Key,[Alias('t')][string]$FieldSeparator,[Parameter(ValueFromPipeline=$true)][object]$InputObject,[Alias('h')][switch]$Help)
    begin{$all=@();$has=$false}
    process{if($PSBoundParameters.ContainsKey('InputObject')){$has=$true;$all+=$InputObject}}
    end{
        if($Help-or ($KeyOrPath-and @('-h','--help')-contains $KeyOrPath)){Get-TransPosixCommandHelp sort;return}
        $args=@();if($Reverse){$args+='-r'};if($NumericSort){$args+='-n'};if($Unique){$args+='-u'};if($PSBoundParameters.ContainsKey('Key')){$args+=@('-k',[string]$Key)};if($PSBoundParameters.ContainsKey('FieldSeparator')){$args+=@('-t',$FieldSeparator)}
        if(-not $has-and $KeyOrPath){$args+=$KeyOrPath};$t=ConvertFrom-PosixSort 'sort (direct PowerShell invocation)' $args;if(-not $t.CanExecute){throw ($t.Unsupported-join ' ')}
        if($has-and $KeyOrPath-and -not $PSBoundParameters.ContainsKey('Key')){$t.ExecutionPlan.Property=$KeyOrPath;$t.PowerShellCommand="Sort-Object $(ConvertTo-TransPosixLiteral $KeyOrPath)";$t.Warnings+= '[TransPosix] Sorting pipeline objects by property is a TransPosix extension.'}
        Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan $all $has
    }
}

function Invoke-TransPosixDateDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Argument,[Alias('u')][switch]$Utc,[Alias('d')][string]$DateExpression,[Alias('h')][switch]$Help)
    if($Help-or ($Argument-and @('-h','--help')-contains $Argument)){Get-TransPosixCommandHelp date;return}
    $args=@();if($Utc){$args+='-u'};if($PSBoundParameters.ContainsKey('DateExpression')){$args+=@('-d',$DateExpression)};if($Argument){$args+=$Argument}
    $t=ConvertFrom-PosixDate 'date (direct PowerShell invocation)' $args;if(-not $t.CanExecute){throw ($t.Unsupported-join ' ')};Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan @() $false
}

function Invoke-TransPosixTacDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Parameter(ValueFromPipeline=$true)][object]$InputObject,[Alias('h')][switch]$Help)
    begin{$all=@();$has=$false};process{if($PSBoundParameters.ContainsKey('InputObject')){$has=$true;$all+=$InputObject}};end{if($Help-or($null-ne $Path-and @($Path).Count-eq 1-and @('-h','--help')-contains $Path[0])){Get-TransPosixCommandHelp tac;return};$args=@();if($null-ne $Path){$args+=@($Path)};$t=ConvertFrom-PosixTac 'tac (direct PowerShell invocation)' $args;Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan $all $has}
}
function Invoke-TransPosixUniqDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path,[Alias('c')][switch]$Count,[Parameter(ValueFromPipeline=$true)][object]$InputObject,[Alias('h')][switch]$Help)
    begin{$all=@();$has=$false};process{if($PSBoundParameters.ContainsKey('InputObject')){$has=$true;$all+=$InputObject}};end{if($Help-or($Path-and @('-h','--help')-contains $Path)){Get-TransPosixCommandHelp uniq;return};$args=@();if($Count){$args+='-c'};if($Path){$args+=$Path};$t=ConvertFrom-PosixUniq 'uniq (direct PowerShell invocation)' $args;if(-not $t.CanExecute){throw($t.Unsupported-join ' ')};Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan $all $has}
}
function Invoke-TransPosixWcDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Alias('l')][switch]$Lines,[Alias('w')][switch]$Words,[Parameter(ValueFromPipeline=$true)][object]$InputObject,[Alias('h')][switch]$Help)
    begin{$all=@();$has=$false};process{if($PSBoundParameters.ContainsKey('InputObject')){$has=$true;$all+=$InputObject}};end{if($Help-or($null-ne $Path-and @($Path).Count-eq 1-and @('-h','--help')-contains $Path[0])){Get-TransPosixCommandHelp wc;return};$args=@();if($Lines){$args+='-l'};if($Words){$args+='-w'};if($null-ne $Path){$args+=@($Path)};$t=ConvertFrom-PosixWc 'wc (direct PowerShell invocation)' $args;Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan $all $has}
}
function Invoke-TransPosixWhichDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Name,[Alias('a')][switch]$All,[Alias('h')][switch]$Help)
    if($Help-or($null-ne $Name-and @($Name).Count-eq 1-and @('-h','--help')-contains $Name[0])){Get-TransPosixCommandHelp which;return};$args=@();if($All){$args+='-a'};if($null-ne $Name){$args+=@($Name)};$t=ConvertFrom-PosixWhich 'which (direct PowerShell invocation)' $args;if(-not $t.CanExecute){throw($t.Unsupported-join ' ')};Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan @() $false
}
function Invoke-TransPosixTouchDirect {
    [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[Alias('c')][switch]$NoCreate,[Alias('h')][switch]$Help)
    if($Help-or($null-ne $Path-and @($Path).Count-eq 1-and @('-h','--help')-contains $Path[0])){Get-TransPosixCommandHelp touch;return};$args=@();if($NoCreate){$args+='-c'};if($null-ne $Path){$args+=@($Path)};$t=ConvertFrom-PosixTouch 'touch (direct PowerShell invocation)' $args;if(-not $t.CanExecute){throw($t.Unsupported-join ' ')};Format-TransPosixTranslation $t $script:TransPosixMode;Wait-TransPosixExplainExecution $script:TransPosixMode;Invoke-TransPosixPlan $t.ExecutionPlan @() $false
}

function Enable-TransPosixCommandGroup {
    param([string]$Group,[string[]]$Names,[string]$ModuleFile)
    $enabled=if($Group-eq 'Core'){$script:TransPosixCoreEnabled}else{$script:TransPosixOptionalEnabled};if($enabled){return}
    # Command discovery reads the global preference, even inside a module function.
    $autoLoadingVariable=Get-Variable PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue
    if($null-ne $autoLoadingVariable){$autoLoadingValue=$autoLoadingVariable.Value}
    try {
        $global:PSModuleAutoLoadingPreference='None'
        foreach($name in $Names) {
            $existing=Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if($existing){Write-Warning "[TransPosix] '$name' conflicts with an existing $($existing.CommandType) command. Disabling TransPosix commands will reveal the original command again."}
            elseif($name-eq 'date'-and (Get-Command Get-Date -ErrorAction SilentlyContinue)) {
                Write-Warning "[TransPosix] 'date' implicitly resolves to the Get-Date cmdlet through PowerShell's default Get- verb. Disabling TransPosix commands will reveal that original behavior again."
            }
        }
    }
    finally {
        if($null-ne $autoLoadingVariable){$global:PSModuleAutoLoadingPreference=$autoLoadingValue}
        else{Remove-Variable PSModuleAutoLoadingPreference -Scope Global}
    }
    foreach($name in $Names){$alias=Get-Alias $name -ErrorAction SilentlyContinue;if($alias-and -not $script:TransPosixSavedAliases.ContainsKey($name)){$script:TransPosixSavedAliases[$name]=[pscustomobject]@{Definition=$alias.Definition;Description=$alias.Description;Options=$alias.Options}}}
    $module=Import-Module (Join-Path $PSScriptRoot $ModuleFile) -Global -Force -DisableNameChecking -PassThru
    if($Group-eq 'Core'){$script:TransPosixCoreModule=$module;$script:TransPosixCoreEnabled=$true}else{$script:TransPosixOptionalModule=$module;$script:TransPosixOptionalEnabled=$true}
}
function Enable-TransPosixCoreCommands {
    [CmdletBinding(SupportsShouldProcess=$true)]param()
    if($PSCmdlet.ShouldProcess('global session','Enable TransPosix core commands')){
        Enable-TransPosixCommandGroup Core @('ls','cat','cp','mv','rm','mkdir','sort','date') 'TransPosix.CoreCommands.psm1'
        $map=@{ls='TransPosixLsCommand';cat='TransPosixCatCommand';cp='TransPosixCpCommand';mv='TransPosixMvCommand';rm='TransPosixRmCommand';sort='TransPosixSortCommand'}
        foreach($entry in $map.GetEnumerator()){$options=[System.Management.Automation.ScopedItemOptions]::None;if($script:TransPosixSavedAliases.ContainsKey($entry.Key)){$options=$script:TransPosixSavedAliases[$entry.Key].Options};Set-Alias -Name $entry.Key -Value $entry.Value -Scope Global -Option $options -Force}
    }
}
function Enable-TransPosixOptionalCommands {
    [CmdletBinding(SupportsShouldProcess=$true)]param()
    if($PSCmdlet.ShouldProcess('global session','Enable TransPosix optional commands')){Enable-TransPosixCommandGroup Optional @('grep','find','head','tail','tac','uniq','wc','which','touch') 'TransPosix.OptionalCommands.psm1'}
}
function Disable-TransPosixCommands {
    [CmdletBinding(SupportsShouldProcess=$true)]param()
    $loadedCommandModules=@(Get-Module 'TransPosix.CoreCommands','TransPosix.OptionalCommands')
    if(-not $script:TransPosixCoreEnabled-and -not $script:TransPosixOptionalEnabled-and $loadedCommandModules.Count-eq 0){return}
    if($PSCmdlet.ShouldProcess('global session','Disable POSIX-style commands')) {
        $hadCore=$script:TransPosixCoreEnabled-or $null-ne ($loadedCommandModules|Where-Object Name -eq 'TransPosix.CoreCommands'|Select-Object -First 1)-or $script:TransPosixSavedAliases.Count-gt 0
        if($script:TransPosixSavedAliases.Count-eq 0){$core=$loadedCommandModules|Where-Object Name -eq 'TransPosix.CoreCommands'|Select-Object -First 1;if($core){$script:TransPosixSavedAliases=& $core {$script:OriginalAliases}}}
        foreach($commandModule in $loadedCommandModules){Remove-Module $commandModule -Force -ErrorAction SilentlyContinue}
        if($hadCore){foreach($name in @('ls','cat','cp','mv','rm','sort')){if($script:TransPosixSavedAliases.ContainsKey($name)){$saved=$script:TransPosixSavedAliases[$name];Set-Alias -Name $name -Value $saved.Definition -Description $saved.Description -Option $saved.Options -Scope Global -Force}else{Remove-Item -LiteralPath ("Alias:"+$name) -Force -ErrorAction SilentlyContinue}}}
        $script:TransPosixSavedAliases=@{};$script:TransPosixCoreModule=$null;$script:TransPosixOptionalModule=$null;$script:TransPosixCoreEnabled=$false;$script:TransPosixOptionalEnabled=$false
    }
}

Export-ModuleMember -Function ConvertFrom-PosixCommand,Invoke-TransPosix,Set-TransPosixMode,Get-TransPosixMode,Enable-TransPosixCoreCommands,Enable-TransPosixOptionalCommands,Disable-TransPosixCommands
