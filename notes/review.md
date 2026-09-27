# Full review

Only when the user asks for a "full review" (or a review "by agents"). Never
start one on your own after a change.

Spawn two reviewers in parallel, both **read-only**: they report findings
and edit nothing. Point each at `AGENTS.md`, the notes the change touches, and
the diff (`git diff`, plus any file outside the repo the change depends on,
such as `~/.config/hypr`).

1. **Quickshell and Hyprland expert: correctness.** Does the change hold up
   against how Quickshell and Hyprland actually behave? Check event coverage
   and stale state (`lastIpcObject`, which events refresh what), binding
   dependency tracking, races and ordering, reload behaviour of both
   Quickshell and Hyprland, and multi-monitor and special or named
   workspaces. It may run read-only probes (`hyprctl -j …`, `qs log`, the
   installed qmltypes). It must not dispatch, eval, reload or call `qs ipc`:
   the session it would change is the user's live desktop.
2. **Senior engineer: code quality.** Design, where the code lives
   (`notes/layout.md`), naming, simplicity, duplication, and comments against
   `notes/conventions.md`. It also reviews the notes the change added: are
   they structured, and are rejected ideas under `## Rejected`? It flags
   obvious bugs but leaves correctness to the first reviewer.

Ask each for a ranked list (severity, file:line, failure scenario or reason,
suggested fix), plus what it checked and found fine, in about 600 words.

When both are back, merge them into one list. Drop duplicates, say where the
two reviewers disagree, and mark what needs the user's decision. Apply
nothing until the user picks.
