"""Run Story in an isolated relocated project using an installed Godot binary.

python run_tests.py --godot /path/to/godot [--test parser_test.gd]
The staging project and engine user data remain beneath the host's .godot folder.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
parser.add_argument('--test', action='append')
args = parser.parse_args()
module = Path(__file__).resolve().parents[1]
workspace = module.parents[3]
staging = workspace / '.godot/cherry_story_tests'
project = staging / 'project'
project.mkdir(parents=True, exist_ok=True)
shutil.copytree(module, project / 'features/narrative', dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('*.import', '__pycache__'))
shutil.copytree(module.parents[1] / 'core', project / 'shared/cherry_core', dirs_exist_ok=True)
(project / 'project.godot').write_text('''config_version=5
[application]
config/name="Cherry Story Tests"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding='utf-8')
env = os.environ.copy()
env['APPDATA'] = env['LOCALAPPDATA'] = str(staging / 'engine')
Path(env['APPDATA']).mkdir(parents=True, exist_ok=True)
flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0

def run(arguments):
    command = [args.godot, '--headless', '--path', str(project), *arguments]
    result = subprocess.run(command, env=env, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=90, creationflags=flags)
    output = result.stdout + result.stderr
    # This sandbox may not expose Windows' certificate store; tests use no network.
    errors = [line for line in output.splitlines() if
              ('SCRIPT ERROR:' in line or line.startswith('ERROR:')) and
              'Failed to read the root certificate store' not in line]
    if result.returncode or errors:
        print(output)
        raise SystemExit(result.returncode or 1)
    for line in result.stdout.splitlines():
        if 'passed' in line or 'failed' in line:
            print(line, flush=True)

run(['--editor', '--import'])
tests = args.test or sorted(path.name for path in (module / 'tests').glob('*_test.gd'))
for test in tests:
    print(f'Running {test}', flush=True)
    run(['--script', f'res://features/narrative/tests/{test}'])
