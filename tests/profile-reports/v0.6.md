# TUI Sidebar Controlled Baseline

Generated: 2026-07-17T11:02:13+09:00

Revision: `361bf74` (dirty: `true`)

Environment: `tmux 3.6`, attached urxvt client, 100x30 geometry
Runs: 3

| Metric | Median and observed range | Result |
| :--- | :--- | :---: |
| Idle launcher CPU | 53.41 % (range 53.23-57.19) | PASS |
| Idle launcher peak RSS | 5968.00 KiB (range 5660.00-6024.00) | PASS |
| Active launcher CPU | 51.14 % (range 50.91-55.14) | PASS |
| Active launcher peak RSS | 5972.00 KiB (range 5660.00-6024.00) | PASS |
| Key-to-render latency | 4187.00 ms (range 1766.00-7816.00) | PASS |
| Enter-to-client-switch latency | 10221.00 ms (range 9691.00-14232.00) | PASS |
| Archive completion | 1061.00 ms (range 939.00-1069.00) | PASS |
| Archive metadata size | 10068.00 bytes (range 9902.00-10615.00) | PASS |
| Restore completion | 18979.00 ms (range 18922.00-20466.00) | PASS |
| Restore pane/window integrity | 100% required on every run | PASS |
| Layout preserved after 3 open/close cycles | 100% required on every run | PASS |
| Grid bounded and exactly one cursor | required on every run | PASS |

## Method

Each run creates a unique tmux socket, an attached urxvt client, and a temporary history directory. It executes the launcher from the checked-out repository, never the installed copy. CPU is interval CPU time from `/proc/PID/stat` (including reaped children), and RSS is peak launcher RSS sampled during the same interval. Timed operations have bounded completion checks; a timeout or invariant mismatch fails the suite instead of becoming a numeric baseline.

The former active-vs-isolated comparison was removed because it changed the user's live tmux server and compared uncontrolled workloads. Use this report for before/after measurements under the same geometry and run count.
