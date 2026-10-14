# Mutations of surfaces/pwa/page/app-update.js, when a new version of the phone app takes the place of
# the running one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-app-update.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10g). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\app-update.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "reloads-on-the-first-install"
           Find = 'if (reloaded || !hadController) return "none";'
           Replace = 'if (reloaded) return "none";' }
        @{ Name = "reloads-again-and-again"
           Find = 'if (reloaded || !hadController) return "none";'
           Replace = 'if (!hadController) return "none";' }
        @{ Name = "reloads-over-his-words"
           Find = 'return busy ? "wait" : "reload";'
           Replace = 'return "reload";' }
        @{ Name = "a-clock-set-back-never-asks"
           Find = 'return now < lastAt || now - lastAt >= everyMs;'
           Replace = 'return now - lastAt >= everyMs;' }
        @{ Name = "asks-a-moment-late"
           Find = 'return now < lastAt || now - lastAt >= everyMs;'
           Replace = 'return now < lastAt || now - lastAt > everyMs;' }
        @{ Name = "an-empty-keeping-is-a-draft"
           Find = 'return !!o && typeof o === "object" && Object.keys(o).length > 0;'
           Replace = 'return !!o && typeof o === "object";' }
        @{ Name = "update-pending-always"
           Find = 'VERSION.test(workerVersion) && workerVersion !== pageVersion)'
           Replace = 'VERSION.test(workerVersion))' }
        @{ Name = "any-version-shown"
           Find = 'if (typeof pageVersion !== "string" || !VERSION.test(pageVersion)) return "Version not known.";'
           Replace = 'if (typeof pageVersion !== "string") return "Version not known.";' }
    )
}
