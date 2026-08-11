@{
    RootModule           = 'TransPosix.psm1'
    ModuleVersion        = '0.4.0'
    GUID                 = '940cf90f-f229-4b36-a263-d1083a062a76'
    Author               = 'TransPosix contributors'
    Description          = 'Educational translations from a safe subset of POSIX commands to native PowerShell.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'ConvertFrom-PosixCommand'
        'Invoke-TransPosix'
        'Set-TransPosixMode'
        'Get-TransPosixMode'
        'Enable-TransPosixCoreCommands'
        'Enable-TransPosixOptionalCommands'
        'Disable-TransPosixCommands'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{ PSData = @{ Tags = @('POSIX', 'Education', 'PowerShell') } }
}
