Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'TransPosix.psd1')

Describe 'conflict detection without module auto-loading' {
    InModuleScope TransPosix {
        BeforeEach {
            Disable-TransPosixCommands -Confirm:$false
            $script:savedPreference=Get-Variable PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue
            if($script:savedPreference){$script:savedPreferenceValue=$script:savedPreference.Value}
            Mock Import-Module {
                # The temporary override must already be gone before import.
                $actual=Get-Variable PSModuleAutoLoadingPreference -ErrorAction SilentlyContinue
                if($script:expectedPreferenceExists){$actual.Value | Should -Be $script:expectedPreference}
                else{$actual | Should -BeNullOrEmpty}
            }
        }
        AfterEach {
            $script:TransPosixOptionalEnabled=$false
            $script:TransPosixOptionalModule=$null
            if($script:savedPreference){$global:PSModuleAutoLoadingPreference=$script:savedPreferenceValue}
            else{Remove-Variable PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue}
        }

        It 'still detects aliases functions loaded cmdlets and PATH applications' {
            $global:PSModuleAutoLoadingPreference='All'
            $script:expectedPreferenceExists=$true
            $script:expectedPreference='All'
            function Test-ConflictFunction {}
            Set-Alias Test-ConflictAlias Test-ConflictFunction
            $warnings=@(Enable-TransPosixCommandGroup Optional @('Test-ConflictAlias','Test-ConflictFunction','Get-Item','powershell.exe') 'unused.psm1' 3>&1)
            $text=$warnings -join "`n"
            foreach($type in @('Alias','Function','Cmdlet','Application')){$text | Should -Match "existing $type command"}
        }

        It 'does not discover commands from an unloaded module' {
            $global:PSModuleAutoLoadingPreference='All'
            $script:expectedPreferenceExists=$true
            $script:expectedPreference='All'
            $moduleDirectory=Join-Path $TestDrive 'TransPosixColdProbe'
            $null=New-Item -ItemType Directory -Path $moduleDirectory -Force
            Set-Content (Join-Path $moduleDirectory 'TransPosixColdProbe.psm1') 'function Get-TransPosixColdProbe {}; Export-ModuleMember -Function Get-TransPosixColdProbe'
            New-ModuleManifest -Path (Join-Path $moduleDirectory 'TransPosixColdProbe.psd1') -RootModule 'TransPosixColdProbe.psm1' -FunctionsToExport 'Get-TransPosixColdProbe'
            $originalModulePath=$env:PSModulePath
            try {
                $env:PSModulePath=$TestDrive+[IO.Path]::PathSeparator+$originalModulePath
                $warnings=@(Enable-TransPosixCommandGroup Optional @('Get-TransPosixColdProbe') 'unused.psm1' 3>&1)
                $warnings | Should -BeNullOrEmpty
                Get-Module TransPosixColdProbe | Should -BeNullOrEmpty
                # Positive control: normal discovery can find and load this module.
                Get-Command Get-TransPosixColdProbe | Should -Not -BeNullOrEmpty
                Get-Module TransPosixColdProbe | Should -Not -BeNullOrEmpty
            }
            finally {
                $env:PSModulePath=$originalModulePath
                Remove-Module TransPosixColdProbe -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'conflict detection without module auto-loading' {
    InModuleScope TransPosix {
        BeforeEach {
            Disable-TransPosixCommands -Confirm:$false
            $script:savedPreference=Get-Variable PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue
            if($script:savedPreference){$script:savedPreferenceValue=$script:savedPreference.Value}
            Mock Import-Module {
                # The temporary override must already be gone before import.
                $actual=Get-Variable PSModuleAutoLoadingPreference -ErrorAction SilentlyContinue
                if($script:expectedPreferenceExists){$actual.Value | Should -Be $script:expectedPreference}
                else{$actual | Should -BeNullOrEmpty}
            }
        }
        AfterEach {
            $script:TransPosixOptionalEnabled=$false
            $script:TransPosixOptionalModule=$null
            if($script:savedPreference){$global:PSModuleAutoLoadingPreference=$script:savedPreferenceValue}
            else{Remove-Variable PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue}
        }

        It 'restores each original preference before importing commands' {
            foreach($value in @('All','ModuleQualified','None',$null)) {
                $global:PSModuleAutoLoadingPreference=$value
                $script:expectedPreferenceExists=$true
                $script:expectedPreference=$value
                Mock Get-Command {
                    $PSModuleAutoLoadingPreference | Should -Be 'None'
                    $null
                }
                Enable-TransPosixCommandGroup Optional @('missing-conflict-probe','date') 'unused.psm1'
                $global:PSModuleAutoLoadingPreference | Should -Be $value
                $script:TransPosixOptionalEnabled=$false
            }
            Assert-MockCalled Import-Module -Times 4 -Exactly
            Assert-MockCalled Get-Command -Times 12 -Exactly
        }

        It 'removes the temporary preference when originally undefined' {
            Remove-Variable PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue
            $script:expectedPreferenceExists=$false
            Mock Get-Command { $PSModuleAutoLoadingPreference | Should -Be 'None'; $null }
            Enable-TransPosixCommandGroup Optional @('missing-conflict-probe') 'unused.psm1'
            Get-Variable PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Assert-MockCalled Import-Module -Times 1 -Exactly
        }

        It 'preserves the preference when conflict detection throws' {
            $global:PSModuleAutoLoadingPreference='ModuleQualified'
            Mock Get-Command { $PSModuleAutoLoadingPreference | Should -Be 'None'; throw 'conflict probe failed' }
            { Enable-TransPosixCommandGroup Optional @('probe') 'unused.psm1' } | Should -Throw '*conflict probe failed*'
            $global:PSModuleAutoLoadingPreference | Should -Be 'ModuleQualified'
            Assert-MockCalled Import-Module -Times 0 -Exactly
        }

    }
}

