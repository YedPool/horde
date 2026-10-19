// Which Orc a session belongs to: the ONE place that answers it for the meter.
//
// The founder's data audit (2026-10-19, recommendation 9) says metrics rows carry orc_id and session_id,
// never a lane guessed from a label. orc_id is fleet.db's orc.id, a ULID (Orc N, T-0299, Horde PR 339).
// It is NOT the PR 319 Orc registry's id: that is the lane folder name, which fleet.db keeps as
// orc.lane_dir. One column must never hold two kinds of id, so until fleet.db has the orc rows and the
// session-to-Orc link (its session table / orc_seat view), this lookup answers null for every session and
// orc_id stays NULL. When N says fleet.db has them, this file reads that link (ATTACH, read-only) and
// nothing else changes. Nothing is ever worked out from a label, a parent chain, a folder or a lane name.

// -> { orcIdOf(sessionId) -> string | null, records }
export function loadOrcRegistry(_home) {
  return { records: 0, orcIdOf: () => null };
}
