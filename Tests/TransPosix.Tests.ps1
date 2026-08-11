$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TransPosix.psd1'
Import-Module $modulePath -Force

BeforeAll {
    $script:modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TransPosix.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'TransPosix foundation' {
    It 'imports and exposes only formal commands' {
        (Get-Command ConvertFrom-PosixCommand).ModuleName | Should -Be 'TransPosix'
        Get-TransPosixMode | Should -Be 'Explain'
    }
    It 'can be re-imported' { { Import-Module $script:modulePath -Force } | Should -Not -Throw }
    It 'changes mode without producing output' {
        @(Set-TransPosixMode Compact).Count | Should -Be 0
        Get-TransPosixMode | Should -Be 'Compact'
        Set-TransPosixMode Explain
    }
    It 'rejects unsafe shell syntax' {
        { ConvertFrom-PosixCommand 'grep TODO file;Remove-Item *' } | Should -Throw
        { ConvertFrom-PosixCommand 'grep $(Get-Process) file' } | Should -Throw
        { ConvertFrom-PosixCommand 'find . -exec echo {} ;' } | Should -Throw
    }
    It 'preserves quoted spaces and Windows backslashes' {
        $t = ConvertFrom-PosixCommand 'grep TODO "C:\path with spaces\file.txt"'
        $t.ExecutionPlan.Paths[0] | Should -Be 'C:\path with spaces\file.txt'
    }
}

Describe 'grep translation' {
    It 'provides help without execution' {
        (Invoke-TransPosix 'grep --help') | Should -Match 'files-with-matches'
    }
    It 'translates basic file search' { (ConvertFrom-PosixCommand 'grep "TODO" file.txt').CanExecute | Should -BeTrue }
    It 'translates combined short options' {
        $t=ConvertFrom-PosixCommand 'grep -Ri "TODO" .'
        $t.PowerShellCommand | Should -Match 'Get-ChildItem'
        $t.ExecutionPlan.Recursive | Should -BeTrue
    }
    It 'supports fixed, inverted, and files-only searches' {
        (ConvertFrom-PosixCommand 'grep -F "[test]" file.txt').ExecutionPlan.Fixed | Should -BeTrue
        (ConvertFrom-PosixCommand 'grep -v DEBUG app.log').ExecutionPlan.Invert | Should -BeTrue
        (ConvertFrom-PosixCommand 'grep -Ril TODO .').ExecutionPlan.FilesOnly | Should -BeTrue
    }
    It 'rejects unsupported options' { (ConvertFrom-PosixCommand 'grep --exclude-dir=.git TODO .').CanExecute | Should -BeFalse }
    It 'is case-sensitive by default and makes -i meaningful' {
        Set-Content -LiteralPath (Join-Path $TestDrive 'case.txt') @('TODO','todo')
        @(Invoke-TransPosix ('grep TODO "'+(Join-Path $TestDrive 'case.txt')+'"') -Quiet).Count | Should -Be 1
        @(Invoke-TransPosix ('grep -i TODO "'+(Join-Path $TestDrive 'case.txt')+'"') -Quiet).Count | Should -Be 2
    }
    It 'rejects -n because MatchInfo always contains LineNumber' {
        (ConvertFrom-PosixCommand 'grep -n TODO file.txt').CanExecute | Should -BeFalse
    }
}

Describe 'find translation' {
    It 'provides help without execution' {
        (Invoke-TransPosix 'find -h') | Should -Match 'maxdepth'
    }
    It 'supports type and name' {
        $t=ConvertFrom-PosixCommand 'find . -type f -name "*.xml"'
        $t.CanExecute | Should -BeTrue; $t.PowerShellCommand | Should -Match '-Filter'
    }
    It 'supports maxdepth, mtime, and size' {
        (ConvertFrom-PosixCommand 'find . -maxdepth 2 -type d').ExecutionPlan.MaxDepth | Should -Be 2
        (ConvertFrom-PosixCommand 'find . -type f -mtime -7').CanExecute | Should -BeTrue
        (ConvertFrom-PosixCommand 'find . -type f -size +10M').CanExecute | Should -BeTrue
    }
    It 'rejects destructive and boolean expressions' {
        (ConvertFrom-PosixCommand 'find . -type f -delete').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'find . -name "*.txt" -o -name "*.log"').CanExecute | Should -BeFalse
    }
}

Describe 'head and tail translation' {
    It 'translates line counts and rejects bytes' {
        (ConvertFrom-PosixCommand 'head -n 5 file.txt').ExecutionPlan.Lines | Should -Be 5
        (ConvertFrom-PosixCommand 'tail --lines=5 file.txt').ExecutionPlan.Lines | Should -Be 5
        (ConvertFrom-PosixCommand 'head -c 10 file.txt').CanExecute | Should -BeFalse
    }
    It 'preserves pipeline objects' {
        Set-TransPosixMode Quiet
        Enable-TransPosixOptionalCommands -WarningAction SilentlyContinue
        $items=@([pscustomobject]@{Id=1},[pscustomobject]@{Id=2})
        @($items|head -n 1)[0].Id | Should -Be 1
        @($items|tail -n 1)[0].Id | Should -Be 2
        Disable-TransPosixCommands
    }
}

Describe 'sort translation' {
    It 'supports reverse numeric unique and fields' {
        (ConvertFrom-PosixCommand 'sort -r file.txt').ExecutionPlan.Reverse | Should -BeTrue
        (ConvertFrom-PosixCommand 'sort -n file.txt').ExecutionPlan.Numeric | Should -BeTrue
        (ConvertFrom-PosixCommand 'sort -u file.txt').ExecutionPlan.Unique | Should -BeTrue
        (ConvertFrom-PosixCommand 'sort -t, -k2 data.txt').ExecutionPlan.Key | Should -Be 2
    }
    It 'rejects unsupported stable sort' { (ConvertFrom-PosixCommand 'sort -s file.txt').CanExecute | Should -BeFalse }
}

Describe 'date translation' {
    It 'supports UTC formats and limited expressions' {
        (ConvertFrom-PosixCommand 'date -u').ExecutionPlan.Utc | Should -BeTrue
        (Invoke-TransPosix 'date "+%Y-%m-%d"' -Quiet) | Should -Match '^\d{4}-\d{2}-\d{2}$'
        (ConvertFrom-PosixCommand 'date -d "tomorrow"').CanExecute | Should -BeTrue
        (ConvertFrom-PosixCommand 'date -d "7 days ago"').ExecutionPlan.Amount | Should -Be -7
    }
    It 'rejects unknown expressions and formats' {
        (ConvertFrom-PosixCommand 'date -d "next Friday"').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'date "+%Q"').CanExecute | Should -BeFalse
    }
}

Describe 'Phase 2 additional commands' {
    It 'reverses tac input and preserves objects' {
        $items=@([pscustomobject]@{Id=1},[pscustomobject]@{Id=2})
        $plan=(ConvertFrom-PosixCommand 'tac').ExecutionPlan
        $plan.Operation | Should -Be 'Tac'
        Set-TransPosixMode Quiet
        Enable-TransPosixOptionalCommands -WarningAction SilentlyContinue
        @($items|tac)[0].Id | Should -Be 2
        Disable-TransPosixCommands
    }
    It 'groups only adjacent duplicates with uniq' {
        Set-TransPosixMode Quiet
        Enable-TransPosixOptionalCommands -WarningAction SilentlyContinue
        @(@('a','a','b','a')|uniq) | Should -Be @('a','b','a')
        $counts=@(@('a','a','b')|uniq -c)
        $counts[0].Count | Should -Be 2
        $counts[0].Value | Should -Be 'a'
        Disable-TransPosixCommands
    }
    It 'returns structured wc results' {
        $path=Join-Path $TestDrive 'words.txt';Set-Content -LiteralPath $path -Value @('one two','three')
        $result=Invoke-TransPosix ('wc -lw "'+$path+'"') -Quiet
        $result.Lines | Should -Be 2
        $result.Words | Should -Be 3
        $result.PSTypeNames | Should -Contain 'TransPosix.WordCount'
    }
    It 'returns CommandInfo from which' {
        $result=Invoke-TransPosix 'which Get-Item' -Quiet
        $result.Name | Should -Be 'Get-Item'
        $result | Should -BeOfType ([System.Management.Automation.CommandInfo])
    }
    It 'creates, updates, and conditionally skips files with touch' {
        $created=Join-Path $TestDrive 'created.txt';$missing=Join-Path $TestDrive 'missing.txt'
        $null=Invoke-TransPosix ('touch "'+$created+'"') -Quiet
        Test-Path -LiteralPath $created | Should -BeTrue
        $item=Get-Item -LiteralPath $created;$item.LastWriteTime=(Get-Date).AddDays(-2);$old=$item.LastWriteTime
        $null=Invoke-TransPosix ('touch "'+$created+'"') -Quiet
        (Get-Item -LiteralPath $created).LastWriteTime | Should -BeGreaterThan $old
        $null=Invoke-TransPosix ('touch -c "'+$missing+'"') -Quiet
        Test-Path -LiteralPath $missing | Should -BeFalse
    }
    It 'rejects unsupported additional-command options' {
        (ConvertFrom-PosixCommand 'uniq -d file').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'wc -c file').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'touch -d now file').CanExecute | Should -BeFalse
    }
}

Describe 'safe execution' {
    BeforeAll {
        $script:fixture=Join-Path $TestDrive '日本語 directory'; New-Item -ItemType Directory $script:fixture | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fixture '日本語.txt') -Value @('TODO one','DEBUG','TODO two') -Encoding UTF8
    }
    It 'executes grep through an execution plan' {
        $cmd='grep -F TODO "'+(Join-Path $script:fixture '日本語.txt')+'"'
        @(Invoke-TransPosix $cmd -Quiet).Count | Should -Be 2
    }
    It 'executes find through an execution plan' {
        $cmd='find "'+$script:fixture+'" -type f -name "*.txt"'
        @(Invoke-TransPosix $cmd -Quiet).Count | Should -Be 1
    }
    It 'returns translation only' { (Invoke-TransPosix 'find . -type f' -TranslateOnly -Quiet).PSTypeNames | Should -Contain 'TransPosix.Translation' }
}

Describe 'direct command modes' {
    BeforeEach {
        Mock Read-Host { '' } -ModuleName TransPosix
        Disable-TransPosixCommands -Confirm:$false
        Enable-TransPosixOptionalCommands -WarningAction SilentlyContinue -Confirm:$false
    }
    AfterEach { Disable-TransPosixCommands -Confirm:$false; Set-TransPosixMode Explain | Out-Null }

    It 'shows educational output in Explain mode' {
        Set-TransPosixMode Explain | Out-Null
        $null = find $TestDrive -Type f -InformationVariable details 6>$null
        ($details -join "`n") | Should -Match 'PowerShell:'
        ($details -join "`n") | Should -Match 'Explanation:'
        Assert-MockCalled Read-Host -ModuleName TransPosix -Times 1
    }
    It 'shows only translated code in Compact mode' {
        Set-TransPosixMode Compact | Out-Null
        $null = find $TestDrive -Type f -InformationVariable details 6>$null
        ($details -join "`n") | Should -Match '^\[TransPosix\]'
        ($details -join "`n") | Should -Match 'Get-ChildItem'
        ($details -join "`n") | Should -Not -Match 'Explanation:'
    }
    It 'does not add Compact translation text to the success pipeline' {
        Set-TransPosixMode Compact | Out-Null
        $path=Join-Path $TestDrive 'pipeline.txt';Set-Content -LiteralPath $path 'value'
        $result=@(find $TestDrive -Type f 6>$null | Where-Object Name -eq 'pipeline.txt')
        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType ([System.IO.FileInfo])
    }
    It 'does not show translation in Quiet mode' {
        Set-TransPosixMode Quiet | Out-Null
        $null = find $TestDrive -Type f -InformationVariable details 6>$null
        @($details).Count | Should -Be 0
    }
    It 'searches files when there is no pipeline input' {
        Set-TransPosixMode Quiet | Out-Null
        Set-Content -LiteralPath (Join-Path $TestDrive 'search.txt') -Value 'find this line'
        @(grep -r find $TestDrive).Count | Should -Be 1
    }
    It 'still accepts real pipeline input' {
        Set-TransPosixMode Quiet | Out-Null
        @('find this line','nothing') | grep find | Should -Be 'find this line'
    }
    It 'accepts mtime and size in direct find calls' {
        Set-TransPosixMode Quiet | Out-Null
        $recentPath = Join-Path $TestDrive 'recent.txt'
        Set-Content -LiteralPath $recentPath -Value ('x' * 2048)
        @(find $TestDrive -Type f -MTime -7).FullName | Should -Contain $recentPath
        @(find $TestDrive -Type f -Size +1k).FullName | Should -Contain $recentPath
    }
    It 'rejects invalid direct mtime values' {
        Set-TransPosixMode Quiet | Out-Null
        { find $TestDrive -MTime recent } | Should -Throw
    }
    It 'shows direct help without prompting' {
        grep -h | Should -Match 'fixed-strings'
        find --help | Should -Match 'mtime'
        Assert-MockCalled Read-Host -ModuleName TransPosix -Times 0
    }
}

Describe 'Invoke-TransPosix confirmation' {
    BeforeEach { Mock Read-Host { '' } -ModuleName TransPosix }

    It 'pauses before execution in Explain mode' {
        $null = Invoke-TransPosix 'find . -maxdepth 0 -type f' -Explain
        Assert-MockCalled Read-Host -ModuleName TransPosix -Times 1
    }
    It 'does not pause when only translating' {
        $null = Invoke-TransPosix 'find . -type f' -TranslateOnly -Explain
        Assert-MockCalled Read-Host -ModuleName TransPosix -Times 0
    }
}

Describe 'command disable lifecycle' {
    It 'removes every enabled command and restores prior resolution' {
        $names=@('ls','cat','cp','mv','rm','mkdir','sort','date','grep','find','head','tail','tac','uniq','wc','which','touch')
        $before=@{};foreach($name in $names){$before[$name]=@(Get-Command $name -All -ErrorAction SilentlyContinue).Count}
        Enable-TransPosixCoreCommands -WarningAction SilentlyContinue
        Enable-TransPosixOptionalCommands -WarningAction SilentlyContinue
        Disable-TransPosixCommands
        foreach($name in $names){@(Get-Command $name -All -ErrorAction SilentlyContinue).Count | Should -Be $before[$name]}
        (Get-Alias sort).Definition | Should -Be 'Sort-Object'
    }
    It 'still disables commands after the parent module is re-imported' {
        Enable-TransPosixOptionalCommands -WarningAction SilentlyContinue
        Import-Module $script:modulePath -Force
        Disable-TransPosixCommands
        Get-Module TransPosix.OptionalCommands | Should -BeNullOrEmpty
        Get-Command tac -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'core commands' {
    BeforeEach { Disable-TransPosixCommands -Confirm:$false; Set-TransPosixMode Quiet; Enable-TransPosixCoreCommands -WarningAction SilentlyContinue -Confirm:$false }
    AfterEach { Disable-TransPosixCommands -Confirm:$false; Set-TransPosixMode Explain }

    It 'exports the split API and removes the legacy enable command' {
        Get-Command Enable-TransPosixCoreCommands | Should -Not -BeNullOrEmpty
        Get-Command Enable-TransPosixOptionalCommands | Should -Not -BeNullOrEmpty
        Get-Command Enable-TransPosixCommands -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
    It 'warns about the implicit date to Get-Date resolution' {
        Disable-TransPosixCommands -Confirm:$false
        Enable-TransPosixCoreCommands -WarningVariable warnings -WarningAction SilentlyContinue -Confirm:$false
        ($warnings -join "`n") | Should -Match "'date'.*Get-Date"
    }
    It 'translates core options and provides help' {
        (ConvertFrom-PosixCommand 'ls -aR .').ExecutionPlan.All | Should -BeTrue
        (ConvertFrom-PosixCommand 'ls -l .').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'cat -n file').ExecutionPlan.Number | Should -BeTrue
        (ConvertFrom-PosixCommand 'cp -rf a b').ExecutionPlan.Recursive | Should -BeTrue
        (ConvertFrom-PosixCommand 'mkdir -p parent/child').ExecutionPlan.Parents | Should -BeTrue
        (Invoke-TransPosix 'rm --help') | Should -Match 'recursive'
        (Invoke-TransPosix 'mkdir --help') | Should -Match 'New-Item'
    }
    It 'excludes dot-prefixed items by default and includes them with -a' {
        Set-Content -LiteralPath (Join-Path $TestDrive '.hidden') 'hidden'
        Set-Content -LiteralPath (Join-Path $TestDrive 'visible') 'visible'
        @(TransPosixLsCommand $TestDrive).Name | Should -Be @('visible')
        @(TransPosixLsCommand -a $TestDrive).Name | Should -Contain '.hidden'
    }
    It 'numbers cat input as structured objects' {
        $a=Join-Path $TestDrive 'a.txt';$b=Join-Path $TestDrive 'b.txt';Set-Content $a @('one','two');Set-Content $b 'three'
        # Use the proxy target explicitly because Windows PowerShell 5.1 copies
        # AllScope aliases into Pester's child scope before this test enables Core.
        $result=@(TransPosixCatCommand -n $a,$b)
        $result.Count | Should -Be 3
        $result[2].LineNumber | Should -Be 3
        $result[2].PSTypeNames | Should -Contain 'TransPosix.NumberedLine'
    }
    It 'copies moves and removes literal paths' {
        $source=Join-Path $TestDrive 'source.txt';$copy=Join-Path $TestDrive 'copy.txt';$moved=Join-Path $TestDrive 'moved.txt';Set-Content -LiteralPath $source 'value'
        cp $source $copy;Test-Path -LiteralPath $copy | Should -BeTrue
        mv $copy $moved;Test-Path -LiteralPath $moved | Should -BeTrue
        rm $moved;Test-Path -LiteralPath $moved | Should -BeFalse
    }
    It 'does not expand wildcard characters in file-operation paths' {
        $source=Join-Path $TestDrive 'source [1].txt';$copy=Join-Path $TestDrive 'literal copy.txt';Set-Content -LiteralPath $source 'value'
        $null=Invoke-TransPosix ('cp "'+$source+'" "'+$copy+'"') -Quiet
        Test-Path -LiteralPath $copy | Should -BeTrue
    }
    It 'requires a directory for multiple copy sources' {
        $a=Join-Path $TestDrive 'a';$b=Join-Path $TestDrive 'b';$target=Join-Path $TestDrive 'target';Set-Content $a a;Set-Content $b b
        { cp $a $b $target } | Should -Throw
    }
    It 'creates directories and accepts existing directories only with -p' {
        $nested=Join-Path $TestDrive 'parent\child'
        mkdir $nested | Should -BeOfType ([System.IO.DirectoryInfo])
        { mkdir $nested } | Should -Throw
        { mkdir -p $nested } | Should -Not -Throw
    }
}
