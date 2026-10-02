# Mutations of the binding record. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\session-binding.psd1
# The schema is the thing under test, so it is the target: each mutation loosens, removes or
# mislabels one rule in its text, and test\test-schema-session-binding.ps1 must fail for every one.
@{
    Target = "schema\session-binding.v1.json"
    Suite  = "test\test-schema-session-binding.ps1"
    Mutations = @(
        @{ Name = "unknown-keys-allowed"
           Find = '"additionalProperties": false,'
           Replace = '"additionalProperties": true,' }
        @{ Name = "session-id-not-required"
           Find = '"required": ["schemaVersion", "sessionId"],'
           Replace = '"required": ["schemaVersion"],' }
        @{ Name = "schema-version-not-required"
           Find = '"required": ["schemaVersion", "sessionId"],'
           Replace = '"required": ["sessionId"],' }
        @{ Name = "schema-version-2-accepted"
           Find = '"enum": [1],'
           Replace = '"enum": [1, 2],' }
        @{ Name = "session-id-any-string"
           Find = '"sessionId": {"type": "string", "pattern": "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", '
           Replace = '"sessionId": {"type": "string", ' }
        @{ Name = "session-id-owner-changed"
           Find = '"x-horde-owner": "agent", "description": "THE KEY'
           Replace = '"x-horde-owner": "node", "description": "THE KEY' }
        @{ Name = "project-cwd-may-be-empty"
           Find = '"projectCwd": {"type": "string", "pattern": "\\S", '
           Replace = '"projectCwd": {"type": "string", ' }
        @{ Name = "project-cwd-any-type"
           Find = '"projectCwd": {"type": "string", '
           Replace = '"projectCwd": {' }
        @{ Name = "project-cwd-written-by-the-hub"
           Find = '"x-horde-owner": "node", "x-horde-read": "X2 cwd'
           Replace = '"x-horde-owner": "engine", "x-horde-read": "X2 cwd' }
        @{ Name = "project-cwd-read-order-wrong"
           Find = '"x-horde-read": "X2 cwd, then W1 firstCwd, then X1 cwd, then W1 cwd"'
           Replace = '"x-horde-read": "W1 firstCwd, then X2 cwd, then X1 cwd, then W1 cwd"' }
        @{ Name = "project-cwd-dropped"
           Find = '"projectCwd": {"type": "string"'
           Replace = '"projectDir": {"type": "string"' }
        @{ Name = "fleet-field-stored"
           Find = '"properties": {'
           Replace = '"properties": { "role": { "type": "string", "x-horde-owner": "node" },' }
        @{ Name = "device-stored"
           Find = '"properties": {'
           Replace = '"properties": { "device": { "type": "string", "x-horde-owner": "engine" },' }
        @{ Name = "key-repeated-in-text"
           Find = '"properties": {'
           Replace = '"properties": { "projectCwd": { "type": "string" },' }
        @{ Name = "id-of-the-fleet-record"
           Find = '"$id": "horde/schema/session-binding.v1",'
           Replace = '"$id": "horde/schema/session-record.v1",' }
        @{ Name = "last-tool-may-be-empty"
           Find = '"lastTool": {"type": "string", "pattern": "\\S", '
           Replace = '"lastTool": {"type": "string", ' }
        @{ Name = "last-seen-any-zone"
           Find = '"lastSeen": {"type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"'
           Replace = '"lastSeen": {"type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T"' }
        @{ Name = "spawned-at-any-string"
           Find = '"spawnedAt": {"type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$", '
           Replace = '"spawnedAt": {"type": "string", ' }
        @{ Name = "last-seen-written-by-the-hub"
           Find = '"x-horde-owner": "node", "x-horde-read": "W1 lastSeen"'
           Replace = '"x-horde-owner": "engine", "x-horde-read": "W1 lastSeen"' }
    )
}
