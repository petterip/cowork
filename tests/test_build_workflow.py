#!/usr/bin/env python3
"""Execute the build skill's shell examples with a local, deterministic worker."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / 'skills/codex-build/SKILL.md'
BLOCKS = re.findall(r'```bash\n(.*?)\n```', SKILL.read_text(), re.S)


def block(marker):
    return next(code for code in BLOCKS if marker in code)


def shell(code, env, cwd, succeeds=True, error=None):
    result = subprocess.run(
        ['bash', '-euo', 'pipefail'], input=code, text=True, env=env,
        cwd=cwd, capture_output=True, timeout=10,
    )
    assert (result.returncode == 0) == succeeds, result.stderr
    if error:
        assert error in result.stderr, result.stderr
    return result.stdout


with tempfile.TemporaryDirectory(prefix='cowork-build-check-') as temporary:
    root = Path(temporary)
    worker = root / 'worker'
    worker.mkdir()
    binary = root / 'bin'
    binary.mkdir()
    fake_codex = binary / 'codex'
    fake_codex.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
prompt = sys.stdin.read()
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps({'args': args, 'prompt': prompt, 'cwd': os.getcwd()}) + '\\n')
if os.environ.get('NO_REPORT') == '1':
    sys.exit(0)
if os.environ.get('FAIL_WORKER') == '1':
    print('worker failed', file=sys.stderr)
    sys.exit(7)
phase = os.environ['PHASE']
if phase == 'two':
    assert pathlib.Path('one.txt').read_text() == 'verified input'
pathlib.Path(phase + '.txt').write_text('verified input')
pathlib.Path(args[args.index('-o') + 1]).write_text('Worker result for ' + phase)
print(json.dumps({'type': 'thread.started', 'thread_id': 'thread-' + phase}))
''')
    fake_codex.chmod(0o755)
    env = dict(os.environ, PATH=f'{binary}:{os.environ["PATH"]}',
               XDG_STATE_HOME=str(root / 'state'), CODEX_HOME=str(root / 'config'), TMPDIR=str(root),
               RALLY_SCRIPTS=str(ROOT / 'skills/codex-claude-rally/scripts'),
               CALL_LOG=str(root / 'calls.jsonl'), PHASE='one')
    for code in BLOCKS:
        subprocess.run(['bash', '-n'], input=code, text=True, check=True, timeout=10)
    for full_access in ['0', '1']:
        env['COWORK_FULL_ACCESS_AUTHORIZED'] = full_access
        setup = shell(block('BUILD_ROOT=') + '\ndeclare -p BUILD_DIR BUILD_ACCESS', env, worker)
        build_dir = Path(shell(setup + '\nprintf %s "$BUILD_DIR"', env, worker))
        assert build_dir.is_dir(), 'Setup artifacts vanished between shell calls'
        assert build_dir.stat().st_mode & 0o077 == 0
        assert not (worker / 'PLAN.md').exists()
        for phase in ['one', 'two']:
            env.update(PHASE=phase, CODEX_MODEL=f'model-{phase}', CODEX_EFFORT='xhigh')
            # An untracked plan is supplied as frozen task text, not a worker file.
            phase_code = block('PHASE_DIR=').replace(
                '<frozen phase text, or exact sections of a worker-readable spec>',
                'Save and reopen drafts offline; preserve old draft compatibility',
            )
            phase_state = shell(setup + '\n' + phase_code + '\ndeclare -p PHASE_DIR P CODEX_ARGS', env, worker)
            launched = shell(setup + '\n' + phase_state + '\n' + block('BUILD_REPORT="$PHASE_DIR/report.md"')
                             + '\ndeclare -p BUILD_REPORT BUILD_EVENTS BUILD_STDERR THREAD_ID', env, worker)
            assert (worker / f'{phase}.txt').is_file()
            calls = json.loads(Path(env['CALL_LOG']).read_text().splitlines()[-1])
            assert calls['args'][calls['args'].index('-m') + 1] == f'model-{phase}'
            assert calls['args'][calls['args'].index('-c') + 1] == 'model_reasoning_effort=xhigh'
            assert ('--dangerously-bypass-approvals-and-sandbox' in calls['args']) == (full_access == '1')
            assert 'offline' in calls['prompt'] and calls['cwd'] == str(worker)
            fix = 'P2="$PHASE_DIR/fix.md"\nprintf "Verify offline acceptance" >"$P2"\n'
            # A zero exit without a new report must not reuse the previous report.
            env['NO_REPORT'] = '1'
            shell(setup + '\n' + phase_state + '\n' + launched + '\n' + fix
                  + block('codex exec resume'), env, worker, succeeds=False,
                  error='Codex resume returned no report')
            del env['NO_REPORT']
            shell(setup + '\n' + phase_state + '\n' + launched + '\n' + fix
                            + block('codex exec resume'), env, worker)
            calls = json.loads(Path(env['CALL_LOG']).read_text().splitlines()[-1])
            phase_dir = Path(shell(phase_state + '\nprintf %s "$PHASE_DIR"', env, worker))
            assert len(list(phase_dir.glob('fix-report.*.events.jsonl'))) == 2
            assert (phase_dir / 'events.jsonl').is_file()
            assert calls['args'][1:3] == ['resume', f'thread-{phase}']
            assert calls['args'][calls['args'].index('-m') + 1] == f'model-{phase}'
            assert calls['args'][calls['args'].index('-c') + 1] == 'model_reasoning_effort=xhigh'
            assert ('--dangerously-bypass-approvals-and-sandbox' in calls['args']) == (full_access == '1')
        assert len(list(build_dir.glob('phase.*'))) == 2
        env['FAIL_WORKER'] = '1'
        shell(setup + '\n' + phase_state + '\n' + block('BUILD_REPORT="$PHASE_DIR/report.md"'),
              env, worker, succeeds=False, error='Codex build failed')
        del env['FAIL_WORKER']
        assert any('worker failed' in p.read_text() for p in build_dir.rglob('stderr.log'))
        assert build_dir.is_dir(), 'Failure diagnostics were deleted'
    # Default selection leaves the configured model to Codex.
    env.pop('CODEX_MODEL', None)
    env.pop('CODEX_EFFORT', None)
    default_state = shell(setup + '\n' + block('PHASE_DIR=') + '\ndeclare -p CODEX_ARGS', env, worker)
    assert 'declare -a CODEX_ARGS=()' in default_state
    # Execute initial and resumed reviews in both permission modes.
    for name in ['codex-review', 'grill-me-codex', 'grill-with-docs-codex']:
        codes = re.findall(r'```bash\n(.*?)\n```',
                           (ROOT / 'skills' / name / 'SKILL.md').read_text(), re.S)
        resume_index = next(i for i, code in enumerate(codes) if 'codex exec resume' in code)
        for full_access in ['0', '1']:
            review_dir = root / f'{name}-{full_access}'
            review_dir.mkdir()
            env.update(COWORK_FULL_ACCESS_AUTHORIZED=full_access, CODEX_MODEL='review-model',
                       PHASE='review', RUN_DIR=str(review_dir), WORK_DIR=str(review_dir))
            initial = shell('\n'.join(codes[:resume_index]) +
                            '\ndeclare -p CODEX_EXEC_ACCESS CODEX_RESUME_ACCESS MODEL_ARGS '
                            'RUN_DIR WORK_DIR VERDICT_FILE EVENTS_FILE STDERR_FILE THREAD_ID', env, worker)
            calls = json.loads(Path(env['CALL_LOG']).read_text().splitlines()[-1])
            assert calls['args'][calls['args'].index('--model') + 1] == 'review-model'
            assert ('--dangerously-bypass-approvals-and-sandbox' in calls['args']) == (full_access == '1')
            if full_access == '0':
                assert calls['args'][calls['args'].index('-s') + 1] == 'read-only'
            previous = Path(shell(initial + '\nprintf %s "$VERDICT_FILE"', env, worker))
            previous.write_text('VERDICT: APPROVED')
            env['NO_REPORT'] = '1'
            shell(initial + '\n' + codes[resume_index], env, worker, succeeds=False,
                  error='Codex resume returned no verdict')
            del env['NO_REPORT']
            shell(initial + '\n' + codes[resume_index], env, worker)
            calls = json.loads(Path(env['CALL_LOG']).read_text().splitlines()[-1])
            assert calls['args'][1:3] == ['resume', 'thread-review']
            assert calls['args'][calls['args'].index('--model') + 1] == 'review-model'
            assert ('--dangerously-bypass-approvals-and-sandbox' in calls['args']) == (full_access == '1')
            if full_access == '0':
                assert calls['args'][calls['args'].index('-c') + 1] == 'sandbox_mode="read-only"'
            assert len(list(previous.parent.glob('verdict.*.events.jsonl'))) == 2
            assert (previous.parent / 'events.jsonl').is_file()
            assert previous.read_text() == 'VERDICT: APPROVED'
print('Cowork build workflow: PASS (phases, models, access, artifacts, missing reports, failure)')
