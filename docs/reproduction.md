# tmux Sidebar TUI - Reproduction & Alignment Guide

This guide documents the guidelines and commands required to align the agent's background reproduction scripts with the user's interactive terminal experience, preventing discrepancy bugs due to headless execution.

## Core Discrepancies (Headless vs. Attached)

1. **Terminal Client Events**: Interactive terminal clients propagate focus reporting, mouse events, and resize boundaries, modifying cursor/border states and changing computed hashes. Headless runs generate zero client events.
2. **Command Context**: Default tmux commands (e.g. `switch-client` or `display-message`) executed inside a background daemon run without a client context, causing them to target the wrong session or be ignored.
3. **Pane Lifecycle**: Switching sessions via TUI `Enter` keeps the target launcher process alive. A per-session tmux user option requests a force-refresh, and the switch path waits briefly for the target sidebar to render `>*` before and after `switch-client`. A fast client switch can still expose a transient stale cursor frame.

---

## 3 Alignment Rules

### 1. Explicit Client Targeting (`-c` option)
Always query the active client and target it explicitly using the `-c` flag. Do not infer the active session from an unscoped background `display-message`; identify a sidebar's own session from its pane id when inspecting the launcher.

- **List Clients**:
  ```bash
  tmux list-clients
  # Output format: /dev/pts/3: session_name [270x74 ...]
  ```
- **Explicit Switch**:
  ```bash
  tmux switch-client -c /dev/pts/3 -t <session_name>
  ```

### 2. Simulate Physical Keypresses (`send-keys`)
Rather than forcing layout changes via background tmux API commands, simulate physical keystrokes on the sidebar pane.

- **Identify Sidebar Pane**:
  ```bash
  tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_title}' | grep 'dotfiles-session-sidebar'
  ```
- **Simulate Selection Move**:
  ```bash
  tmux send-keys -t %7 j  # Move down
  ```
- **Simulate Enter Switch**:
  ```bash
  tmux send-keys -t %7 Enter  # Triggers the TUI switch_session handler
  ```

### 3. Capture Color Grid (`capture-pane -e`)
Verify the active rendering state by capturing the full character grid including escape codes.

- **Capture Pane**:
  ```bash
  tmux capture-pane -e -p -t %8 > /tmp/capture.txt
  ```
- **Count Color Escape Codes (Gradients)**:
  ```bash
  grep -o $'\e' /tmp/capture.txt | wc -l
  ```

---

## Standard Verification / Test Flow

For archive safety, use a dedicated history directory and verify that a
failed archive leaves every managed session alive. After a successful restore,
repeat the same archive only after removing the restored session and confirm
that the archive's history marker prevents duplicate history import. During
both operations, capture `@dotfiles_sidebar_operation`, sidebar owner client,
pane ID/PID, and the trace file before declaring the flow successful.

To verify that session switches do not trigger false gradients, use this check:

```bash
# 1. Switch client to a stable background session
tmux switch-client -c /dev/pts/3 -t bbbbbbbbbbbbbbbbbbbbbbbb
sleep 7

# 2. Find the sidebar pane in the currently attached session and move/select a target
sidebar_pane=$(tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_title}' |
  awk '$1 == "bbbbbbbbbbbbbbbbbbbbbbbb" && $3 == "dotfiles-session-sidebar" { print $2; exit }')
tmux send-keys -t "$sidebar_pane" j
tmux send-keys -t "$sidebar_pane" Enter
sleep 2

# 3. Find and capture the target sidebar's complete visible grid
target_sidebar=$(tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_title}' |
  awk '$1 == "cccccccccccccccccccccccc" && $3 == "dotfiles-session-sidebar" { print $2; exit }')
tmux capture-pane -e -p -t "$target_sidebar" > /tmp/verify.txt
esc_count=$(grep -o $'\e' /tmp/verify.txt | wc -l)
if grep -Fq ">* cccccccccccccccccccccccc" /tmp/verify.txt; then
    echo "SUCCESS: Sidebar cursor and active session are aligned."
else
    echo "FAILURE: Sidebar cursor and active session are not aligned (ESC count = $esc_count)."
fi
```
