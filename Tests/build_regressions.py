"""Exercise real build.sh control flow using isolated fake signing/notary tools."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
STUBS = {
    "xcrun": r'''printf '%s\n' "$*" >> tool-calls
case "$*" in
    *--show-sdk-version*) echo 26.0 ;;
    *--show-sdk-build-version*) echo 26A ;;
    "notarytool history"*)
        if [ "${AUDIT_NO_PROFILE:-0}" != "0" ]; then echo "${AUDIT_PROFILE_ERROR:-Fixture profile unavailable}" >&2; fi
        exit "${AUDIT_NO_PROFILE:-0}" ;;
    "notarytool submit"*) exit "${AUDIT_NOTARY_FAILURE:-0}" ;;
    "stapler staple"*|"stapler validate"*) exit "${AUDIT_NO_TICKET:-0}" ;;
    *) exit 1 ;;
esac''',
    "xcodebuild": "echo 'Xcode 26.0'; echo 'Build version 26A'",
    "security": r'''if [ "${AUDIT_NO_IDENTITY:-0}" = "0" ]; then echo '  1) FIXTURE "Developer ID Application: Audit Fixture (AUDIT)"'; fi''',
    "swiftc": r'''while [ "$#" -gt 0 ]; do if [ "$1" = '-o' ]; then shift; : > "$1"; fi; shift; done''',
    "codesign": "exit 0",
    "create-dmg": r'''for arg do prev="${last:-}"; last="$arg"; done; echo INVALID > "$prev"; exit 1''',
    "hdiutil": r'''for arg do last="$arg"; done; echo VALID > "$last"''',
    "spctl": 'exit "${AUDIT_GATEKEEPER_FAILURE:-0}"',
    "SetFile": "exit 0",
}


def case(name, mode="direct", expected=0, artifact=None, preserve=False, error=None, **flags):
    with tempfile.TemporaryDirectory(prefix="talktype-build-test-") as temp:
        work = Path(temp)
        fake = work / "bin"
        fake.mkdir()
        for name_, body in STUBS.items():
            script = fake / name_
            script.write_text("#!/bin/bash\n" + body + "\n")
            script.chmod(0o755)
        for path in ["build.sh", "TalkType.swift", "TalkType.entitlements", "TalkType.sandbox.entitlements", "PrivacyInfo.xcprivacy"]:
            shutil.copy(ROOT / path, work / path)
        (work / "Assets").mkdir()
        for folder in ["build", "dist"]:
            (work / folder).mkdir()
            (work / folder / "previous-good-artifact").write_text("preserve me")
        env = os.environ.copy()
        # Prevent a developer's ordinary release settings from leaking into the fixtures.
        for key in ["LOCAL_BUILD", "ALLOW_ADHOC_MAS", "SKIP_NOTARIZE", "UNIVERSAL", "VERSION", "BUILD_NUMBER"]:
            env.pop(key, None)
        env.update(PATH=f"{fake}:/usr/bin:/bin:/usr/sbin:/sbin", NOTARY_PROFILE="fixture")
        env.update({k: str(v) for k, v in flags.items()})
        result = subprocess.run(["/bin/bash", "build.sh", mode], cwd=work, env=env, text=True, capture_output=True, timeout=30)
        assert result.returncode == expected, (name, result.returncode, result.stdout, result.stderr)
        if error:
            assert error in result.stderr, (name, result.stderr)
            assert "not found" not in result.stdout, name
        release = work / "dist/TalkType-1.0.dmg"
        local = work / "dist/TalkType-1.0-LOCAL-ONLY.dmg"
        if preserve:
            assert all((work / folder / "previous-good-artifact").is_file() for folder in ["build", "dist"]), name
        elif artifact == "release":
            assert release.read_text().strip() == "VALID", name
        elif artifact == "local":
            assert local.read_text().strip() == "VALID" and not release.exists(), name
            assert "notarytool submit" not in (work / "tool-calls").read_text(), name
        else:
            assert not release.exists(), name
        print("PASS", name, flush=True)


case("invalid mode preserves previous artifacts", mode="invalid", expected=1, preserve=True)
case("missing Developer ID preserves previous artifacts", expected=1, preserve=True, AUDIT_NO_IDENTITY=1)
case("missing MAS certificates preserves previous artifacts", mode="mas", expected=1, preserve=True)
case("failed create-dmg discards partial image before fallback", artifact="release")
case("Gatekeeper rejection removes release image", expected=1, AUDIT_GATEKEEPER_FAILURE=1)
case("notary command failure removes release image", expected=1, AUDIT_NOTARY_FAILURE=1)
case("missing notarization ticket rejects release", expected=1, AUDIT_NO_PROFILE=1, AUDIT_NO_TICKET=1)
case("Apple agreement failure is reported accurately", expected=1, AUDIT_NO_PROFILE=1,
     AUDIT_PROFILE_ERROR="HTTP 403: required agreement missing", error="HTTP 403: required agreement missing")
case("local image is distinct and never submitted", artifact="local", LOCAL_BUILD=1, AUDIT_NO_IDENTITY=1, AUDIT_NO_TICKET=1)
