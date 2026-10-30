#!/usr/bin/env python3
"""Create a private Android release key locally. Never commit or upload .release/."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
private = root / '.release'
properties = root / 'android/key.properties'
key = private / 'release.jks'
if properties.exists() or key.exists():
    raise SystemExit('Signing files already exist; refusing to overwrite. Back them up.')
keytool = shutil.which('keytool')
if os.environ.get('JAVA_HOME'):
    keytool = str(Path(os.environ['JAVA_HOME']) / 'bin/keytool')
if not keytool:
    raise SystemExit('Java 17 keytool is required.')
os.umask(0o077)
private.mkdir(mode=0o700, exist_ok=True)
password = secrets.token_hex(32)
env = dict(os.environ, MANMANXIANG_KEY_PASSWORD=password)
subprocess.run([keytool, '-genkeypair', '-keystore', str(key), '-storetype', 'PKCS12',
    '-alias', 'manmanxiang-release', '-storepass:env', 'MANMANXIANG_KEY_PASSWORD',
    '-keypass:env', 'MANMANXIANG_KEY_PASSWORD', '-keyalg', 'RSA', '-keysize', '4096',
    '-validity', '10000', '-dname', 'CN=Manmanxiang Open Source Release', '-noprompt'],
    env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
properties.write_text('storeFile=' + str(key) + '\nstorePassword=' + password + '\nkeyAlias=manmanxiang-release\nkeyPassword=' + password + '\n')
key.chmod(0o600)
properties.chmod(0o600)
print('Created local release signing files. Back up .release/ AND android/key.properties privately.')
print('Neither file is uploaded to GitHub.')
