$parentModule = Get-Module TransPosix
if($null -eq $parentModule) { throw '[TransPosix] The TransPosix module must be imported before enabling optional commands.' }
$definitions = & $parentModule {
    @{
        grep=${function:Invoke-TransPosixGrepDirect};find=${function:Invoke-TransPosixFindDirect};head=${function:Invoke-TransPosixHeadDirect};tail=${function:Invoke-TransPosixTailDirect}
        tac=${function:Invoke-TransPosixTacDirect};uniq=${function:Invoke-TransPosixUniqDirect};wc=${function:Invoke-TransPosixWcDirect};which=${function:Invoke-TransPosixWhichDirect};touch=${function:Invoke-TransPosixTouchDirect}
    }
}
foreach($entry in $definitions.GetEnumerator()) { Set-Item -Path ("Function:"+$entry.Key) -Value $entry.Value }
Export-ModuleMember -Function grep,find,head,tail,tac,uniq,wc,which,touch
