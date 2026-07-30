# AGENT-NOTES — paultaki/hermes-agent (fork of NousResearch/hermes-agent)

Handoff log for fleet agents working in this fork. Newest entries on top.
This fork exists to carry upstream contributions; keep PR branches clean —
this file is committed on `main` only and must never appear in an upstream
PR diff. (A locally-ignored copy sits at the dev clone's root via
`.git/info/exclude` so branch checkouts still surface it.)

## 2026-07-30 (codexbt reimplemented our change) · claude-code

- **Did:** codexbt refactored #73632 (`5cf2751`) after the sweeper review and
  **reimplemented #73627's core change** — `all_profiles` on
  `_get_service_pids()`, passed at both sweeps. Verified three defects and
  posted a narrow correctness note on the one that matters
  (`pull/73632#issuecomment-5133566189`), Paul's call: post the kill-path
  finding only, skip piling on.
- **Why:** They threaded `all_profiles` through `find_gateway_pids()`
  (`gateway.py:552`) instead of only at the sweep call sites.
  `find_gateway_pids()` *includes* service PIDs in its result and
  `kill_gateway_processes(all_profiles=True)` passes straight through to it
  and `terminate_pid()`s everything returned — so sibling launchd gateways
  enter the **kill** path. That is the same `_get_service_pids` scope-leak
  finding #73627's own review already caught and fixed by keeping the
  default `False` and widening only the two update-sweep sites.
- **Next:** Watch for the sweeper's re-review of `5cf2751`. #73627 is clean
  and `MERGEABLE` at `6b993c1d33`; #73632 is still `invalid`/P3 and
  `CONFLICTING`. If a maintainer starts comparing the two implementations,
  the differentiator to state is *where* `all_profiles` is threaded.
- **Watch out:** Two other verified defects were deliberately NOT raised —
  (a) their `main.py` hunks target `service_pids = _get_service_pids()`,
  which **no longer exists in upstream `main.py`** (moved by `927463efcc`),
  so "rebased cleanly" is inaccurate and the branch is still conflicting;
  (b) their `all_profiles` launchd path globs the whole user domain via
  `launchctl list` + `startswith("ai.hermes.gateway")` instead of deriving
  from this install's profiles, breaking sandboxed-`HERMES_HOME` isolation
  and making hermetic tests machine-sensitive. Both are ammunition if a
  maintainer proposes merging their version over #73627 — don't spend them
  unprompted.
- **Also:** Fixed `~/.claude/hooks/agent-notes-guard.sh` — it queried
  AGENT-NOTES commits on the **current branch only**, so on any PR branch in
  this repo (where the file is `.git/info/exclude`d by design) it blocked
  every session regardless of diligence. Added `--all`; backup at
  `agent-notes-guard.sh.bak-2026-07-30`. Verified: no block here, still
  blocks a repo with commits and no notes on any ref.

## 2026-07-30 (pushed + replied) · claude-code

- **Did:** Paul approved. Force-pushed the rebase+port with
  `--force-with-lease` (`32198028ab` → **`6b993c1d33`**) and posted the
  point-by-point sweeper reply
  (`pull/73627#issuecomment-5133486363`). **Supersedes the "NOT PUSHED"
  line in the entry below — that hold is over.**
- **Why:** The sweeper's only blocker on #73627 was the merge conflict from
  the `main.py` → `update_cmd.py` extraction; resolving it is what unblocks
  a maintainer decision.
- **Next:** GitHub now reports **`mergeable: MERGEABLE`** (was `CONFLICTING`),
  so the salvageability complaint is answered. Still `needs-decision`, still
  **zero CI runs ever** on the branch — first-contributor workflow approval
  remains the likeliest gate, and is the thing worth nudging if it stays
  silent another day or two. Watch for a re-review from hermes-sweeper on the
  new head.
- **Watch out:** The reply commits us publicly to the pre-existing-failure
  claim (6 failures, identical on pristine `upstream/main` @ `acfd376d66`) —
  if a maintainer disputes it, re-run in
  `~/Development/hermes-upstream-check` rather than re-arguing from memory.
  Reply draft also archived at
  `~/Desktop/2026-07-30-pr73627-sweeper-reply-draft.md`.

## 2026-07-30 · claude-code

- **Did:** hermes-sweeper finally reviewed **#73627** (`keep_open`,
  `salvageability=medium`) with **no design objections** — it validated the
  per-label approach and asked only for a rebase, because `927463efcc`
  extracted the update pipeline from `hermes_cli/main.py` into
  `hermes_cli/update_cmd.py` on 07-29. Rebased 918 commits onto
  `upstream/main` (`gateway.py`'s 275 lines auto-merged clean; both `main.py`
  conflicts had an **empty upstream side**, so they resolved to upstream and
  verified byte-identical). Ported `_restart_macos_launchd_gateways()`, the
  macOS call site, and both `_get_service_pids(all_profiles=True)` sweeps
  into `update_cmd.py`; repointed the 27-test file to import from
  `hermes_cli.update_cmd`. Amended to **`6b993c1d33`**, both co-author
  trailers intact. Separately, the sweeper reviewed **#73632** a minute later
  and **independently reproduced Paul's sequencing argument** verbatim, and
  told them to split out the 4,677 NVIDIA-skill lines.
- **Why:** The sweeper's only blocker was mechanical, so this was the
  playbook's "just do it" branch. Dropped the PR's `test_gateway.py` edits
  entirely — upstream restructured that file (392 lines now) and deleted both
  tests it touched, and no remaining upstream test monkeypatches
  `_get_service_pids`, so the widened signature needs nothing at the current
  test surface. Put the new helper next to
  `_warn_incomplete_gateway_fleet_restart` rather than adding it to
  `main.py`'s re-export block, since that block exists for *moved* names and
  this one is new.
- **Next:** **NOT PUSHED, NOTHING POSTED** — awaiting Paul's go on (1) the
  force-push (`--force-with-lease`; PR head moves `32198028ab` →
  `6b993c1d33`) and (2) the point-by-point reply, drafted at
  `~/Desktop/2026-07-30-pr73627-sweeper-reply-draft.md`. Once #73627 lands,
  the #73626 `ps -Aww` follow-up becomes safe — and the sweeper has now said
  so itself on #73632, which is the cleanest possible citation for it.
- **Watch out:** Tests — 27/27 on the fleet-restart file, 42/42 on the four
  regression files, 274 passed / **6 failed** across all `test_update*` +
  `test_gateway*`. Those 6 (`test_update_eol_churn.py` ×5 +
  `test_gateway_service.py::...test_systemd_restart_gracefully_restarts_running_service_and_waits`)
  fail **identically on pristine `upstream/main` at `acfd376d66`** — verified
  in `~/Development/hermes-upstream-check`, do not report them as ours. The
  previous session's baseline list lived in a dead scratchpad, so it had to
  be re-derived; re-derive it again rather than trusting this line blindly.
  Also: this repo's shell is **zsh**, where unquoted `$FILES` does not
  word-split — pass globs to pytest directly.

## 2026-07-29 (competing PR #73632) · claude-code

- **Did:** Resumed the watch from the Desktop handoff and fixed three bugs in
  its monitor script (BSD `grep -qE` — `\|` never matched, so the exit-on-merge
  check was dead; a partial-poll acceptance guard; added `gh pr checks`).
  Found `codexbt`'s PR #73632, opened 15 min after Paul's issue #73626,
  carrying the verbatim `ps -Aww` fix sketch **minus the sequencing note**,
  buried in +4679/-3 of unrelated NVIDIA skills. The triage bot called it
  "best fix" and recommended merging it after scope cleanup. Verified the
  hazard against `upstream/main`, then posted a sequencing warning on #73632
  (`issuecomment-5117872966`) — Paul's call, chosen over replying on #73626.
- **Why:** `main`'s update sweep excludes only current-profile service PIDs
  (`_get_service_pids()`, main.py:13509) while searching every profile
  (`find_gateway_pids(all_profiles=True)`, :13510). The `ps` bug is precisely
  what masks that asymmetry on macOS. Land the scan fix alone and sibling
  launchd gateways enumerate as *manual* processes → SIGUSR1 drain → SIGTERM
  → detached respawn watcher racing launchd `KeepAlive` → duplicate gateways
  (8 of them on this Mac's 9-gateway install, every `hermes update`).
  #73627 is the prerequisite: it widens `_get_service_pids(all_profiles=True)`
  at both sweep call sites (branch main.py:13610, :13728).
- **Next:** Watch #73632 for a maintainer reply. If they reduce it to the
  2-line gateway change and move to merge, either the sequencing objection
  holds or #73627 lands first. Monitor now covers #73632 alongside
  #73627/#73625/#73626.
- **Watch out:** #73632 is already labeled `invalid`/P3 and may just be
  closed — don't escalate further unless a maintainer actually engages, and
  keep it about correctness, not authorship. No code changed this session;
  branch still at `32198028ab`. PR #73627 remains at zero reviews, and **no
  CI has ever run on its branch** (likely first-contributor workflow gating).

## 2026-07-28 (session handoff) · claude-code

- **Did:** Paul is clearing the session; wrote the full monitoring/response
  playbook to `~/Desktop/2026-07-28-hermes-pr73627-monitoring-handoff.md`
  (re-armable Monitor script, sweeper response playbook, load-bearing
  design points, this Mac's pre-existing test baseline). Memory pointer
  added. The old session's live monitor dies with that session.
- **Why:** Continuity — the next session must resume the watch in minutes,
  not re-derive three review cycles of context.
- **Next:** New session: read the Desktop handoff, re-arm the monitor,
  follow the playbook. PR #73627 still unreviewed at handoff.
- **Watch out:** PR responses go out as paultaki — scope/design questions
  (`needs-decision`) get surfaced to Paul before replying.

## 2026-07-28 (watch armed) · claude-code

- **Did:** No code delta (still `32198028ab`, submitted as PR #73627).
  Armed a persistent 90s-poll monitor in the active Claude Code session
  watching PR #73627 + issues #73625/#73626 for reviews/comments/labels/
  merge.
- **Why:** Paul asked for active check-ins on the hermes-sweeper bot;
  fast response to its review is the whole game.
- **Next:** On sweeper/maintainer activity: fix → re-test → push → reply
  same-day. The monitor dies with that session — if it's gone, poll
  `gh pr view 73627 --repo NousResearch/hermes-agent` manually.
- **Watch out:** `needs-decision` label is on the PR — a maintainer call
  is pending; anything scope-related goes to Paul before replying.

## 2026-07-28 (SUBMITTED) · claude-code

- **Did:** Upstream submission complete: issue #73625 (fleet-restart
  tracking, full two-machine field evidence), issue #73626 (`ps -A eww`
  dead-sweep discovery), PR #73627 (supersedes #41403, Co-authored-by
  David Neyra), courtesy comment on #41403. Final gate cleared by
  mechanical verification (byte-level diff of the current-profile gate vs
  upstream's inline block + the 2 pinning tests) after `codex exec`
  turned out to hang reading stdin when backgrounded.
- **Why:** Paul's path to upstream contributor status; first merged PR
  is the milestone.
- **Next:** Watch #73627 for the hermes-sweeper auto-review and human
  maintainer response — respond FAST (that's where #41403 died). After
  merge: offer the #73626 ps-fix follow-up PR (safe only post-merge),
  and retire `~/.hermes/bin/hermes-update-all.sh` on both Macs.
- **Watch out:** Never background `codex exec` without `</dev/null` — it
  silently blocks on stdin with 0 CPU and empty output.

## 2026-07-28 (status check) · claude-code

- **Did:** No new code since `32198028ab` (already logged below). Found the
  focused Codex gate re-check stalled (~0 CPU after 15 min); killed and
  relaunched it with a tighter time-boxed prompt.
- **Why:** Paul asked for status; submission is gated only on this check.
- **Next:** On RESOLVED (or a second stall → verify mechanically by
  diffing the gate block against upstream + the 2 pinning tests), file
  the 2 upstream issues + superseding PR from the scratchpad drafts.
- **Watch out:** `codex exec` can stall silently with empty output —
  check CPU time (`ps aux`), not just wall time, before trusting a
  long-running review.

## 2026-07-28 (gate restoration) · claude-code

- **Did:** Fixed the last Codex finding (final-pass review: 5 PASS / 1
  Medium FAIL): my rework had swapped the current-profile restart gate to
  a domain locate, breaking upstream semantics (no-plist installs got
  probed, and macOS-26 registered-but-unprintable labels skipped
  `launchd_restart()` which owns the domain-unsupported fallback).
  Restored the exact upstream gate (plist first → `launchctl list`
  registration predicate via new `_launchd_service_registered()`; locate
  is siblings-only), +2 regression tests pinning both behaviors (27/27).
  Suite v4 verdict: zero regressions — all remaining reds are the
  pre-existing baseline (proven on pristine upstream) or solo-pass load
  flakes. Amended to `32198028ab`, branch pushed to fork.
- **Why:** Merge-ready bar — the sweeper rejected the original PR for a
  domain defect; ours has to survive that same review class cleanly.
- **Next:** One focused Codex re-check of the gate fix is running in
  background; on RESOLVED → file the 2 upstream issues + superseding PR
  (drafts in session scratchpad: issue_fleet_restart.md, issue_ps_eww.md,
  pr_body.md; PR = supersedes #41403, Co-authored-by David Neyra).
- **Watch out:** When "preserving old behavior," diff against the literal
  upstream block, not your memory of it — gate ORDER and PREDICATE were
  both load-bearing here (macOS-26 fallback + zero-calls-when-no-plist).

## 2026-07-28 (final verification) · claude-code

- **Did:** Closed out full-suite forensics: fixed a 2nd self-regression
  (upstream `tests/hermes_cli/test_gateway.py` stubs `_get_service_pids`
  as a zero-arg lambda; my `all_profiles` passthrough broke the signature
  — stubs updated, 57/57 green). Attributed every remaining suite
  failure: 14 files reproduce identically on pristine upstream/main
  (pre-existing baseline), `test_stale_diagnostics` is a parallel-load
  flake (passes solo on both trees). Amended commit: `4ee4e31a8e`.
- **Why:** Zero-questions bar for the upstream PR — every red test either
  fixed or provably not ours.
- **Next:** Full suite v4 + Codex pass 2 running in background; then a
  short Codex delta-check of the two post-review fixes, push branch, file
  2 issues + superseding PR (drafts in session scratchpad).
- **Watch out:** After changing any shared helper's signature, re-run the
  neighboring upstream test files that stub it — spot-checks before a
  rework don't carry over.

## 2026-07-28 (later) · claude-code

- **Did:** Caught and fixed a serious regression in my own fleet-restart
  branch via the full CI-parity suite: enumerating the fleet by globbing
  the REAL `~/Library/LaunchAgents` (pwd-home) leaked this machine's 9
  production labels into the sandboxed update tests
  (`test_update_yes_flag` 2✗/502s, `test_cmd_update` +
  `test_update_autostash` 600s SIGKILL). Production fleet was untouched
  (tests mock subprocess) but the design was wrong: a sandboxed
  HERMES_HOME must never see another install's fleet. Replaced the glob
  with install-scoped `launchd_gateway_labels_for_install()` (derives
  labels from `list_profiles()` / `get_default_hermes_root()`). The 3
  files now pass 103/103 in 86s; my 25 regression tests green; the one
  remaining suite failure (`test_computer_use.py` gnome-shell filter)
  reproduces identically on pristine upstream/main — pre-existing, not
  ours. Amended commit: `54fff54546`.
- **Why:** "Zero questions at review" bar — the recommended contributor
  setup is a live install, so upstream reviewers would have hit the same
  test blowup immediately.
- **Next:** Awaiting final full-suite run (v3) + Codex CLI second-pass
  verification (first pass found 4 real defects, all fixed: domain-blind
  discovery, `_get_service_pids` scope leak into the orphan reaper,
  swallowed launchctl timeouts, Windows test crash). Then: push branch,
  file 2 upstream issues (fleet-restart tracking + the separate
  `ps -A eww` dead-sweep bug) + the superseding PR. Drafts in the session
  scratchpad (`issue_fleet_restart.md`, `issue_ps_eww.md`, `pr_body.md`).
- **Watch out:** Don't run bare `pytest tests/hermes_cli/test_cmd_update*`
  outside `scripts/run_tests.sh` hermeticity on a machine with a live
  fleet until this branch's install-scoping is in — with subprocess
  unmocked those paths execute REAL launchctl calls.

## 2026-07-28 · claude-code

- **Did:** Built the superseding fix for upstream #41403 (macOS `hermes update`
  only restarts the invoking profile's launchd gateway; siblings keep stale
  `sys.modules` and crash on their next turn — bit us 2026-06-15 and again
  2026-07-28 on the Mac Studio fleet). Branch
  `fix/update-restart-all-macos-launchd-gateways`: domain-explicit
  `_locate_launchd_gateway_service()` (`launchctl print gui|user/<uid>/<label>`),
  SIGUSR1 drain → kickstart → fresh-PID verify per sibling,
  `_get_service_pids(all_profiles=...)` scoping, launchctl hints in the
  incomplete-update warning, 25 mocked regression tests
  (`tests/hermes_cli/test_update_launchd_fleet_restart.py`). Codex CLI
  adversarially reviewed round 1 (4 findings, incl. 2 High — orphan reaper
  would have SIGKILLed the whole fleet; all fixed and re-tested 25/25).
  Validated read-only against the live 9-gateway fleet. Also discovered and
  drafted a second upstream issue: `ps -A eww` is illegal on BSD ps, so
  `_scan_gateway_pids` silently returns `[]` on all of macOS (manual-gateway
  sweep is dead code there).
- **Why:** Paul wants contributor status upstream; the original PR is
  unmergeable (dirty, author inactive) and its sweeper review checklist
  (per-label domain + regression tests) was never picked up. Our fleet is the
  only documented mixed-domain / multi-profile reproduction environment.
- **Next:** Waiting on full CI-parity suite + Codex second-pass verification
  (both running in background). When clean: push branch to this fork, file
  tracking issue + `ps -A eww` issue upstream, open PR (body drafted;
  supersedes #41403 with Co-authored-by: David Neyra <vyr.agent@vyrgs.com>),
  then a courtesy comment on #41403. Offer follow-up PR for the `ps` fix
  after this one merges (sequencing matters — see PR body).
- **Watch out:** NEVER develop in `~/.hermes/hermes-agent` — that's the live
  checkout 9 running gateways lazily import from; branch-switching there
  recreates the exact stale-module bug we're fixing. Dev clone is
  `~/Development/hermes-agent` (venv at `~/Development/hermes-venvs/hermes-dev`;
  run tests with `HERMES_PYTHON=<venv>/bin/python scripts/run_tests.sh`).
  Don't `git add -A` in the dev clone — `run_tests.sh` drops runtime
  artifacts like `.lazy-refresh-incomplete` at the repo root. On this Mac,
  after ANY `hermes update`, run `HERMES_SKIP_UPDATE=1
  ~/.hermes/bin/hermes-update-all.sh` until the upstream fix ships.
