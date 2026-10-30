#!/usr/bin/env python3
"""Reject accidentally tracked credentials, private machine data, and model binaries."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
secret = re.compile(rb'(?:sk-(?:or-v1-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[A-Z0-9]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')
errors = []
for name in filter(None, paths):
    path = root / name
    if not path.is_file():
        continue
    if name.startswith(('.release/', '.dart_tool/', 'build/')) or name in ('android/key.properties', 'android/local.properties', '.vscode/settings.json') or path.suffix in ('.jks', '.keystore', '.p12', '.p8', '.mobileprovision', '.onnx', '.apk', '.aab', '.ipa') or path.name.startswith('.env'):
        errors.append(name + ': private/generated file')
    if path.stat().st_size > 20 * 1024 * 1024:
        errors.append(name + ': unexpectedly large file')
    if path.stat().st_size < 10 * 1024 * 1024:
        data = path.read_bytes()
        if b'\0' not in data:
            if secret.search(data):
                errors.append(name + ': possible credential (value hidden)')
            if re.search(rb'/Users/[A-Za-z0-9._-]+/', data):
                errors.append(name + ': personal absolute path')
            if re.search(rb'DEVELOPMENT_TEAM = [A-Z0-9]{10};', data):
                errors.append(name + ': personal Apple development team')
if errors:
    raise SystemExit('\n'.join(errors))
print('Public source checks passed.')
