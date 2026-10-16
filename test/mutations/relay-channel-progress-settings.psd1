# Mutations of which file the progress channel follows (channels/progress/Settings.ps1, moved out of
# channels/progress/Channel.ps1 on 2026-10-15 so the Orc registry reads the same file). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-progress-settings.psd1
# test\test-relay-channel-progress.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "channels\progress\Settings.ps1"
    Suite  = "test\test-relay-channel-progress.ps1"
    Mutations = @(
        @{ Name = "default-file-not-under-the-home"
           Find = 'return [System.IO.Path]::Combine($HordeHome, "progress", "changelog.jsonl")'
           Replace = 'return [System.IO.Path]::Combine($HordeHome, "changelog.jsonl")' }
        @{ Name = "progress-file-setting-ignored"
           Find = 'if ($Setting -cne "") { return $Setting }'
           Replace = '' }
    )
}
