BeforeAll {
    $script:originalCoreAliases=@(Get-Alias -Scope Global | Where-Object Name -in @('ls','cat','cp','mv','rm','sort','diff'))
    $script:modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'TransPosix.psd1'
    Import-Module $script:modulePath -Force
}

AfterAll {
    Disable-TransPosixCommands -Confirm:$false
    # Core commands mutate global aliases; keep Pester container scopes isolated.
    foreach($alias in $script:originalCoreAliases) {
        Set-Alias -Name $alias.Name -Value $alias.Definition -Description $alias.Description -Option $alias.Options -Scope Global -Force
    }
}

Describe 'diff command' {
    BeforeEach {
        Disable-TransPosixCommands -Confirm:$false
        Set-TransPosixMode Quiet
        Enable-TransPosixCoreCommands -WarningAction SilentlyContinue -Confirm:$false
        # Refresh a possible inherited AllScope alias in the Pester test scope.
        Set-Alias diff TransPosixDiffCommand -Option (Get-Alias diff).Options -Force
        $a=Join-Path $TestDrive 'first [1].txt'
        $b=Join-Path $TestDrive 'second 日本語.txt'
        $empty=Join-Path $TestDrive 'empty.txt'
        Set-Content -LiteralPath $a -Value @('共通','最初','') -Encoding UTF8
        Set-Content -LiteralPath $b -Value @('共通','次の行','') -Encoding UTF8
        [IO.File]::WriteAllText($empty,'')
    }
    AfterEach { Disable-TransPosixCommands -Confirm:$false; Set-TransPosixMode Explain }

    It 'compares files with native structured output and literal UTF-8 paths' {
        $result=@(diff $a $b)
        $result.Count | Should -Be 2
        @($result | Where-Object SideIndicator -eq '<=' | Select-Object -ExpandProperty InputObject) | Should -Be @('最初')
        @($result | Where-Object SideIndicator -eq '=>' | Select-Object -ExpandProperty InputObject) | Should -Be @('次の行')
    }
    It 'buffers explicit stdin on the right' {
        $result=@(Get-Content -LiteralPath $b | diff $a -)
        $result.Count | Should -Be 2
        ($result | Where-Object SideIndicator -eq '=>').InputObject | Should -Be '次の行'
    }
    It 'buffers explicit stdin on the left' {
        $result=@(Get-Content -LiteralPath $a | diff - $b)
        $result.Count | Should -Be 2
        ($result | Where-Object SideIndicator -eq '<=').InputObject | Should -Be '最初'
    }
    It 'supports the omitted second operand' {
        $result=@(Get-Content -LiteralPath $b | diff $a)
        $result.Count | Should -Be 2
        ($result | Where-Object SideIndicator -eq '=>').InputObject | Should -Be '次の行'
    }
    It 'rejects missing files on either side' {
        { diff (Join-Path $TestDrive 'missing') $b } | Should -Throw
        { diff $a (Join-Path $TestDrive 'missing') } | Should -Throw
    }
    It 'rejects absent stdin and ambiguous stdin' {
        { diff $a - } | Should -Throw '*requires pipeline input*'
        { diff - $b } | Should -Throw '*requires pipeline input*'
        { diff $a } | Should -Throw '*requires pipeline input*'
        { diff - - } | Should -Throw '*two independent inputs*'
        { 'line' | diff - - } | Should -Throw '*two independent inputs*'
    }
    It 'accepts empty files and empty pipelines on either side' {
        @(diff $empty $empty).Count | Should -Be 0
        @(diff $empty $b).Count | Should -Be 3
        @(diff $a $empty).Count | Should -Be 3
        @(Get-Content $empty | diff $a -).Count | Should -Be 3
        @(Get-Content $empty | diff - $b).Count | Should -Be 3
        @(Get-Content $empty | diff $a).Count | Should -Be 3
        @(@() | diff $empty).Count | Should -Be 0
    }
    It 'returns nothing for identical contents' {
        @(diff $a $a).Count | Should -Be 0
        @(Get-Content -LiteralPath $a | diff $a).Count | Should -Be 0
    }
    It 'detects case differences in files and all stdin forms by default' {
        Set-Content -LiteralPath $a 'Foo'; Set-Content -LiteralPath $b 'foo'
        $result=@(diff $a $b)
        $result.Count | Should -Be 2
        ($result | Where-Object SideIndicator -eq '<=').InputObject | Should -BeExactly 'Foo'
        ($result | Where-Object SideIndicator -eq '=>').InputObject | Should -BeExactly 'foo'
        @(Get-Content -LiteralPath $b | diff $a).Count | Should -Be 2
        @(Get-Content -LiteralPath $b | diff $a -).Count | Should -Be 2
        @(Get-Content -LiteralPath $a | diff - $b).Count | Should -Be 2
    }
    It 'ignores case with -i in files and all stdin forms' {
        Set-Content -LiteralPath $a 'Foo'; Set-Content -LiteralPath $b 'foo'
        @(diff -i $a $b).Count | Should -Be 0
        @(Get-Content -LiteralPath $b | diff -i $a).Count | Should -Be 0
        @(Get-Content -LiteralPath $b | diff -i $a -).Count | Should -Be 0
        @(Get-Content -LiteralPath $a | diff -i - $b).Count | Should -Be 0
    }
    It 'ignores case with --ignore-case in files and all stdin forms' {
        Set-Content -LiteralPath $a 'Foo'; Set-Content -LiteralPath $b 'foo'
        @(diff --ignore-case $a $b).Count | Should -Be 0
        @(Get-Content -LiteralPath $b | diff --ignore-case $a).Count | Should -Be 0
        @(Get-Content -LiteralPath $b | diff --ignore-case $a -).Count | Should -Be 0
        @(Get-Content -LiteralPath $a | diff --ignore-case - $b).Count | Should -Be 0
    }
    It 'accepts cat pipelines from both native and TransPosix aliases' {
        Set-Content -LiteralPath $a 'Foo'; Set-Content -LiteralPath $b 'foo'
        $saved=Get-Alias cat
        try {
            foreach($target in @('Get-Content','TransPosixCatCommand')) {
                Set-Alias cat $target -Option $saved.Options -Force
                @(cat $b | diff $a).Count | Should -Be 2
                @(cat $b | diff -i $a).Count | Should -Be 0
                @(cat $b | diff --ignore-case $a).Count | Should -Be 0
            }
        }
        finally { Set-Alias cat $saved.Definition -Option $saved.Options -Force }
    }
    It 'maps case options to native translation and string API execution' {
        Set-Content -LiteralPath $a 'Foo'; Set-Content -LiteralPath $b 'foo'
        $operands=' "'+$a+'" "'+$b+'"'
        $t=ConvertFrom-PosixCommand ('diff'+$operands)
        $t.ExecutionPlan.IgnoreCase | Should -BeFalse
        $t.PowerShellCommand | Should -Match '-CaseSensitive'
        @(Invoke-TransPosix ('diff'+$operands) -Quiet).Count | Should -Be 2
        foreach($option in @('-i','--ignore-case')) {
            $t=ConvertFrom-PosixCommand ('diff '+$option+$operands)
            $t.ExecutionPlan.IgnoreCase | Should -BeTrue
            $t.PowerShellCommand | Should -Not -Match '-CaseSensitive'
            @(Invoke-TransPosix ('diff '+$option+$operands) -Quiet).Count | Should -Be 0
        }
        (ConvertFrom-PosixCommand 'diff -- -i file').ExecutionPlan.Paths[0] | Should -Be '-i'
        foreach($option in @('-u','--unified','-r','-w','-b')) {
            (ConvertFrom-PosixCommand ('diff '+$option+' a b')).CanExecute | Should -BeFalse
            { diff $option $a $b } | Should -Throw
        }
    }
    It 'supports translation help and string API execution' {
        (ConvertFrom-PosixCommand 'diff a b').PowerShellCommand | Should -Match 'Compare-Object.*Get-Content'
        @(Invoke-TransPosix ('diff "'+$a+'" "'+$b+'"') -Quiet).Count | Should -Be 2
        (ConvertFrom-PosixCommand 'diff - -').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'diff -u a b').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'diff').CanExecute | Should -BeFalse
        (ConvertFrom-PosixCommand 'diff a b c').CanExecute | Should -BeFalse
        diff --help | Should -Match 'SideIndicator'
        Invoke-TransPosix 'diff -h' | Should -Match 'SideIndicator'
    }
}

Describe 'diff alias lifecycle' {
    It 'restores the original alias when disabled' {
        Disable-TransPosixCommands -Confirm:$false
        $before=Get-Alias diff -Scope Global
        Enable-TransPosixCoreCommands -WarningAction SilentlyContinue -Confirm:$false
        (Get-Alias diff -Scope Global).Definition | Should -Be 'TransPosixDiffCommand'
        Disable-TransPosixCommands -Confirm:$false
        $after=Get-Alias diff -Scope Global
        $after.Definition | Should -Be $before.Definition
        $after.Options | Should -Be $before.Options
        Get-Command TransPosixDiffCommand -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}
