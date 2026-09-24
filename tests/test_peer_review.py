#!/usr/bin/env python3
"""Behavioral contract for the read-only peer review launcher.

The selected dialog peer can silently review the wrong thing: it must run from a scratch
directory, honour the subscription gate, forward a requested effort, and never
fall back to another peer.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/invoke-peer-review.sh"


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


with tempfile.TemporaryDirectory(prefix="cowork-peer-review-") as temporary:
    tmp = Path(temporary)
    fake_bin = tmp / "bin"
    home = tmp / "home"
    prompt = tmp / "prompt.md"
    log = tmp / "calls.jsonl"
    fake_bin.mkdir()
    home.mkdir()
    prompt.write_text("Review this diff Ω\nand answer from the text alone", encoding="utf-8")

    claude = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
if args[:2] == ["auth", "status"]:
    print(json.dumps({"loggedIn": True, "authMethod": "claude.ai",
                      "apiProvider": "firstParty", "subscriptionType": "max"}))
    raise SystemExit()
if not any(arg == "-p" for arg in args):
    print("unexpected invocation: " + " ".join(args), file=sys.stderr)
    raise SystemExit(2)
if "--" in args:
    prompt = args[args.index("--") + 1]
else:
    prompt = sys.stdin.read()
with open(os.environ["CALL_LOG"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"args": args, "prompt": prompt,
                             "cwd": os.getcwd()}) + "\n")
print("answered:" + prompt)
'''
    agy = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if args and args[0] == "models":
    print("peer-gamma-3")
    raise SystemExit()
with open(os.environ["CALL_LOG"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"args": args, "cwd": os.getcwd()}) + "\n")
print("peer answered")
'''
    for name, body in (("claude", claude), ("agy", agy)):
        executable = fake_bin / name
        executable.write_text(body)
        executable.chmod(0o755)

    env = {key: value for key, value in os.environ.items()
           if not key.startswith("ANTHROPIC_") and not key.startswith("CLAUDE_CODE_USE_")}
    env.update(PATH=f"{fake_bin}:{os.environ['PATH']}", HOME=str(home),
               CALL_LOG=str(log), XDG_STATE_HOME=str(tmp / "state"))

    # A named model reaches Claude as an alias, the review runs outside the
    # repository, and the answer is the peer's stdout.
    result = run(["claude", "user-choice", "--prompt-file", prompt], cwd=tmp, env=env)
    launch = call_log(log)[-1]
    assert launch["args"][0] == "-p"
    assert "--model" in launch["args"] and "user-choice" in launch["args"]
    assert "--effort" not in launch["args"]
    assert launch["prompt"] == prompt.read_text()
    assert Path(launch["cwd"]) != tmp
    assert Path(launch["cwd"]).name.startswith("cowork-peer-")
    assert not Path(launch["cwd"]).exists()
    assert result.stdout.startswith("answered:")

    # `auto` leaves model selection to the peer, while an explicitly requested
    # effort is forwarded for the CLI to validate.
    run(["claude", "auto", "--effort", "high", "--prompt-file", prompt], cwd=tmp, env=env)
    launch = call_log(log)[-1]
    assert "--model" not in launch["args"] and "high" in launch["args"]

    # The subscription gate fails closed: API-key authentication is not the
    # first-party peer that was requested, and no peer call may happen.
    count = len(call_log(log))
    blocked = run(["claude", "user-choice", "--prompt-file", prompt], cwd=tmp,
                  env=dict(env, ANTHROPIC_API_KEY="sk-not-a-subscription"),
                  succeeds=False)
    assert len(call_log(log)) == count
    assert "authentication" in blocked.stderr

    # A missing CLI is reported, never replaced by another peer.
    run(["claude", "user-choice", "--prompt-file", prompt], cwd=tmp,
        env=dict(env, PATH="/usr/bin:/bin"), succeeds=False)

    # An oversized prompt travels on stdin rather than as an argument.
    big = tmp / "big.md"
    big.write_text("y" * 33)
    run(["claude", "user-choice", "--prompt-file", big], cwd=tmp,
        env=dict(env, COWORK_ARGV_MAX_BYTES="32"))
    launch = call_log(log)[-1]
    assert launch["prompt"] == big.read_text()
    assert not any(arg == big.read_text() for arg in launch["args"])

    # Unknown peers are rejected before any launch.
    count = len(call_log(log))
    run(["nope", "auto", "--prompt-file", prompt], cwd=tmp, env=env, succeeds=False)
    assert len(call_log(log)) == count

    # The Anti-Gravity path keeps its own guards: sandboxed, prompt in the argument.
    run(["agy", "auto", "--prompt-file", prompt], cwd=tmp, env=env)
    launch = call_log(log)[-1]
    assert "--sandbox" in launch["args"]
    assert "--model" not in launch["args"]
    assert prompt.read_text() in launch["args"]

print("Cowork peer review contract: PASS")
