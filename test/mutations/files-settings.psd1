# Mutations of files/Settings.ps1, the named settings of the files store. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-settings.psd1
# Each changes a default, widens a range, or lets a refused settings file through;
# test\test-files-store.ps1 must fail for every one.
@{
    Target = "files\Settings.ps1"
    Suite  = "test\test-files-store.ps1"
    Mutations = @(
        @{ Name = "cap-default-one-byte-more"
           Find = 'name = "maxFileBytes"; kind = "whole"; default = 1048576;'
           Replace = 'name = "maxFileBytes"; kind = "whole"; default = 1048577;' }
        @{ Name = "cap-may-be-zero"
           Find = 'default = 1048576; min = 1;'
           Replace = 'default = 1048576; min = 0;' }
        @{ Name = "title-default-one-more"
           Find = 'name = "maxTitleChars"; kind = "whole"; default = 120;'
           Replace = 'name = "maxTitleChars"; kind = "whole"; default = 121;' }
        @{ Name = "version-tries-default-changed"
           Find = 'name = "versionTries"; kind = "whole"; default = 20;'
           Replace = 'name = "versionTries"; kind = "whole"; default = 21;' }
        @{ Name = "leftover-age-default-changed"
           Find = 'name = "leftoverMinAgeSeconds"; kind = "whole"; default = 600;'
           Replace = 'name = "leftoverMinAgeSeconds"; kind = "whole"; default = 60;' }
        @{ Name = "held-tries-default-changed"
           Find = 'name = "heldReadTries"; kind = "whole"; default = 40;'
           Replace = 'name = "heldReadTries"; kind = "whole"; default = 4;' }
        @{ Name = "held-wait-default-changed"
           Find = 'name = "heldReadWaitMs"; kind = "whole"; default = 50;'
           Replace = 'name = "heldReadWaitMs"; kind = "whole"; default = 5;' }
        @{ Name = "refused-file-runs-on-nothing"
           Find = 'if ($read.state -ceq "refused") { throw (@($read.findings) -join [Environment]::NewLine) }'
           Replace = '' }
        @{ Name = "settings-read-from-the-real-home"
           Find = 'Get-HordeModuleSettings -Declaration (Get-HordeFilesSettingsDeclaration) -HordeHome $HordeHome'
           Replace = 'Get-HordeModuleSettings -Declaration (Get-HordeFilesSettingsDeclaration)' }
    )
}
