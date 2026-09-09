"""Run Story in an isolated relocated project using an installed Godot binary.

python run_tests.py --godot /path/to/godot [--test parser_test.gd]
The staging project and engine user data remain beneath the host's .godot folder.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
parser.add_argument('--test', action='append')
parser.add_argument('--editor-export', action='store_true', help='Also verify the editor plugin and a selected-scene PCK in an empty directory')
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

def run(arguments, project_path=project, expected_error=None):
    command = [args.godot, '--headless', '--path', str(project_path), *arguments]
    result = subprocess.run(command, env=env, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=90, creationflags=flags)
    output = result.stdout + result.stderr
    if expected_error:
        if expected_error not in output:
            print(output)
            raise SystemExit('Expected export diagnostic was not reported: ' + expected_error)
        print('Export error reporting: passed', flush=True)
        return
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

if args.editor_export:
    host = project / 'addons/story_test_host'
    host.mkdir(parents=True, exist_ok=True)
    (host / 'plugin.gd').write_text((module / 'tests/editor_host.gd').read_text(encoding='utf-8').replace(
        '../editor/story_project_files.gd', 'res://features/narrative/editor/story_project_files.gd'), encoding='utf-8')
    (host / 'plugin.cfg').write_text('[plugin]\nname="Story test host"\ndescription=""\nauthor="Cherry"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
    config = project / 'project.godot'
    config.write_text(config.read_text(encoding='utf-8').replace('config/name="Cherry Story Tests"',
        'config/name="Cherry Story Tests"\nrun/main_scene="res://export_probe.tscn"') +
        '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/story_test_host/plugin.cfg")\n', encoding='utf-8')
    (project / 'export_probe.tscn').write_text('''[gd_scene format=3]
[ext_resource type="Script" path="res://features/narrative/tests/export_runtime.gd" id="1"]
[ext_resource type="PackedScene" path="res://features/narrative/examples/story_demo.tscn" id="2"]
[node name="ExportProbe" type="Node"]
script = ExtResource("1")
metadata/dependency = ExtResource("2")
''', encoding='utf-8')
    # A selected export must ignore an unrelated, deliberately invalid library.
    (project / 'unused.md').write_text('`else:`\nGuide: Orphan', encoding='utf-8')
    (project / 'unused.tres').write_text('''[gd_resource type="Resource" script_class="StoryLibrary" format=3]
[ext_resource type="Script" path="res://features/narrative/gdscript/story_library.gd" id="1"]
[resource]
script = ExtResource("1")
stories = {"unused": {"en": "unused.md"}}
''', encoding='utf-8')
    library = project / 'features/narrative/examples/story_library.tres'
    library.write_text(library.read_text(encoding='utf-8') + '\nextra_files = PackedStringArray("res://runtime_config.json")\n', encoding='utf-8')
    (project / 'runtime_config.json').write_text('{"test": true}', encoding='utf-8')
    (project / 'export_presets.cfg').write_text('''[preset.0]
name="Story"
platform="Windows Desktop"
runnable=true
export_filter="scenes"
export_files=PackedStringArray("res://export_probe.tscn")
include_filter=""
exclude_filter=""
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
''', encoding='utf-8')
    run(['--editor', '--import'])
    print('Running editor integration', flush=True)
    run(['--editor', '--', '--story-editor-check'])
    pack = staging / 'story_test.pck'
    print('Exporting selected-scene PCK', flush=True)
    run(['--editor', '--export-pack', 'Story', str(pack)])
    empty = staging / 'pack_runtime'
    empty.mkdir(parents=True, exist_ok=True)
    run(['--main-pack', str(pack)], empty)
    story = project / 'features/narrative/examples/stories/mahiro.ja.md'
    original = story.read_text(encoding='utf-8')
    try:
        story.write_text(original + '\nGuide: [undefined_export_test_command]\n', encoding='utf-8')
        run(['--editor', '--export-pack', 'Story', str(staging / 'invalid_story.pck')],
            expected_error='Unknown inline command: undefined_export_test_command')
    finally:
        story.write_text(original, encoding='utf-8')
    presets = project / 'export_presets.cfg'
    original_presets = presets.read_text(encoding='utf-8')
    try:
        presets.write_text(original_presets.replace('exclude_filter=""', 'exclude_filter="*room.svg"'), encoding='utf-8')
        run(['--editor', '--export-pack', 'Story', str(staging / 'excluded_asset.pck')],
            expected_error='Required dependency is excluded by the export preset:')
    finally:
        presets.write_text(original_presets, encoding='utf-8')
