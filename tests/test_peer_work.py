#!/usr/bin/env python3
"""Behavioral contract for scripts/invoke-peer-work.sh."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/invoke-peer-work.sh"


def run(args, *, cwd, env, succeeds=True):
    result = subprocess.run(
        [str(SCRIPT), *map(str, args)], cwd=cwd, env=env, text=True,
        capture_output=True, timeout=10,
    )
    assert (result.returncode == 0) == succeeds, (
        result.returncode, result.stdout, result.stderr
    )
    return result


def call_log(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


with tempfile.TemporaryDirectory(prefix="cowork-peer-work-") as temporary:
    tmp = Path(temporary)
    source = tmp / "source"
    worker = tmp / "worker"
    clone = tmp / "clone"
    reports = tmp / "reports"
    fake_bin = tmp / "bin"
    prompt = tmp / "prompt.md"
    log = tmp / "calls.jsonl"
    source.mkdir()
    reports.mkdir()
    fake_bin.mkdir()
    prompt.write_text("Implement phase one\nThen verify Ω", encoding="utf-8")

    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=source, check=True, timeout=10)
    (source / "tracked.txt").write_text("seed")
    subprocess.run(["git", "add", "tracked.txt"], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "worktree", "add", "-q", "-b", "worker", worker], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "clone", "-q", str(source), str(clone)], check=True, timeout=10)

    (source / "tracked.txt").write_text("user edit")
    (source / "user-note.txt").write_text("preserve")

    provider = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
if args and args[0] == "models":
    print("gemini-9.1-flash-medium")
    raise SystemExit()
if args[:2] == ["help", "config"]:
    print('  `model`: AI model to use:\n    - "gemini-9.2-flash"\n')
    raise SystemExit()
if args and args[0] == "/model":
    print('[{"id":"gemini-9.2-flash"}]')
    raise SystemExit()
prompt = args[args.index("-p") + 1]
with open(os.environ["CALL_LOG"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"provider": pathlib.Path(sys.argv[0]).name,
                             "args": args, "prompt": prompt,
                             "cwd": os.getcwd()}) + "\n")
print("provider stderr", file=sys.stderr)
if os.environ.get("FAIL_PROVIDER") == "1":
    print("partial output")
    raise SystemExit(7)
if os.environ.get("EMPTY_REPORT") == "1":
    raise SystemExit()
marker = pathlib.Path("phase-one.txt")
if os.environ.get("EXPECT_PHASE_ONE") == "1":
    assert marker.read_text() == "built"
else:
    marker.write_text("built")
print("completed:" + prompt)
'''
    for name in ("agy", "copilot"):
        executable = fake_bin / name
        executable.write_text(provider)
        executable.chmod(0o755)

    base_env = dict(
        os.environ,
        PATH=f"{fake_bin}:{os.environ['PATH']}",
        CALL_LOG=str(log),
        CODEX_HOME=str(tmp / "codex-home"),
        RALLY_SCRIPTS=str(ROOT / "skills/codex-claude-rally/scripts"),
    )

    def invoke(mode, via, model, output, *, repo=worker, extra=(), env=base_env,
               succeeds=True, source_repo=None):
        args = [mode, via, model, "--repo", repo, "--prompt-file", prompt,
                "--output", output, *extra]
        if source_repo is not None:
            args += ["--source-repo", source_repo]
        return run(args, cwd=tmp, env=env, succeeds=succeeds)

    # Build launches in the registered worktree, preserves the prompt exactly,
    # resolves auto, and publishes provider output with adjacent diagnostics.
    first = reports / "build.md"
    invoke("build", "agy", "auto", first, source_repo=source)
    launch = call_log(log)[-1]
    assert launch["cwd"] == str(worker)
    assert launch["prompt"] == prompt.read_text()
    assert "gemini-9.1-flash-medium" in launch["args"]
    assert "--mode" in launch["args"] and "accept-edits" in launch["args"]
    assert "--print-timeout" in launch["args"] and "10m" in launch["args"]
    assert "--conversation" not in launch["args"]
    assert first.read_text().startswith("completed:")
    artifacts = [p for p in reports.rglob("*") if p.is_file()]
    assert any("provider stderr" in p.read_text() for p in artifacts if p != first)

    # A fresh dependent continuation runs in the existing repo without guessing
    # a latest session. An explicit model beats a stale environment default.
    fresh = reports / "fresh.md"
    fresh_env = dict(base_env, EXPECT_PHASE_ONE="1", COWORK_MODEL="stale-model")
    invoke("continue", "copilot", "explicit-model", fresh, env=fresh_env,
           extra=("--effort", "max"))
    launch = call_log(log)[-1]
    assert launch["cwd"] == str(worker) and launch["prompt"] == prompt.read_text()
    assert "--model=explicit-model" in launch["args"]
    assert "--effort=max" in launch["args"]
    assert not any(arg.startswith("--resume") for arg in launch["args"])
    assert launch["args"][:1] == ["-p"]
    assert "-s" in launch["args"] and "--no-ask-user" in launch["args"]

    # Explicit continuation IDs map to the provider-specific resume option.
    agy_resume = reports / "agy-resume.md"
    invoke("continue", "agy", "agy-model", agy_resume,
           extra=("--session", "agy-session", "--family", "gemini-flash",
                  "--effort", "high"))
    assert call_log(log)[-1]["args"][call_log(log)[-1]["args"].index("--conversation") + 1] == "agy-session"
    copilot_resume = reports / "copilot-resume.md"
    invoke("continue", "copilot", "copilot-model", copilot_resume,
           extra=("--session", "copilot-session"))
    assert "--resume=copilot-session" in call_log(log)[-1]["args"]

    # An explicit family also wins over an unrelated environment model.
    for via, expected in (("agy", "gemini-9.1-flash-medium"),
                          ("copilot", "gemini-9.2-flash")):
        invoke("continue", via, "auto", reports / f"family-{via}.md",
               extra=("--family", "gemini-flash"),
               env=dict(base_env, COWORK_MODEL="stale-model"))
        assert expected in " ".join(call_log(log)[-1]["args"])

    # Access flags are inherited only in full-access mode.
    for full, expected in (("0", False), ("1", True)):
        for via, flag in (("agy", "--dangerously-skip-permissions"),
                          ("copilot", "--allow-all")):
            output = reports / f"access-{via}-{full}.md"
            invoke("continue", via, f"{via}-model", output,
                   env=dict(base_env, COWORK_FULL_ACCESS_AUTHORIZED=full))
            assert (flag in call_log(log)[-1]["args"]) == expected

    # Failure and empty output retain diagnostics but never publish the report.
    for variable in ("FAIL_PROVIDER", "EMPTY_REPORT"):
        output = reports / f"{variable}.md"
        before = set(reports.iterdir())
        invoke("continue", "agy", "model", output,
               env=dict(base_env, **{variable: "1"}), succeeds=False)
        assert not output.exists()
        assert set(reports.iterdir()) - before

    assert (source / "tracked.txt").read_text() == "user edit"
    assert (source / "user-note.txt").read_text() == "preserve"
    assert (worker / "tracked.txt").read_text() == "seed"
    assert not (source / "phase-one.txt").exists()

    # Scope and overwrite guards fail before launching a provider.
    existing = reports / "existing.md"
    existing.write_text("keep")
    cases = [
        ("build", source, reports / "same.md", source),
        ("build", clone, reports / "clone.md", source),
        ("continue", worker, worker / "inside.md", None),
        ("continue", worker, existing, None),
    ]
    for mode, repo, output, source_repo in cases:
        count = len(call_log(log))
        invoke(mode, "agy", "model", output, repo=repo, source_repo=source_repo,
               succeeds=False)
        assert len(call_log(log)) == count
    assert existing.read_text() == "keep"

    large_prompt = tmp / "large.md"
    large_prompt.write_text("x" * 33)
    old_prompt = prompt
    prompt = large_prompt
    count = len(call_log(log))
    invoke("continue", "copilot", "model", reports / "large-report.md",
           env=dict(base_env, COWORK_ARGV_MAX_BYTES="32"), succeeds=False)
    assert len(call_log(log)) == count
    prompt = old_prompt

print("Cowork peer work contract: PASS")
