"""Check configuration presence; never print secret contents."""
import os
import sys
from pathlib import Path

NAMES = ('AAW_RELEASE_KEYSTORE_BASE64', 'AAW_RELEASE_STORE_PASSWORD',
         'AAW_RELEASE_KEY_ALIAS', 'AAW_RELEASE_KEY_PASSWORD')
missing = [name for name in NAMES if not os.environ.get(name)]
configured = not missing
if os.environ.get('GITHUB_OUTPUT'):
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        output.write('configured=' + str(configured).lower() + '\n')
if missing:
    message = 'Owner signing setup pending. Add these repository secrets: ' + ', '.join(missing)
    print('::notice title=Owner signing setup pending::' + message)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as summary:
            summary.write('## Owner signing setup pending\n\n' + message + '\n\nNo production APK was published. Use the matching files in the private owner signing backup.\n')
    sys.exit(1 if os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch' else 0)
print('Permanent owner signing configuration is present. Values remain private.')
