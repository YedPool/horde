# Mutations of the wezfleet pointer matcher (channels/chat/Pointer.ps1, T-0309). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\chat-pointer.psd1
# Each hides a founder's line that merely resembles a wezfleet line, or shows a wezfleet line again;
# test\test-chat-pointer.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\chat\Pointer.ps1"
    Suite  = "test\test-chat-pointer.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "pointer-start-not-anchored"
           Find = '''\Awezfleet: (?:a message is|'
           Replace = '''wezfleet: (?:a message is|' }
        @{ Name = "pointer-end-not-anchored"
           Find = 'changes nothing\z'''
           Replace = 'changes nothing''' }
        @{ Name = "pointer-id-any-text"
           Find = '$script:HordeChatPointerId = ''(?:[0-9a-f]{32}|[0-9a-f]{10})'''
           Replace = '$script:HordeChatPointerId = ''(?:.*)''' }
        @{ Name = "pattern-case-insensitive"
           Find = 'if ($t -cmatch $script:HordeChatPointerPatterns[$k]) { return $k }'
           Replace = 'if ($t -match $script:HordeChatPointerPatterns[$k]) { return $k }' }
        @{ Name = "unconfirmed-start-not-anchored"
           Find = '''\Awezfleet tell to '
           Replace = '''wezfleet tell to ' }
        @{ Name = "unconfirmed-takes-more-lines"
           Find = '[^\r\n]{0,300}\z'''
           Replace = '[\s\S]{0,300}\z''' }
        @{ Name = "relay-start-not-anchored"
           Find = '''\AMESSAGE FROM wezfleet tell'
           Replace = '''MESSAGE FROM wezfleet tell' }
        @{ Name = "relay-takes-any-rest"
           Find = 'if ($rest -eq "") { return "relay" }'
           Replace = 'return "relay"' }
        @{ Name = "relay-body-not-checked"
           Find = ' -and $rest.Substring(2) -cmatch $script:HordeChatPointerPatterns["unconfirmed"]'
           Replace = '' }
        @{ Name = "relay-trailer-not-cut"
           Find = 'if ($more.Success) { $rest = $rest.Substring(0, $more.Index) }'
           Replace = '' }
        @{ Name = "surrounding-space-trimmed"
           Find = '$Text.TrimEnd([char]13, [char]10)'
           Replace = '$Text.Trim()' }
        @{ Name = "test-says-yes-to-all"
           Find = 'return ((Get-HordeChatPointerKind -Text $Text) -cne "")'
           Replace = 'return ((Get-HordeChatPointerKind -Text $Text) -cne "x")' }
    )
}
