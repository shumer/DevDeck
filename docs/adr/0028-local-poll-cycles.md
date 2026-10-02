# ADR 0028 — Share local poll cycles without stale explicit observations

Status: accepted for the Windows development preview.

Windows previously started one 15-second timer per project and ran `ddev list -j` for every
card. The Mac uses a separate ten-second local loop with one DDEV inventory. Source coverage
had incorrectly claimed worker caching; an offline production request regression observed
three CLI reads where one was required.

Use one native ten-second local timer. Active idle cards share a fresh cycle identifier;
closed/busy cards do not fetch. Reads start independently across distributions, and a slow
cycle coalesces later ticks instead of accumulating requests. Remote polling retains the
user's existing interval choices.

Protocol v1 gains optional refreshCycle (1–128 UTF-8 bytes, without controls). Each distribution's
worker keeps one DDEV inventory task/result for its latest explicit cycle, including an unavailable
CLI result. A new cycle retries. Manual Refresh, discovery/import and lifecycle checks bypass or
invalidate the cache, so explicit actions and their verified outcomes cannot reuse stale state.
No time-based cache or shared Mac service is changed.

Local reads/actions/logs and remote API/verification/Inbox operations use separate lazily created
worker connections in each distribution. The old single transport serialized a slow API request
ahead of local status. Connection loss replaces only that channel and resets its observation
scope; a distribution reset/disposal closes both. Both channels use the same versioned runtime
and OS-vault/token-on-stdin rules. Workers persist no credentials.

Regressions cover grouped/new/manual/import/action cycles, unavailable CLI retry, cycle validation,
native busy/closed guards, overlapping polls, independent reads and a stalled remote transport
that cannot hold the local connection. Native Mac suite/build, live desktop/network/other release
qualification remain required; this development change does not certify full feature parity.
