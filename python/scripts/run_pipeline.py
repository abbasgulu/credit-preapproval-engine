"""Stage 5: the whole pipeline with one command.

In plain words: the project is a chain of steps — load the data, build the
features, score every client, run the decision engine, explain the
declines, write the dashboard files. Each step already checks itself and
stops on a problem. This script runs the steps in the right order, stops at
the first one that fails, and writes everything every step printed to one
log file, so a run can be repeated and inspected later.

Two modes:
  daily (default)  what a lender would schedule every day, on the data and
                   model already in place: decisions for today, their checks,
                   the evaluation, the three facts behind each risk decline
                   and the dashboard files
  full             rebuilds everything from the raw Kaggle files first
                   (load, features, scores, reference tables), then the
                   daily steps. Takes a long time: 58.5M rows are loaded

Never run automatically, on purpose (decisions 16, 23, 25, 31): training the
models, the one-time holdout exam and choosing the PD cut-off. They are
decisions with a date and a reason, made once by a person — not something a
schedule should repeat.

Passwords: none here. SQL*Plus connects through the Oracle Wallet and Python
through Windows Credential Manager, exactly as when each step is run by hand.

Run from the repository root:
    python python\\scripts\\run_pipeline.py              daily run
    python python\\scripts\\run_pipeline.py --mode full  everything from the raw files
    python python\\scripts\\run_pipeline.py --list       show the steps, run nothing
    python python\\scripts\\run_pipeline.py --from explain   resume after a failed step
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOG_DIR = ROOT / "logs"
TAIL = 20                       # lines of a failed step shown on screen


@dataclass(frozen=True)
class Step:
    key: str        # short name, used with --from
    what: str       # plain-words description
    kind: str       # "sql" or "python"
    target: str     # runner script, relative to the repository root
    full_only: bool = False


STEPS = [
    Step("check_data", "raw Kaggle files are complete", "python", r"python\scripts\check_data.py", True),
    Step("load", "Stage 1: raw tables loaded from the Kaggle files", "sql", r"sql\run_stage1.sql", True),
    Step("features", "Stage 2: feature table, data-quality checks", "sql", r"sql\run_stage2.sql", True),
    Step("split", "Stage 3: fit / valid / holdout split, score tables", "sql", r"sql\run_stage3.sql", True),
    Step("scores", "Stage 3: calibrated scores for every client", "python", r"python\scripts\calibrate_and_score.py", True),
    Step("scores_check", "Stage 3: Oracle and Python PDs agree", "sql", r"sql\99_checks\05_model_scores.sql", True),
    Step("reference", "Stage 4: rules, reasons, limit grid, engine code", "sql", r"sql\run_stage4.sql", True),
    Step("decisions", "decision engine for today + 12 checks", "sql", r"sql\run_decisions.sql"),
    Step("evaluate", "evaluation and reconciliation with Python", "python", r"python\scripts\evaluate_decisions.py"),
    Step("explain", "three facts behind each risk decline", "python", r"python\scripts\explain_decisions.py"),
    Step("export", "dashboard files, reconciled with the run", "python", r"python\scripts\export_tableau.py"),
]


def plan(mode: str, start: str | None) -> list[Step]:
    steps = [s for s in STEPS if mode == "full" or not s.full_only]
    if start:
        keys = [s.key for s in steps]
        if start not in keys:
            sys.exit(f"Unknown step '{start}' for mode {mode}. Steps: {', '.join(keys)}")
        steps = steps[keys.index(start):]
    return steps


def command(step: Step) -> list[str]:
    if step.kind == "sql":
        return ["sqlplus", "/nolog", "@" + step.target]
    return [sys.executable, step.target]


def preflight(steps: list[Step]) -> list[str]:
    """Problems that would stop the run anyway, found before anything starts."""
    problems = []
    for s in steps:
        if not (ROOT / s.target.replace("\\", os.sep)).exists():
            problems.append(f"missing script {s.target}")
    if any(s.kind == "sql" for s in steps) and shutil.which("sqlplus") is None:
        problems.append("sqlplus is not on PATH (Oracle client tools)")
    if any(s.kind == "python" for s in steps):
        if not (ROOT / "config" / ".env").exists():
            problems.append(r"config\.env not found (copy config\.env.example config\.env)")
        if any(s.key in ("explain", "evaluate") for s in steps) and not (ROOT / "models" / "lightgbm.txt").exists():
            problems.append(r"models\lightgbm.txt not found (Stage 3 model of record)")
    return problems


def run_step(step: Step, log) -> tuple[int, list[str], float]:
    """Run one step; everything it prints goes to the log, line by line as it comes."""
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUNBUFFERED="1")
    t0 = time.perf_counter()
    lines: list[str] = []
    with subprocess.Popen(command(step), cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, env=env) as proc:
        for raw in proc.stdout:
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            lines.append(line)
            log.write(line + "\n")
        code = proc.wait()
    log.flush()
    return code, lines, time.perf_counter() - t0


def summary(started: dt.datetime) -> list[str]:
    """What the run produced, read back from Oracle (the run itself and every check it logged)."""
    sys.path.insert(0, str(ROOT / "python"))
    from hcr.db import read_sql
    run = read_sql("SELECT run_id, TO_CHAR(run_date, 'YYYY-MM-DD') AS run_date, clients, approved "
                   "FROM v_decision_last_run")
    dq = read_sql("SELECT severity, passed, COUNT(*) AS n FROM dq_log WHERE checked_at >= :t "
                  "GROUP BY severity, passed", {"t": started})
    out = []
    if not run.empty:
        r = run.iloc[0]
        out.append(f"decision run {int(r.run_id)} of {r.run_date}: {int(r.clients):,} clients, "
                   f"{int(r.approved):,} pre-approved ({r.approved / r.clients:.1%})")
    total = int(dq.n.sum()) if not dq.empty else 0
    warn = int(dq[(dq.passed == "N")].n.sum()) if not dq.empty else 0
    out.append(f"data-quality checks logged during this run: {total}, failed warnings: {warn}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Run the credit pre-approval pipeline.")
    ap.add_argument("--mode", choices=["daily", "full"], default="daily")
    ap.add_argument("--from", dest="start", metavar="STEP", help="start at this step (resume after a failure)")
    ap.add_argument("--list", action="store_true", help="show the steps and exit")
    args = ap.parse_args()

    steps = plan(args.mode, args.start)
    if args.list:
        for i, s in enumerate(steps, 1):
            print(f"{i:>2}. {s.key:<13} {s.what}   ({s.target})")
        return

    problems = preflight(steps)
    if problems:
        sys.exit("Not started:\n  - " + "\n  - ".join(problems))

    started = dt.datetime.now()
    LOG_DIR.mkdir(exist_ok=True)
    log_path = LOG_DIR / f"pipeline_{started:%Y%m%d_%H%M%S}.log"
    print(f"Pipeline, mode {args.mode}: {len(steps)} steps. Log: {log_path.relative_to(ROOT)}\n")
    t_all = time.perf_counter()
    with open(log_path, "a", encoding="utf-8") as log:      # "a": two runs in the same second share one log
        log.write(f"Pipeline started {started:%Y-%m-%d %H:%M:%S}, mode {args.mode}\n")
        for i, s in enumerate(steps, 1):
            print(f"[{i}/{len(steps)}] {s.key:<13} {s.what} ...", end=" ", flush=True)
            log.write(f"\n{'=' * 78}\n[{i}/{len(steps)}] {s.key}: {' '.join(command(s))}\n{'=' * 78}\n")
            code, lines, secs = run_step(s, log)
            log.write(f"--> exit code {code}, {secs:.1f} s\n")
            if code != 0:
                print(f"FAILED ({secs:.1f} s)\n")
                print("\n".join("    " + ln for ln in lines[-TAIL:]))
                print(f"\nStopped. Full output: {log_path.relative_to(ROOT)}")
                print(f"After fixing it, resume with:  python python\\scripts\\run_pipeline.py "
                      f"--mode {args.mode} --from {s.key}")
                log.write("PIPELINE STOPPED\n")
                sys.exit(1)
            print(f"OK ({secs:.1f} s)")
        total = time.perf_counter() - t_all
        print(f"\nAll {len(steps)} steps passed in {total / 60:.1f} min.")
        log.write(f"\nPIPELINE COMPLETE in {total:.1f} s\n")
        try:
            for line in summary(started):
                print("  " + line)
                log.write(line + "\n")
        except Exception as exc:          # the run itself succeeded; the summary is a convenience
            print(f"  (summary not available: {exc})")


if __name__ == "__main__":
    main()
