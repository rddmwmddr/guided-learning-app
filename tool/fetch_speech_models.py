#!/usr/bin/env python3
"""Download pinned upstream voice assets. Standard library only; no keys required."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def verified(item):
    path = ROOT / item['path']
    return path.is_file() and digest(path) == item['sha256']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    groups = json.loads((ROOT / 'tool/speech_models.json').read_text())
    for group in groups:
        missing = [item for item in group['files'] if not verified(item)]
        if not missing:
            print('Verified:', group['files'][0]['path'].rsplit('/', 1)[0])
            continue
        if args.verify_only:
            raise SystemExit('Missing or invalid model assets: run python3 tool/fetch_speech_models.py')
        with tempfile.TemporaryDirectory(prefix='manmanxiang-model-') as temporary:
            download = Path(temporary) / 'download'
            print('Downloading', group['url'])
            with urllib.request.urlopen(group['url'], timeout=120) as response, download.open('wb') as out:
                shutil.copyfileobj(response, out)
            if digest(download) != group['sha256']:
                raise SystemExit('Upstream archive checksum mismatch; refusing to use it.')
            archive = tarfile.open(download, 'r:bz2') if group['archive'] else None
            try:
                for item in missing:
                    target = (ROOT / item['path']).resolve()
                    if not target.is_relative_to(ROOT / 'assets/speech'):
                        raise SystemExit('Invalid asset destination')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    staging = target.with_suffix(target.suffix + '.download')
                    try:
                        if archive:
                            member = archive.getmember(item['member'])
                            if not member.isfile():
                                raise SystemExit('Refusing non-regular archive member')
                            with archive.extractfile(member) as source, staging.open('wb') as out:
                                shutil.copyfileobj(source, out)
                        else:
                            shutil.copyfile(download, staging)
                        if digest(staging) != item['sha256']:
                            raise SystemExit('Asset checksum mismatch: ' + item['path'])
                        os.replace(staging, target)
                    finally:
                        staging.unlink(missing_ok=True)
            finally:
                if archive:
                    archive.close()
    print('All voice assets are ready.')

if __name__ == '__main__':
    main()
