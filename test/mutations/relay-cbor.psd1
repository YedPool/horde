# Mutations of relay/Cbor.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-cbor.psd1
# Each switches off one refusal of the strict CBOR reader, and test\test-relay-registration.ps1 - whose
# hand-written bytes and WebCrypto-made registrations are each wrong in one way only - must fail for
# every one. Every find string occurs once in the target.
@{
    Target = "relay\Cbor.ps1"
    Suite  = "test\test-relay-registration.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "indefinite-read-as-reserved"
           Find = 'if ($info -eq 31) {'
           Replace = 'if ($false) {' }
        @{ Name = "longer-form-allowed"
           Find = 'if ($major -ne 7 -and $n -lt $floor) {'
           Replace = 'if ($false) {' }
        @{ Name = "repeated-key-allowed"
           Find = 'if ($seen -ccontains $keyText) {'
           Replace = 'if ($false) {' }
        @{ Name = "tag-read-as-simple"
           Find = 'if ($h.major -eq 6) {'
           Replace = 'if ($false) {' }
        @{ Name = "utf8-not-strict"
           Find = 'New-Object System.Text.UTF8Encoding -ArgumentList $false, $true'
           Replace = 'New-Object System.Text.UTF8Encoding -ArgumentList $false, $false' }
        @{ Name = "no-depth-limit"
           Find = 'if ($Depth -gt $limits.depth) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-item-limit"
           Find = 'if ($h.number -gt [decimal]$limits.items) {'
           Replace = 'if ($false) {' }
        @{ Name = "trailing-bytes-allowed"
           Find = 'if ($r.ok -and $Whole -and $r.next -ne $Bytes.Length) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-key-type"
           Find = 'if (@("uint", "nint", "text") -cnotcontains $k.value.type) {'
           Replace = 'if ($false) {' }
    )
}
