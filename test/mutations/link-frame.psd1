# Mutations of the link envelope. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-frame.psd1
# Each mutation loosens one rule in schema/link-frame.v1.json's text, and test\test-link-contracts.ps1
# must fail for every one. Every find string occurs exactly once, on one line.
@{
    Target = "schema\link-frame.v1.json"
    Suite  = "test\test-link-contracts.ps1"
    Mutations = @(
        @{ Name = "version-2-accepted"
           Find = '"v": { "type": "integer", "enum": [1],'
           Replace = '"v": { "type": "integer", "enum": [1, 2],' }
        @{ Name = "upper-case-ids-accepted"
           Find = '"uuid": { "type": "string", "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",'
           Replace = '"uuid": { "type": "string", "pattern": "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",' }
        @{ Name = "time-without-zone-accepted"
           Find = '"time": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$",'
           Replace = '"time": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z?$",' }
        @{ Name = "request-id-optional"
           Find = '"req":   { "required": ["verb", "requestId", "args"],'
           Replace = '"req":   { "required": ["verb", "args"],' }
        @{ Name = "result-or-error-not-exclusive"
           Find = ', "oneOf": ["result", "error"] }'
           Replace = ' }' }
        @{ Name = "fourth-answer-state"
           Find = '"state": { "type": "string", "enum": ["known", "absent", "unknown"] },'
           Replace = '"state": { "type": "string", "enum": ["known", "absent", "unknown", "unsure"] },' }
        @{ Name = "frame-cap-past-ceiling"
           Find = '"frameBytes": 1048576,'
           Replace = '"frameBytes": 8388608,' }
        @{ Name = "hello-clock-optional"
           Find = '"required": ["role", "id", "name", "protocols", "verbsVersions", "hordeVersion", "t1"],'
           Replace = '"required": ["role", "id", "name", "protocols", "verbsVersions", "hordeVersion"],' }
    )
}
