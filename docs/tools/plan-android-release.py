"""Validate monotonic Android updates from public release metadata; no secrets."""
import argparse
import json
import re
from pathlib import Path


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d+\.\d+(?:\.\d+){0,2}', value):
        raise ValueError('Use a numeric release version such as 1.4 or 1.4.1')
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (4-len(parts))


def plan(gradle, signing, releases, previous=None):
    name = re.search(r"versionName\s+'([^']+)'", gradle).group(1)
    code = int(re.search(r'versionCode\s+(\d+)', gradle).group(1))
    current = version_tuple(name)
    if code < signing.get('baseline_version_code', 5):
        raise ValueError('versionCode is below the first permanent owner release')
    if current < version_tuple(signing.get('baseline_version_name', '1.4')):
        raise ValueError('Version is below the first permanent owner release')
    if not isinstance(releases, list):
        raise ValueError('Release API did not return a list')
    published = []
    for release in releases:
        tag = release.get('tag_name', '')
        if release.get('draft') or release.get('prerelease') or not tag.startswith('android-v'):
            continue
        published.append((version_tuple(tag[9:]), tag))
    latest = max(published, default=None)
    target = 'android-v' + name
    if latest and current < latest[0]:
        raise ValueError('Refusing an older Android release')
    if any(tag == target for _, tag in published):
        return dict(release_needed='false', version_name=name, version_code=str(code), previous_tag='')
    if latest and current <= latest[0]:
        raise ValueError('Increase versionName before publishing another Android release')
    if previous is not None:
        if not latest:
            raise ValueError('Unexpected previous release metadata')
        if previous.get('package_name') != 'com.arifagroworks.combined':
            raise ValueError('Previous package identity mismatch')
        if previous.get('certificate_sha256') != signing['certificate_sha256']:
            raise ValueError('Previous release signer differs from the permanent owner signer')
        if 'android-v' + previous.get('version_name', '') != latest[1]:
            raise ValueError('Previous release metadata does not match its tag')
        old_code = previous.get('version_code')
        if type(old_code) is not int or code <= old_code:
            raise ValueError('Increase versionCode so installed owner apps can update')
    return dict(release_needed='true', version_name=name, version_code=str(code),
                previous_tag=latest[1] if latest else '')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--releases', required=True)
    parser.add_argument('--previous-metadata')
    parser.add_argument('--gradle', default='android-app/app/build.gradle')
    parser.add_argument('--signing', default='android-app/release-signing.json')
    parser.add_argument('--output')
    args = parser.parse_args()
    previous = json.loads(Path(args.previous_metadata).read_text()) if args.previous_metadata else None
    result = plan(Path(args.gradle).read_text(), json.loads(Path(args.signing).read_text()),
                  json.loads(Path(args.releases).read_text()), previous)
    if args.output:
        with Path(args.output).open('a') as output:
            output.writelines(key+'='+value+'\n' for key,value in result.items())
    print(json.dumps(result))


if __name__ == '__main__':
    main()
