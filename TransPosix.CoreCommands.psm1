$parentModule = Get-Module TransPosix
if($null -eq $parentModule) { throw '[TransPosix] The TransPosix module must be imported before enabling core commands.' }
$script:OriginalAliases=@{}
foreach($name in @('ls','cat','cp','mv','rm','sort','diff')){$alias=Get-Alias $name -ErrorAction SilentlyContinue;if($alias){$script:OriginalAliases[$name]=[pscustomobject]@{Definition=$alias.Definition;Description=$alias.Description;Options=$alias.Options}}}
$definitions = & $parentModule {
    @{
        TransPosixDiffCommand=${function:Invoke-TransPosixDiffDirect};TransPosixLsCommand=${function:Invoke-TransPosixLsDirect};TransPosixCatCommand=${function:Invoke-TransPosixCatDirect}
        TransPosixCpCommand=${function:Invoke-TransPosixCpDirect};TransPosixMvCommand=${function:Invoke-TransPosixMvDirect};TransPosixRmCommand=${function:Invoke-TransPosixRmDirect}
        mkdir=${function:Invoke-TransPosixMkdirDirect};TransPosixSortCommand=${function:Invoke-TransPosixSortDirect};date=${function:Invoke-TransPosixDateDirect}
    }
}
foreach($entry in $definitions.GetEnumerator()) { Set-Item -Path ("Function:"+$entry.Key) -Value $entry.Value }
Export-ModuleMember -Function TransPosixDiffCommand,TransPosixLsCommand,TransPosixCatCommand,TransPosixCpCommand,TransPosixMvCommand,TransPosixRmCommand,mkdir,TransPosixSortCommand,date
