#!/usr/bin/env python3
"""Select an installed visionOS simulator and download a runtime only if needed."""

import json
import os
from pathlib import Path
import subprocess


def output(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


def version_pair(value):
    return tuple(int(part) for part in value.split('.')[:2])


def compatible_runtimes(sdk_version):
    runtimes = json.loads(output('xcrun', 'simctl', 'list', 'runtimes', '--json'))
    return [
        runtime for runtime in runtimes['runtimes']
        if runtime['name'].startswith('visionOS ')
        and runtime.get('isAvailable', False)
        and (26, 0) <= version_pair(runtime['version']) <= version_pair(sdk_version)
    ]


def main():
    sdk_version = output('xcrun', '--sdk', 'xrsimulator', '--show-sdk-version')
    runtimes = compatible_runtimes(sdk_version)
    if not runtimes:
        subprocess.run([
            'xcodebuild', '-downloadPlatform', 'visionOS', '-buildVersion', sdk_version
        ], check=True)
        runtimes = compatible_runtimes(sdk_version)
    if not runtimes:
        raise RuntimeError('No available visionOS runtime supports the selected SDK.')

    runtime = max(runtimes, key=lambda item: version_pair(item['version']))
    device_type = next(
        item['identifier'] for item in runtime['supportedDeviceTypes']
        if item['name'] == 'Apple Vision Pro'
    )
    devices = json.loads(output('xcrun', 'simctl', 'list', 'devices', '--json'))
    candidates = [
        device for device in devices['devices'].get(runtime['identifier'], [])
        if device.get('isAvailable', False)
        and device.get('deviceTypeIdentifier') == device_type
        and not device['name'].startswith('Clone ')
    ]
    if candidates:
        udid = candidates[0]['udid']
    else:
        udid = output('xcrun', 'simctl', 'create', 'DesignSphere CI',
                      device_type, runtime['identifier'])

    destination = f'platform=visionOS Simulator,id={udid}'
    print(f"Using {runtime['name']} with SDK {sdk_version}: {destination}")
    if os.environ.get('GITHUB_ENV'):
        with Path(os.environ['GITHUB_ENV']).open('a') as environment:
            environment.write(f'DESIGNSPHERE_TEST_DESTINATION={destination}\n')


if __name__ == '__main__':
    main()
