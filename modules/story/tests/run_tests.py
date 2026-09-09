"""Story regression runner: --godot PATH [--test parser_test.gd --runtime-only].
Runs in a fresh relocated temporary project; keeps logs and report.json there.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def seed_stale_text_cache(project):
    """Reproduce Godot 4.x's pre-loader TextFile index without changing its UID.

    This is an intentionally version-sensitive fixture. Fail if Godot changes
    the cache schema so a passing test cannot silently skip the stale-cache case.
    """
    editor = project / '.godot/editor'
    names = ('original.ja.md', 'original.ja.story')
    cache = editor / 'filesystem_cache10'
    lines = cache.read_text(encoding='utf-8').splitlines()
    changed = set()
    for index, line in enumerate(lines):
        fields = line.split('::')
        if fields[0] in names:
            if len(fields) < 8 or '<>' not in fields[7]:
                raise ValueError('Unsupported Godot filesystem cache schema')
            fields[1] = 'TextFile'
            fields[7] = '<><><>0<>0<><>'
            lines[index] = '::'.join(fields)
            changed.add(fields[0])
    if changed != set(names):
        raise ValueError('Could not seed both stale Story file types')
    cache.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    updates = editor / 'filesystem_update4'
    if updates.exists():
        updates.write_text('\n'.join(p for p in updates.read_text(encoding='utf-8').splitlines()
                                     if p.removeprefix('res://') not in names) + '\n', encoding='utf-8')
    (editor / 'editor_layout.cfg').write_text('[ScriptEditor]\nopen_scripts=["res://original.ja.md", "res://original.ja.story"]\nselected_script="res://original.ja.md"\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--test', action='append', help='Runtime test filename (repeatable)')
    parser.add_argument('--runtime-only', action='store_true')
    parser.add_argument('--editor-export', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--timeout', type=float, default=120, help='Seconds per engine process')
    args = parser.parse_args()
    binary = shutil.which(args.godot)
    if not binary:
        parser.error('Godot executable not found; supply --godot or set GODOT.')
    module = Path(__file__).resolve().parents[1]
    tests = args.test or sorted(path.name for path in (module / 'tests').glob('*_test.gd'))
    for test in tests:
        if Path(test).name != test or not (module / 'tests' / test).is_file():
            parser.error('Unknown runtime test: ' + test)
    staging = Path(tempfile.mkdtemp(prefix='cherry-story-tests-'))
    project = staging / 'project'
    # Relocate the addon; rewrite serialized path hints as an installer would.
    module_path = 'features/narrative'
    relocated = project / module_path
    shutil.copytree(module, relocated, ignore=shutil.ignore_patterns('*.import', '__pycache__'))
    shutil.copytree(module.parents[1] / 'core', project / 'shared/cherry_core')
    for file in relocated.rglob('*'):
        if file.suffix in ('.tscn', '.tres'):
            file.write_text(file.read_text(encoding='utf-8').replace(
                'res://addons/cherry/modules/story/', f'res://{module_path}/'), encoding='utf-8')
    config = project / 'project.godot'
    config.write_text('''config_version=5
[application]
config/name="Cherry Story Tests"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding='utf-8')
    engine = staging / 'engine'
    engine.mkdir()
    env = os.environ.copy()
    for name in ('APPDATA', 'LOCALAPPDATA', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME'):
        env[name] = str(engine)
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    results = []
    print('Test artifacts: ' + str(staging), flush=True)

    def run(name, arguments, project_path=project, marker=None, expected_error=None, expected_file=None):
        command = [binary, '--headless', '--path', str(project_path), *arguments]
        begin = time.monotonic()
        try:
            result = subprocess.run(command, env=env, capture_output=True, text=True,
                                    encoding='utf-8', errors='replace', timeout=args.timeout,
                                    creationflags=flags)
            output = result.stdout + result.stderr
            code = result.returncode
        except subprocess.TimeoutExpired as exc:
            output = 'TIMEOUT\n' + str(exc.stdout or '') + str(exc.stderr or '')
            code = -1
        errors = [line for line in output.splitlines() if
                  (line.startswith(('SCRIPT ERROR:', 'ERROR:', 'FAIL')) or 'CRASH' in line) and
                  'Failed to read the root certificate store' not in line]
        if expected_error:
            # Godot can return zero on export failure; allow only this diagnostic
            # and its platform summary, never unrelated script errors or crashes.
            unexpected = [line for line in errors if expected_error not in line and
                          not line.startswith('ERROR: Project export for preset')]
            passed = expected_error in output and not unexpected and code in (0, 1)
        else:
            passed = code == 0 and not errors and (marker is None or marker in output)
        if expected_file is not None and not expected_file.is_file():
            passed = False
            output += '\nFAIL: Expected output file was not created: ' + str(expected_file)
        counts = re.findall(r'(\d+) passed, (\d+) failed', output)
        item = dict(name=name, passed=passed, exit_code=code,
                    seconds=round(time.monotonic() - begin, 2),
                    checks=sum(int(a) + int(b) for a, b in counts), command=command)
        results.append(item)
        (staging / (name + '.log')).write_text(output, encoding='utf-8')
        (staging / 'report.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
        print(f'{"PASS" if passed else "FAIL"} {name} ({item["seconds"]}s, {item["checks"]} checks)', flush=True)
        if not passed:
            print(output[-14000:], flush=True)
        return passed

    if not run('import', ['--editor', '--import']):
        return 1
    for test in tests:
        run(test.removesuffix('.gd'), ['--script', f'res://{module_path}/tests/{test}'], marker='passed, 0 failed')

    if not args.runtime_only:
        host = project / 'addons/story_test_host'
        host.mkdir(parents=True)
        (host / 'plugin.gd').write_text(f'@tool\nextends "res://{module_path}/tests/editor_host.gd"\n', encoding='utf-8')
        (host / 'plugin.cfg').write_text('[plugin]\nname="Story"\ndescription="Isolated regression host"\nauthor="Cherry"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
        config.write_text(config.read_text(encoding='utf-8').replace('config/name="Cherry Story Tests"',
            'config/name="Cherry Story Tests"\nrun/main_scene="res://export_probe.tscn"') +
            '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/story_test_host/plugin.cfg")\n', encoding='utf-8')
        for extension in ('md', 'story'):
            for name in ('original', 'copy'):
                (project / f'{name}.ja.{extension}').write_bytes('真尋@happy: Hello [wait:1s]\r\n'.encode('utf-8'))
        (project / 'README.md').write_text('# Documentation\n', encoding='utf-8')
        (project / 'unused.md').write_text(chr(96) + 'else:' + chr(96) + '\nGuide: Orphan', encoding='utf-8')
        (project / 'runtime_config.json').write_text('{"test": true}', encoding='utf-8')
        (project / 'export_entry.tres').write_text(f'''[gd_resource type="Resource" script_class="MarkdownStory" format=3]
[ext_resource type="Script" path="res://{module_path}/gdscript/markdown_story.gd" id="1"]
[resource]
script = ExtResource("1")
source_file = "res://{module_path}/examples/stories/mahiro.ja.md"
extra_files = PackedStringArray("res://runtime_config.json")
''', encoding='utf-8')
        (project / 'export_probe.tscn').write_text(f'''[gd_scene format=3]
[ext_resource type="Script" path="res://{module_path}/tests/export_runtime.gd" id="1"]
[ext_resource type="PackedScene" path="res://{module_path}/examples/story_demo.tscn" id="2"]
[ext_resource type="Resource" path="res://export_entry.tres" id="3"]
[ext_resource type="Resource" path="res://copy.ja.story" id="4"]
[node name="ExportProbe" type="Node"]
script = ExtResource("1")
metadata/demo = ExtResource("2")
metadata/entry = ExtResource("3")
metadata/story_format = ExtResource("4")
''', encoding='utf-8')
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
        if run('editor_import', ['--editor', '--import']):
            run('editor', ['--editor', '--', '--story-editor-check'], marker='Editor total:')
            seed_stale_text_cache(project)
            run('icons', ['--editor', '--', '--story-icon-check'], marker='Icons:')
            # Do not restore Script TextFile resources into the export process.
            (project / '.godot/editor/editor_layout.cfg').write_text('', encoding='utf-8')
            pack = staging / 'story_test.pck'
            if run('export', ['--editor', '--export-pack', 'Story', str(pack)], expected_file=pack):
                empty = staging / 'pack_runtime'
                empty.mkdir()
                run('pack_runtime', ['--main-pack', str(pack)], empty, marker='Export PCK:')
            story = relocated / 'examples/stories/mahiro.ja.md'
            original = story.read_bytes()
            try:
                story.write_bytes(original + b'\nGuide: [undefined_export_test_command]\n')
                run('invalid_story_export', ['--editor', '--export-pack', 'Story', str(staging / 'invalid.pck')],
                    expected_error='Unknown inline command: undefined_export_test_command')
            finally:
                story.write_bytes(original)
            presets = project / 'export_presets.cfg'
            original = presets.read_text(encoding='utf-8')
            try:
                presets.write_text(original.replace('exclude_filter=""', 'exclude_filter="*room.svg"'), encoding='utf-8')
                run('excluded_asset_export', ['--editor', '--export-pack', 'Story', str(staging / 'excluded.pck')],
                    expected_error='Required dependency is excluded by the export preset:')
            finally:
                presets.write_text(original, encoding='utf-8')
    failed = sum(not r['passed'] for r in results)
    print(f'Total: {len(results) - failed} stages passed, {failed} failed; {sum(r["checks"] for r in results)} checks.', flush=True)
    print('Report: ' + str(staging / 'report.json'), flush=True)
    return int(failed > 0)


if __name__ == '__main__':
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(encoding='utf-8')
    raise SystemExit(main())
