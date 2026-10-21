# Mutations of core/home.mjs, the node twin of core/Home.ps1's Get-HordeHome (T-0299): HORDE_HOME, else the pointer
# file %USERPROFILE%\.horde-home.json, else REFUSED. Each breaks one rule of that resolution; test\test-home-node.ps1
# (fleet-db/test/home.test.mjs) must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\home-node.psd1
@{
    Target = "core\home.mjs"
    Suite  = "test\test-home-node.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "pointer-name-changed"
           Find = 'export const POINTER_NAME = ''.horde-home.json'';'
           Replace = 'export const POINTER_NAME = ''.horde-home.txt'';' }
        @{ Name = "horde-home-ignored"
           Find = 'if (raw !== '''') {'
           Replace = 'if (false) {' }
        @{ Name = "rooted-test-too-loose"
           Find = 'return process.platform === ''win32'' ? /^([A-Za-z]:[\\/]|\\\\[^\\/])/.test(s) : path.isAbsolute(s);'
           Replace = 'return path.isAbsolute(s);' }
        @{ Name = "homedir-fallback-dropped"
           Find = 'return p !== '''' ? p : os.homedir();'
           Replace = 'return p;' }
        @{ Name = "relative-horde-home-accepted"
           Find = 'if (!isRootedPath(raw)) {'
           Replace = 'if (false) {' }
        @{ Name = "no-pointer-falls-back-to-a-default"
           Find = 'if (e && e.code === ''ENOENT'') {'
           Replace = 'if (e && e.code === ''ENOENT'') { return { ok: true, home: path.join(profileDir(env), ''.horde''), source: ''default'' };' }
        @{ Name = "unreadable-pointer-skipped"
           Find = 'return { ok: false, kind: ''refused'', message: ''the home pointer file '' + file + '' cannot be read ('''
           Replace = 'return { ok: false, kind: ''unset'', message: ''the home pointer file '' + file + '' cannot be read (''' }
        @{ Name = "bad-pointer-skipped-as-unset"
           Find = 'const bad = (why) => ({ ok: false, kind: ''refused'','
           Replace = 'const bad = (why) => ({ ok: false, kind: ''unset'',' }
        @{ Name = "refusal-does-not-name-the-file"
           Find = '''the home pointer file '' + file + '' is refused: '''
           Replace = '''the home pointer file is refused: ''' }
        @{ Name = "non-ascii-accepted"
           Find = 'if (/[^\x20-\x7e\r\n\t]/.test(text)) return bad(''it holds a character that is not ASCII'');'
           Replace = '' }
        @{ Name = "not-json-skipped"
           Find = 'catch { return bad(''it is not JSON''); }'
           Replace = 'catch { return { ok: false, kind: ''unset'', message: ''x'' }; }' }
        @{ Name = "version-compared-loosely"
           Find = 'if (obj.v !== 1) return bad(''v is not 1'');'
           Replace = 'if (obj.v != 1) return bad(''v is not 1'');' }
        @{ Name = "version-unchecked"
           Find = 'if (obj.v !== 1) return bad(''v is not 1'');'
           Replace = '' }
        @{ Name = "missing-hordehome-accepted"
           Find = 'if (typeof obj.hordeHome !== ''string'' || obj.hordeHome.trim() === '''') return bad(''hordeHome is missing'');'
           Replace = 'if (typeof obj.hordeHome !== ''string'') return { ok: true, home: path.resolve(profileDir(env)), source: ''pointer'', file };' }
        @{ Name = "relative-pointer-target-accepted"
           Find = 'if (!isRootedPath(target)) return bad(''hordeHome "'' + target + ''" is not an absolute path'');'
           Replace = '' }
        @{ Name = "missing-folder-accepted"
           Find = 'if (!isDir) return bad(''hordeHome "'' + target + ''" is not an existing folder'');'
           Replace = '' }
        @{ Name = "pointer-source-mislabelled"
           Find = 'source: ''pointer'', file };'
           Replace = 'source: ''HORDE_HOME'', file };' }
    )
}
