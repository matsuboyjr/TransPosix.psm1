# TransPosix

TransPosix is an educational translation module for users moving from familiar POSIX/GNU commands to native PowerShell cmdlets and the object pipeline. It is not a compatibility layer or a shell, and it does not depend on external binaries, WSL, Git Bash, or Cygwin.

The current implementation includes a deliberately limited parser, translation and display infrastructure, safe structured `ExecutionPlan` execution, and support for `ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`, `grep`, `find`, `head`, `tail`, `sort`, `date`, `tac`, `uniq`, `wc`, `which`, and `touch`. It targets Windows PowerShell 5.1 on Windows and PowerShell 7.4 or later on Windows, Linux, and macOS. It does not use PowerShell 7-only syntax.

## Installation and basic use

Copy this directory to a `TransPosix` directory under `$env:PSModulePath`, or import its manifest directly:

```powershell
Import-Module ./TransPosix.psd1
ConvertFrom-PosixCommand 'grep -Ri "TODO" .'
Invoke-TransPosix 'find . -type f -name "*.xml"'
Invoke-TransPosix 'grep TODO README.md' -TranslateOnly
```

`Explain`, the default mode, displays the input, translation, explanations, and warnings. It waits for Enter before execution so the explanation is not immediately displaced by results. `Compact` displays only the translation, while `Quiet` executes without translation output.

```powershell
Set-TransPosixMode Explain
Set-TransPosixMode Compact
Set-TransPosixMode Quiet
```

For a more familiar POSIX-style command-line editing experience, you may also want to enable PSReadLine's Emacs editing mode. This is optional and does not affect command translation or execution:

```powershell
Set-PSReadLineOption -EditMode Emacs
```

POSIX-style command names are not registered during import. `Enable-TransPosixOptionalCommands` adds names that do not normally replace PowerShell aliases: `grep`, `find`, `head`, `tail`, `tac`, `uniq`, `wc`, `which`, and `touch`. `Enable-TransPosixCoreCommands` explicitly replaces familiar names such as `ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`, and `sort`, and also adds `date`. `Disable-TransPosixCommands` removes both groups and restores the original commands. Core commands are an explicit learning aid and may change existing interactive habits or scripts.

Direct `grep` and `find` calls also honor the current display mode. `Invoke-TransPosix -TranslateOnly` never waits for input because it does not execute anything.

For automatic startup without mode-setting output, add this to `$PROFILE`:

```powershell
Import-Module 'C:\path\to\TransPosix\TransPosix.psd1'
Set-TransPosixMode Explain
Enable-TransPosixOptionalCommands

# Explicit opt-in: replaces standard commands such as ls, cat, cp, mv, rm, mkdir, and sort.
Enable-TransPosixCoreCommands
```

Collision warnings begin with `[TransPosix]` so their source is clear.

## Supported subset

### Commands enabled by `Enable-TransPosixCoreCommands`

- `ls`: `-a/--all` and `-R/--recursive`. Dot-prefixed names are excluded by default on every platform and included with `-a`; detailed information is already present on the returned `FileSystemInfo` objects, so `-l` is intentionally unsupported.
- `cat`: files and pipeline input, plus `-n/--number`; numbered results expose `LineNumber` and `Line`.
- `cp`: `-r/-R/--recursive` and `-f/--force`.
- `mv`: `-f/--force`.
- `rm`: `-r/-R/--recursive` and `-f/--force`; force ignores missing literal paths.
- `mkdir`: `-p/--parents`; PowerShell already creates missing parents, while `-p` also accepts existing directories.
- `sort`: `-r`, `-n`, `-u`, single-field `-k N`, and single-character `-t CHAR`. Direct object pipelines may specify a property, such as `Get-Process | sort CPU`.
- `date`: UTC, the documented format tokens, and the limited expressions `now`, `today`, `tomorrow`, `yesterday`, `N days ago`, and `N hours ago`.

### Commands enabled by `Enable-TransPosixOptionalCommands`

- `grep`: `-i/--ignore-case`, `-v/--invert-match`, `-l/--files-with-matches`, `-r`, `-R`, `--recursive`, and `-F/--fixed-strings`. Matching is case-sensitive by default, and every `MatchInfo` result already has a `LineNumber` property, so `-n` is intentionally unsupported.
- `find`: starting path, `-type f/d`, `-name`, `-iname`, `-maxdepth`, `-mtime`, and `-size` with `c`, `k`, `M`, or `G`. Conditions use implicit AND only.
- `head`: `-n NUM` / `--lines NUM`; defaults to 10. File and object-pipeline input are supported.
- `tail`: `-n NUM` / `--lines NUM`, `-f` / `--follow`; defaults to 10. Follow requires file input.
- `tac`: files and pipeline input; buffers the complete input and returns it in reverse order.
- `uniq`: adjacent duplicate grouping and `-c/--count`; count results are structured objects.
- `wc`: `-l/--lines` and `-w/--words`; results are structured objects and multiple files produce per-file results.
- `which`: one or more command names and `-a/--all`; returns native `CommandInfo` objects.
- `touch`: create missing files, update `LastWriteTime`, and `-c/--no-create`.

Use direct-command or string-API help to list supported options. Help never waits for Enter or executes a translated operation.

```powershell
grep -h
find --help
Invoke-TransPosix 'grep --help'
```

For example:

```text
grep -Ri "TODO" .
```

is conceptually translated to:

```powershell
Get-ChildItem -LiteralPath '.' -Recurse -File |
    Select-String -Pattern 'TODO'
```

PowerShell pipelines carry objects, not only text. `Select-String` is the primary grep-like cmdlet; `Get-ChildItem` and `Where-Object` cover common find-like tasks. Tasks commonly written with `awk` are naturally expressed with `ForEach-Object`, `Where-Object`, and `Select-Object`. Structured data should generally be addressed by property name rather than textual column position.

`Select-String` is normally case-insensitive, which differs from POSIX grep. TransPosix makes ordinary `grep` case-sensitive and uses the native case-insensitive behavior for `grep -i`. It treats `find -name` as explicitly case-sensitive and `-iname` as explicitly case-insensitive.

## Security and unsupported syntax

Display code is never executed. TransPosix does not use `Invoke-Expression` or pass user input to `ScriptBlock::Create()`. Only validated, structured `ExecutionPlan` data is interpreted. Unknown options are not ignored; they produce `CanExecute = $false`. Outside quotes, pipelines, semicolons, `&&`, `||`, `$()`, backticks, redirection, and newlines are rejected.

The complete Bash/POSIX shell language, command-line pipelines, expansion, complete glob compatibility, `find -exec/-delete`, and OR/NOT/parenthesized find expressions are unsupported. Byte-oriented counts, full GNU/BSD option compatibility, and unsupported options documented by each command's help remain intentionally out of scope.

Text input follows the default behavior of `Get-Content` and `Select-String`. Windows PowerShell 5.1 cannot reliably auto-detect UTF-8 without a BOM. Byte-oriented operations and output-writing commands are outside the current scope.

## Tests

Run the Pester 5 suite with:

```powershell
Invoke-Pester ./Tests
```

## Roadmap

Expand cross-platform, encoding, and large-input coverage while keeping the supported subset deliberately small. Complete POSIX compatibility is intentionally not a goal.
