# Changelog

## 0.4.0

- Split session enablement into independent core and optional command groups.
- Added educational `ls`, `cat`, `cp`, `mv`, and `rm` subsets with help and structured execution plans.
- Added educational `mkdir` support with `-p/--parents` and restoration of the standard PowerShell function.
- Made `Disable-TransPosixCommands` clear both groups and restore the original PowerShell aliases.
- Removed the former `Enable-TransPosixCommands` API.

## 0.3.0

- Added Phase 2 commands `tac`, `uniq`, `wc`, `which`, and `touch`.
- Added structured results for `uniq -c` and `wc`.
- Added direct functions, help, safe execution plans, and Pester coverage for all Phase 2 commands.
- Moved session commands into a removable proxy module so `Disable-TransPosixCommands` fully restores command resolution, including after re-import.

## 0.2.0

- Completed the minimal command set with `head`, `tail`, `sort`, and `date`.
- Added safe structured execution, direct commands, help, and tests for the new commands.
- Preserved and restored the existing PowerShell `sort` alias during enable/disable.

## 0.1.0

- Added the safe, limited command-line parser and structured ExecutionPlan infrastructure.
- Added the initial supported subsets of `grep` and `find`.
- Added Explain, Compact, and Quiet modes.
- Left later commands as explicit future work.
- Fixed direct `grep` incorrectly treating absent pipeline input as null pipeline input.
- Added `-h` / `--help` to `grep` and `find`.
- Added `-mtime` / `-size` parameters to direct `find` calls.
- Made `Set-TransPosixMode` silent and prefixed user-facing diagnostics with `[TransPosix]`.
- Changed user-facing messages and documentation to English.
