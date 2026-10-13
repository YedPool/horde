# Mutations of platform/windows/Services.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-windows.psd1
# Each lets a value be read as code, loses what a service says, or lets a process outside the person's
# session answer for them; test\test-services-tend.ps1 must fail for every one.
@{
    Target = "platform\windows\Services.ps1"
    Suite  = "test\test-services-tend.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "values-written-as-text"
           Find = '$b = { param([string]$Text) return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }'
           Replace = '$b = { param([string]$Text) return $Text }' }
        @{ Name = "error-stream-redirected"
           Find = ' 6>&1 | ForEach-Object'
           Replace = ' *>&1 | ForEach-Object' }
        @{ Name = "console-error-not-logged"
           Find = '$w.AutoFlush = $true; [System.Console]::SetError($w) } catch'
           Replace = '$w.AutoFlush = $true } catch' }
        @{ Name = "log-has-no-times"
           Find = '$w.WriteLine((Get-Date -Format s) + '''' '''' + $_)'
           Replace = '$w.WriteLine("" + $_)' }
        @{ Name = "home-not-set"
           Find = '    foreach ($k in @($Launch.environment.Keys | Sort-Object)) {'
           Replace = '    foreach ($k in @()) {' }
        @{ Name = "shell-from-the-search-path"
           Find = '    return [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")'
           Replace = '    return "powershell.exe"' }
        @{ Name = "non-interactive-sees-the-person"
           Find = '    if ($Interactive -ne $true) { return "this process is not interactive, so it is not in the session the person types in" }'
           Replace = '' }
        @{ Name = "session-zero-sees-the-person"
           Find = '    if ([int]$SessionId -eq 0) { return "this process is in session 0, where no person types" }'
           Replace = '' }
        @{ Name = "program-arguments-unquoted"
           Find = 'return ((@($Launch.program) + @($Launch.arguments) | ForEach-Object { ConvertTo-HordeServiceArgument -Text ("" + $_) }) -join " ")'
           Replace = 'return ((@($Launch.program) + @($Launch.arguments)) -join " ")' }
        @{ Name = "ended-process-reported-started"
           Find = '    } catch { return (New-HordeUnknown -Reason ("process " + $processId + " was created and had ended before it could be looked at")) }'
           Replace = '    } catch { return (New-HordeKnown -Value ([pscustomobject]@{ pid = $processId; startedAt = [datetime]::UtcNow })) }'
           Expect = "survives"
           Reason = "the suite's one real start is of a stub that lives long enough to be looked at; a process that ends between its creation and the look cannot be arranged without a race" }
        @{ Name = "blind-session-answers-idle"
           Find = '    if ($blind -ne "") { return (New-HordeUnknown -Reason $blind) }'
           Replace = ''
           Expect = "survives"
           Reason = "the suite runs in the person's own session, where the adapter is never blind; what makes it blind is the function above, which the suite calls with each case" }
    )
}
