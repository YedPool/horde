# Mutations of cli/commands/decisions.ps1, the command file of `horde decisions`. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-command.psd1
# A command file only declares, and hands its arguments on. This one also runs what a verb does once
# its lines are out - `inbox` marks as read what it has just printed - and those lines are what this
# spec breaks. The end-to-end scenario, which runs the real command, must fail for each, except the
# one declared Expect = "survives".
@{
    Target = "cli\commands\decisions.ps1"
    Suite  = "test\e2e\e2e-decisions.ps1"
    Mutations = @(
        @{ Name = "inbox-prints-and-never-marks"
           Find = '        $then = Complete-HordeDecisionCommand -After $result.after'
           Replace = '        $then = [pscustomobject]@{ lines = @(); failure = "" }' }
        @{ Name = "marking-made-and-not-said"
           Find = '        Write-HordeDecisionLines -Lines $then.lines'
           Replace = '' }
        @{ Name = "failed-marking-exits-zero"
           Find = '        if ($then.failure -ne "") { throw $then.failure }'
           Replace = ''
           Expect = "survives"
           Reason = "no test at a real command line makes a marking fail between the printing and the marking: that needs the store to stop taking writes in the middle of one command. That a failed marking is reported, and in what words, is tested in one process (test\test-decisions-console-threads.ps1); that the command file throws it is this one line, read and not run" }
    )
}
