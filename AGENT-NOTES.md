# AGENT-NOTES — paultaki/hermes-agent (fork of NousResearch/hermes-agent)

Handoff log for fleet agents working in this fork. Newest entries on top.
This fork exists to carry upstream contributions; keep PR branches clean —
this file lives on `main` only and must never appear in an upstream PR diff.

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
