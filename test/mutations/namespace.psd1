# Mutations of core/Namespace.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\namespace.psd1
# Each breaks one of remote plan R11's rules; test\test-namespace.ps1 must fail for every one of them.
@{
    Target = "core\Namespace.ps1"
    Suite  = "test\test-namespace.ps1"
    Mutations = @(
        @{ Name = "host-name-accepted-as-device"
           Find = 'if ($Device -cnotmatch $script:HordeNamespaceDevicePattern) { throw'
           Replace = 'if ($Device -eq "") { throw' }
        @{ Name = "device-any-case"
           Find = 'if ($Device -cnotmatch $script:HordeNamespaceDevicePattern) { throw'
           Replace = 'if ($Device -notmatch $script:HordeNamespaceDevicePattern) { throw' }
        @{ Name = "unknown-space-accepted"
           Find = 'if ($Space -cnotmatch $script:HordeNamespaceSpacePattern) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "malformed-device-placed"
           Find = 'if ($dv -cnotmatch $script:HordeNamespaceDevicePattern) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "missing-space-placed"
           Find = 'if ($null -eq $d -or $null -eq $s) { return "its namespace does not give both a device and a space" }'
           Replace = 'if ($null -eq $d) { return "its namespace does not give both a device and a space" }'
           Expect = "survives"
           Reason = "a missing space reads as empty text, which the space pattern refuses on the next line; this line only gives the clearer reason" }
        @{ Name = "no-namespace-is-local"
           Find = 'if ($null -eq $Namespace) { return "it names no namespace" }'
           Replace = 'if ($null -eq $Namespace) { return "" }' }
        @{ Name = "other-device-looked-up"
           Find = 'if ("$($Namespace.device)" -cne "$($Local.device)") { return New-HordeAnswer'
           Replace = 'if ($false) { return New-HordeAnswer' }
        @{ Name = "other-space-looked-up"
           Find = 'if ("$($Namespace.space)" -cne "$($Local.space)") { return New-HordeAnswer'
           Replace = 'if ($false) { return New-HordeAnswer' }
        @{ Name = "same-process-ignores-device"
           Find = '$same = ("$($A.ns.device)" -ceq "$($B.ns.device)") -and '
           Replace = '$same = ' }
        @{ Name = "same-process-ignores-space"
           Find = ' -and ("$($A.ns.space)" -ceq "$($B.ns.space)")'
           Replace = '' }
        @{ Name = "same-process-ignores-proc-start"
           Find = ' -and ((ConvertTo-HordeNamespaceTicks $A.procStart) -eq (ConvertTo-HordeNamespaceTicks $B.procStart))'
           Replace = '' }
        @{ Name = "same-process-compares-proc-start-as-text"
           Find = '((ConvertTo-HordeNamespaceTicks $A.procStart) -eq (ConvertTo-HordeNamespaceTicks $B.procStart))'
           Replace = '("$($A.procStart)" -ceq "$($B.procStart)")' }
        @{ Name = "missing-proc-start-matches"
           Find = 'if ($null -eq $psProp -or $null -eq (ConvertTo-HordeNamespaceTicks $psProp.Value)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "missing-pid-matches"
           Find = 'if ($null -eq $pidProp -or $null -eq (ConvertTo-HordeNamespacePid $pidProp.Value)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "remote-path-opened"
           Find = 'if ("$($Namespace.device)" -cne "$($Local.device)" -or "$($Namespace.space)" -cne "$($Local.space)") {'
           Replace = 'if ($false) {' }
        @{ Name = "other-space-path-opened"
           Find = ' -or "$($Namespace.space)" -cne "$($Local.space)") {'
           Replace = ') {' }
        @{ Name = "remote-path-reason-unsaid"
           Find = '": it is displayed, never opened here")'
           Replace = '"")' }
        @{ Name = "hand-built-bad-space-placed"
           Find = 'if ($sv -cnotmatch $script:HordeNamespaceSpacePattern) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "device-pattern-dollar-anchor"
           Find = '[0-9a-f]{12}\z'''
           Replace = '[0-9a-f]{12}$''' }
        @{ Name = "space-pattern-dollar-anchor"
           Find = '$script:HordeNamespaceSpacePattern = ($script:HordeProcessSpacePattern -replace ''\$$'', ''\z'')'
           Replace = '$script:HordeNamespaceSpacePattern = $script:HordeProcessSpacePattern' }
        @{ Name = "pid-range-unchecked"
           Find = 'if ($n -lt 1 -or $n -gt $script:HordeNamespacePidMax) { return $null }'
           Replace = '' }
        @{ Name = "pid-list-accepted"
           Find = 'if ($null -eq $Value -or $Value -is [System.Array]) { return $null }'
           Replace = 'if ($null -eq $Value) { return $null }' }
    )
}
