# Mutations of core/ownership.json that undo remote plan step R10's split. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\session-split.psd1
# The ownership table decides which record a field is stored in, so moving projectCwd back to the
# engine, or removing the owner node, must fail test\test-schema-session-binding.ps1.
@{
    Target = "core\ownership.json"
    Suite  = "test\test-schema-session-binding.ps1"
    Mutations = @(
        @{ Name = "project-cwd-back-to-the-engine"
           Find = '{ "name": "projectCwd", "owner": "node",'
           Replace = '{ "name": "projectCwd", "owner": "engine",' }
        @{ Name = "owner-node-described-as-nothing"
           Find = '"node": "the engine on the device that runs the session'
           Replace = '"node": " ", "nodeWas": "the engine on the device that runs the session' }
        @{ Name = "spawned-at-back-to-the-engine"
           Find = '{ "name": "spawnedAt", "owner": "node",'
           Replace = '{ "name": "spawnedAt", "owner": "engine",' }
    )
}
