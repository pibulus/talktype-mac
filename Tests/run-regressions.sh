#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
AUDIT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/talktype-regressions.XXXXXX")
trap 'rm -rf "$AUDIT_TMP"' EXIT
python3 - "$AUDIT_TMP" <<'PY'
from pathlib import Path
import plistlib,sys,uuid
out=Path(sys.argv[1]); source=Path('TalkType.swift').read_text()
# Keep production access controls: test extensions are compiled in the same file.
# Substitute only the Security boundary so tests never touch the user's Keychain.
for api, mock in [('SecItemUpdate(', 'AuditKeychain.update('), ('SecItemAdd(', 'AuditKeychain.add('), ('SecItemCopyMatching(', 'AuditKeychain.read('), ('SecItemDelete(', 'AuditKeychain.delete(')]:
    source=source.replace(api,mock)
(out/'Regression.swift').write_text(source+'\n'+Path('Tests/Regression.swift').read_text())
app=out/'Regression.app/Contents';(app/'MacOS').mkdir(parents=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.pibulus.talktype.regression.'+uuid.uuid4().hex,'CFBundleExecutable':'Regression','CFBundlePackageType':'APPL'}))
PY
TEST_ARCH=$(uname -m)
xcrun swiftc -parse-as-library -D TALKTYPE_TESTING -target "${TEST_ARCH}-apple-macos13.0" \
    "$AUDIT_TMP/Regression.swift" -o "$AUDIT_TMP/Regression.app/Contents/MacOS/Regression"
"$AUDIT_TMP/Regression.app/Contents/MacOS/Regression"
python3 Tests/build_regressions.py
