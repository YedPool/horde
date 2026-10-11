# Mutations of surfaces/pwa/page/keywrap.js, how the phone keeps its identity key wrapped. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-keywrap.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\keywrap.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "wrap-not-bound-to-its-horde"
           Find = 'return utf8(WRAP_DOMAIN + kind + "\n" + horde + "\n" + agreeKeyId);'
           Replace = 'return utf8(WRAP_DOMAIN + kind + "\n" + agreeKeyId);' }
        @{ Name = "feeble-work-factor-tried"
           Find = 'record.iterations < 100000) return no('
           Replace = 'record.iterations < 1) return no(' }
        @{ Name = "unwrapped-key-not-checked"
           Find = 'if (await keyId(publicPoint) !== agreeKeyId || a.length !== b.length || !a.every((x, i) => x === b[i])) return no('
           Replace = 'if (await keyId(publicPoint) !== agreeKeyId) return no(' }
        @{ Name = "recovery-code-letters-not-read-as-digits"
           Find = '.replace(/O/g, "0").replace(/[IL]/g, "1");'
           Replace = ';' }
    )
}
