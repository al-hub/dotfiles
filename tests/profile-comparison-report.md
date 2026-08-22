# TUI Sidebar Controlled Baseline

Generated: 2026-08-06T22:47:55+09:00

Revision: `f79575b` (dirty: `true`)

Environment: `tmux 3.6`, attached urxvt client, 100x30 geometry
Runs: 1

| Metric | Median and observed range | Result |
| :--- | :--- | :---: |
| Idle launcher CPU | 11.68 % (range 11.68-11.68) | FAIL |
| Idle launcher peak RSS | 7832.00 KiB (range 7832.00-7832.00) | PASS |
| Active launcher CPU | 9.21 % (range 9.21-9.21) | FAIL |
| Active launcher peak RSS | 7832.00 KiB (range 7832.00-7832.00) | PASS |
| Key-to-render latency | 79.00 ms (range 79.00-79.00) | FAIL |
| Enter-to-client-switch latency | 1883.00 ms (range 1883.00-1883.00) | FAIL |
| Archive completion | 1878.00 ms (range 1878.00-1878.00) | FAIL |
| Archive metadata size | 10077.00 bytes (range 10077.00-10077.00) | PASS |
| Restore completion | 4398.00 ms (range 4398.00-4398.00) | FAIL |
| Restore pane/window integrity | 100% required on every run | PASS |
| Layout preserved after 3 open/close cycles | 100% required on every run | PASS |
| Grid bounded and exactly one cursor | required on every run | PASS |

## Method

Each run creates a unique tmux socket, an attached urxvt client, and a temporary history directory. It executes the launcher from the checked-out repository, never the installed copy. CPU is interval CPU time from `/proc/PID/stat` (including reaped children), and RSS is peak launcher RSS sampled during the same interval. Key-to-render checks poll capture-pane at a 10ms interval; other timed operations have bounded completion checks. A timeout or invariant mismatch fails the suite instead of becoming a numeric baseline.

The former active-vs-isolated comparison was removed because it changed the user's live tmux server and compared uncontrolled workloads. Use this report for before/after measurements under the same geometry and run count.

## Performance targets

Targets are reported independently from functional invariants. The current version must not be promoted until all absolute targets pass: idle <=3%, active <=5%, key <=40ms, switch <=1200ms, archive <=350ms, restore <=2200ms.
