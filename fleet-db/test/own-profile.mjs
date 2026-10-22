// EVERY fleet.db test runs under a profile folder of its own, made under the temp folder, and imports this
// module FIRST. A test that passes an empty environment (to test "no home") makes the resolver fall back to
// the system's home folder (core/home.mjs profileDir: os.homedir(), which reads USERPROFILE on Windows and
// HOME elsewhere). Without this, that fallback is the real user's profile, whose pointer file names the real
// Horde home: a test's init then migrated the real fleet.db (10-21). HORDE_HOME inherited from the shell
// is dropped for the same reason. If the redirect does not take, nothing runs.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-profile-'));
process.env.USERPROFILE = dir;
process.env.HOME = dir;
delete process.env.HORDE_HOME;
if (path.resolve(os.homedir()) !== path.resolve(dir)) {
  throw new Error('fleet.db tests: the profile could not be redirected (the home folder is still ' + os.homedir() + '); refusing to run against the real profile');
}
process.on('exit', () => {
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* a leftover temp folder is harmless */ }
});

export const TEST_PROFILE = dir;
