# Mutations of what relay PR 8c adds to sign-in (relays/cloudflare/worker/signin.js): sign-ins started
# per address, accounts made per address, phones per account, the session's epoch, sign-out freeing the
# phone's place, and a limit's code word for the app. The 8b promises are cloudflare-worker-signin.psd1's.
# Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-signin-limits.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\signin.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "starts-unlimited"
           Find = 'if (!started.ok) return redirect('
           Replace = 'if (false) return redirect(' }
        @{ Name = "accounts-made-unlimited"
           Find = 'if (!made.ok) return refused('
           Replace = 'if (false) return refused(' }
        @{ Name = "every-sign-in-counted-as-a-new-account"
           Find = 'if (!st.exists && !st.deleting) {'
           Replace = 'if (!st.deleting) {' }
        @{ Name = "phone-refusal-ignored"
           Find = 'if (!taken.ok) return refused(taken.reason, LIMIT_WORDS[taken.code]);'
           Replace = '' }
        @{ Name = "session-without-the-epoch"
           Find = 'epoch: taken.epoch,'
           Replace = 'epoch: "",' }
        @{ Name = "sign-out-keeps-the-phone-place"
           Find = 'if (s) await accountOf(env, s.account).signOut(session.id.toString());'
           Replace = '' }
        @{ Name = "no-code-word-for-the-app"
           Find = '"#signin-refused" + (word ? ":" + word : "")'
           Replace = '"#signin-refused"' }
    )
}
