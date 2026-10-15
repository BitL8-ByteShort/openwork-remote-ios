#!/usr/bin/env python3
"""Check a built iOS Release bundle. This does not qualify runtime or distribution."""
import argparse
import hashlib
import json
import pathlib
import plistlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=pathlib.Path, required=True)
args = parser.parse_args()
with (args.app / 'Info.plist').open('rb') as file:
    info = plistlib.load(file)
executable_name = info['CFBundleExecutable']
if not isinstance(executable_name, str) or pathlib.Path(executable_name).name != executable_name or executable_name in {'.', '..'}:
    parser.error('Invalid executable name')
executable = args.app / executable_name
binary = executable.read_bytes()
markers = ['BridgeClient', '/v1/host', '/v1/device', '/v1/pair', '-ui-testing-']
# Xcode Debug apps can have a tiny launcher with their real code in a separate
# .debug.dylib. Inspect all bundled Mach-O images, not only the launcher.
magic = {bytes.fromhex(value) for value in ['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
                                          'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}
images = {}
retired = []
for path in args.app.rglob('*'):
    if not path.is_file():
        continue
    with path.open('rb') as file:
        if file.read(4) not in magic:
            continue
        file.seek(0)
        content = file.read()
    name = str(path.relative_to(args.app))
    images[name] = hashlib.sha256(content).hexdigest()
    retired.extend(name + ': ' + marker for marker in markers if marker.encode() in content)
failures = []
if executable_name not in images:
    failures.append('The main executable is not a Mach-O image')
if retired:
    failures.append('Retired wire implementation or DEBUG fixture markers: ' + ', '.join(retired))
if any(name.endswith('.debug.dylib') for name in images):
    failures.append('A DEBUG implementation dylib is bundled')
if info.get('CFBundleIdentifier') != 'com.saltypanda.openworkremote':
    failures.append('Unexpected app identity')
if set(info.get('UIDeviceFamily', [])) != {1, 2}:
    failures.append('Both iPhone and iPad device families are required')
orientations = set(info.get('UISupportedInterfaceOrientations~ipad',
                            info.get('UISupportedInterfaceOrientations', [])))
if not {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
        'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'} <= orientations:
    failures.append('iPad must declare portrait and both landscape orientations')
if info.get('UIRequiresFullScreen', False):
    failures.append('iPad multitasking must not be disabled')
report = {'scope': 'Static built-bundle checks only; runtime, signing and distribution are separate',
          'pass': not failures, 'binarySHA256': hashlib.sha256(binary).hexdigest(),
          'codeImages': images,
          'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion'),
          'failures': failures}
print(json.dumps(report, indent=2))
raise SystemExit(bool(failures))
