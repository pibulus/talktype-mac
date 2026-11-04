"""Exercise real build.sh control flow using isolated fake signing/notary tools."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
STUBS = {
    "xcrun": r'''printf '%s\n' "$*" >> tool-calls
case "$*" in
    *--show-sdk-version*) echo 26.0 ;;
    *--show-sdk-build-version*) echo 26A ;;
    actool*)
        compile_dir=""
        plist_out=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --compile) shift; compile_dir="$1" ;;
                --output-partial-info-plist) shift; plist_out="$1" ;;
            esac
            shift
        done
        if [ -n "${compile_dir}" ] && [ "${AUDIT_EMPTY_CAR:-0}" = "0" ]; then
            echo "CAR" > "${compile_dir}/Assets.car"
        fi
        if [ -n "${plist_out}" ]; then
            echo '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "${plist_out}"
        fi
        exit 0 ;;
    "notarytool history"*)
        if [ "${AUDIT_NO_PROFILE:-0}" != "0" ]; then echo "${AUDIT_PROFILE_ERROR:-Fixture profile unavailable}" >&2; fi
        exit "${AUDIT_NO_PROFILE:-0}" ;;
    "notarytool submit"*) exit "${AUDIT_NOTARY_FAILURE:-0}" ;;
    "stapler staple"*|"stapler validate"*) exit "${AUDIT_NO_TICKET:-0}" ;;
    *) exit 1 ;;
esac''',
    "xcodebuild": "echo 'Xcode 26.0'; echo 'Build version 26A'",
    "security": r'''if [ "${1:-}" = "cms" ]; then
    if [ "${AUDIT_PROFILE_DEV:-0}" = "1" ]; then cat profile-dev.plist
    elif [ "${AUDIT_PROFILE_WRONG_APPID:-0}" = "1" ]; then cat profile-wrong-appid.plist
    else cat profile-ok.plist
    fi
    exit 0
fi
if [ "${1:-}" = "find-certificate" ]; then
    echo "-----BEGIN CERTIFICATE-----"
    echo "RklYVFVSRQ=="
    echo "-----END CERTIFICATE-----"
    exit 0
fi
if [ "${AUDIT_MAS_IDENTITY:-0}" = "1" ]; then
    case "$*" in
        *"-p codesigning"*) echo '  1) FIXTURE "Apple Distribution: Audit Fixture (AUDIT)"' ;;
        *"-p basic"*) echo '  1) FIXTURE "3rd Party Mac Developer Installer: Audit Fixture (AUDIT)"' ;;
    esac
elif [ "${AUDIT_NO_IDENTITY:-0}" = "0" ]; then
    echo '  1) FIXTURE "Developer ID Application: Audit Fixture (AUDIT)"'
fi''',
    "swiftc": r'''while [ "$#" -gt 0 ]; do if [ "$1" = '-o' ]; then shift; echo "BIN" > "$1"; fi; shift; done''',
    "lipo": r'''if [ "${1:-}" = "-archs" ]; then echo "${AUDIT_LIPO_ARCHS:-x86_64 arm64}"; exit 0; fi
while [ "$#" -gt 0 ]; do if [ "$1" = '-output' ]; then shift; echo "FATBIN" > "$1"; fi; shift; done''',
    "iconutil": r'''while [ "$#" -gt 0 ]; do if [ "$1" = '-o' ]; then shift; mkdir -p "$1"; echo "PNG" > "$1/icon_16x16.png"; fi; shift; done''',
    "otool": r'''if [ "${AUDIT_LINK_AX:-0}" = "1" ]; then
    echo "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices"
fi
exit 0''',
    "xattr": r'''if [ "${AUDIT_QUARANTINE:-0}" = "1" ] && [ "${1:-}" = "-lr" ]; then
    echo "build/mas/TalkType.app: com.apple.quarantine: 0081"
fi
exit 0''',
    "codesign": r'''if [ "${1:-}" = "-d" ]; then
    if [ "${AUDIT_NO_SIGNED_ENTS:-0}" = "0" ]; then cat signed-ents.plist; fi
    exit 0
fi
exit 0''',
    "productbuild": r'''printf 'productbuild %s\n' "$*" >> tool-calls
if [ "${AUDIT_PKG_FAILURE:-0}" != "0" ]; then exit 1; fi
for arg do last="$arg"; done
echo "VALID_PKG" > "$last"''',
    "pkgutil": r'''printf 'pkgutil %s\n' "$*" >> tool-calls
exit "${AUDIT_PKG_SIG_FAILURE:-0}"''',
    "create-dmg": r'''for arg do prev="${last:-}"; last="$arg"; done; echo INVALID > "$prev"; exit 1''',
    "hdiutil": r'''for arg do last="$arg"; done; echo VALID > "$last"''',
    "spctl": 'exit "${AUDIT_GATEKEEPER_FAILURE:-0}"',
    "SetFile": "exit 0",
}

# Fixtures the build.sh release gates read. The real `security cms -D` and
# `codesign -d --entitlements` output is simulated here so the gates stay real.
PROFILE_PLIST = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Entitlements</key><dict>
        <key>com.apple.application-identifier</key><string>V433H655PN.com.pibulus.talktype</string>
        <key>com.apple.developer.team-identifier</key><string>V433H655PN</string>
    </dict>
    <key>DeveloperCertificates</key><array><data>RklYVFVSRQ==</data></array>
</dict></plist>'''

PROFILE_PLIST_DEV = PROFILE_PLIST.replace(
    "<key>DeveloperCertificates</key>",
    "<key>ProvisionedDevices</key><array><string>00000000-0000-0000-0000-000000000000</string></array>\n    <key>DeveloperCertificates</key>",
)

PROFILE_PLIST_WRONG_APPID = PROFILE_PLIST.replace(
    "V433H655PN.com.pibulus.talktype", "V433H655PN.com.pibulus.wrongapp"
)

SIGNED_ENTS_PLIST = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
    <key>com.apple.application-identifier</key><string>V433H655PN.com.pibulus.talktype</string>
    <key>com.apple.developer.team-identifier</key><string>V433H655PN</string>
    <key>com.apple.security.app-sandbox</key><true/>
</dict></plist>'''


def case(name, mode="direct", expected=0, artifact=None, preserve=False, error=None, keep_direct=False, **flags):
    with tempfile.TemporaryDirectory(prefix="talktype-build-test-") as temp:
        work = Path(temp)
        fake = work / "bin"
        fake.mkdir()
        for name_, body in STUBS.items():
            script = fake / name_
            script.write_text("#!/bin/bash\n" + body + "\n")
            script.chmod(0o755)
        for path in ["build.sh", "TalkType.swift", "TalkType.entitlements", "TalkType.sandbox.entitlements",
                     "TalkType.mas.entitlements", "PrivacyInfo.xcprivacy"]:
            shutil.copy(ROOT / path, work / path)
        (work / "profile-ok.plist").write_text(PROFILE_PLIST)
        (work / "profile-dev.plist").write_text(PROFILE_PLIST_DEV)
        (work / "profile-wrong-appid.plist").write_text(PROFILE_PLIST_WRONG_APPID)
        (work / "signed-ents.plist").write_text(SIGNED_ENTS_PLIST)
        if flags.get("AUDIT_NO_PROFILE_FILE") != 1:
            (work / "TalkType.provisionprofile").write_bytes(b"FIXTURE-PROFILE")
        (work / "Assets").mkdir()
        shutil.copy(ROOT / "Assets/AppIcon.icns", work / "Assets/AppIcon.icns")
        for folder in ["build", "dist"]:
            (work / folder).mkdir()
            (work / folder / "previous-good-artifact").write_text("preserve me")
        if keep_direct:
            (work / "dist/direct").mkdir(parents=True)
            (work / "dist/direct/TalkType-1.0.dmg").write_text("KEEP")
        env = os.environ.copy()
        # Prevent a developer's ordinary release settings from leaking into the fixtures.
        for key in ["LOCAL_BUILD", "ALLOW_ADHOC_MAS", "SKIP_NOTARIZE", "UNIVERSAL", "VERSION", "BUILD_NUMBER",
                    "PROVISIONING_PROFILE"]:
            env.pop(key, None)
        env.update(PATH=f"{fake}:/usr/bin:/bin:/usr/sbin:/sbin", NOTARY_PROFILE="fixture")
        env.update({k: str(v) for k, v in flags.items()})
        result = subprocess.run(["/bin/bash", "build.sh", mode], cwd=work, env=env, text=True, capture_output=True, timeout=30)
        assert result.returncode == expected, (name, result.returncode, result.stdout, result.stderr)
        if error:
            assert error in result.stderr, (name, result.stderr)
            assert "not found" not in result.stdout, name
        release = work / "dist/direct/TalkType-1.0.dmg"
        local = work / "dist/direct/TalkType-1.0-LOCAL-ONLY.dmg"
        mas_pkg = work / "dist/mas/TalkType-1.0.pkg"
        if expected == 0:
            app_contents = work / f"build/{mode}/TalkType.app/Contents"
            info = plistlib.loads((app_contents / "Info.plist").read_bytes())
            assert info.get("DTXcode") == "2600", (name, info.get("DTXcode"))
            assert info.get("CFBundleIconName") == "AppIcon", (name, info.get("CFBundleIconName"))
            assert info.get("DTCompiler") == "com.apple.compilers.llvm.clang.1_0", name
            assert info.get("DTPlatformBuild") == "26A", name
            assert (app_contents / "Resources/Assets.car").stat().st_size > 0, name
            assert (app_contents / "Resources/AppIcon.icns").stat().st_size > 0, name
            assert (app_contents / "Resources/PrivacyInfo.xcprivacy").stat().st_size > 0, name
        if keep_direct:
            assert (work / "dist/direct/TalkType-1.0.dmg").read_text().strip() == "KEEP", name
        if preserve:
            assert all((work / folder / "previous-good-artifact").is_file() for folder in ["build", "dist"]), name
        elif artifact == "release":
            assert release.read_text().strip() == "VALID", name
            calls = (work / "tool-calls").read_text()
            assert "stapler staple build/direct/TalkType.app" in calls, name
            assert "stapler staple dist/direct/TalkType-1.0.dmg" in calls, name
        elif artifact == "local":
            assert local.read_text().strip() == "VALID" and not release.exists(), name
            assert "notarytool submit" not in (work / "tool-calls").read_text(), name
        elif artifact == "mas_pkg":
            assert mas_pkg.read_text().strip() == "VALID_PKG", name
            calls = (work / "tool-calls").read_text()
            assert "pkgutil --check-signature dist/mas/TalkType-1.0.pkg" in calls, name
        elif not keep_direct:
            assert not release.exists(), name
        print("PASS", name, flush=True)


case("invalid mode preserves previous artifacts", mode="invalid", expected=1, preserve=True)
case("missing Developer ID preserves previous artifacts", expected=1, preserve=True, AUDIT_NO_IDENTITY=1)
case("missing MAS certificates preserves previous artifacts", mode="mas", expected=1, preserve=True)
case("non-universal release build is rejected before wiping artifacts", expected=1, preserve=True, UNIVERSAL=0, error="UNIVERSAL=1 is required")
case("failed create-dmg discards partial image before fallback", artifact="release")
case("Gatekeeper rejection removes release image", expected=1, AUDIT_GATEKEEPER_FAILURE=1)
case("notary command failure removes release image", expected=1, AUDIT_NOTARY_FAILURE=1)
case("missing notarization ticket rejects release", expected=1, AUDIT_NO_PROFILE=1, AUDIT_NO_TICKET=1)
case("Apple agreement failure is reported accurately", expected=1, AUDIT_NO_PROFILE=1,
     AUDIT_PROFILE_ERROR="HTTP 403: required agreement missing", error="HTTP 403: required agreement missing")
case("local image is distinct and never submitted", artifact="local", LOCAL_BUILD=1, AUDIT_NO_IDENTITY=1, AUDIT_NO_TICKET=1)
case("single-arch binary rejected by universal release gate", expected=1, AUDIT_LIPO_ARCHS="arm64", error="missing x86_64 architecture")
case("mas build never touches the direct DMG", mode="mas", ALLOW_ADHOC_MAS=1, keep_direct=True)
case("MAS release builds signed pkg with 4-digit DTXcode and Assets.car", mode="mas", artifact="mas_pkg", AUDIT_MAS_IDENTITY=1)
case("MAS build rejects ApplicationServices linkage", mode="mas", ALLOW_ADHOC_MAS=1, expected=1, AUDIT_LINK_AX=1, error="ApplicationServices")
case("missing Assets.car fails bundle hygiene gate", mode="mas", ALLOW_ADHOC_MAS=1, expected=1, AUDIT_EMPTY_CAR=1, error="Assets.car is missing or empty")
case("quarantine attribute fails ITMS-91109 release gate", mode="mas", ALLOW_ADHOC_MAS=1, expected=1, AUDIT_QUARANTINE=1, error="com.apple.quarantine")
case("MAS release fails fast without a provisioning profile", mode="mas", expected=1, preserve=True,
     AUDIT_MAS_IDENTITY=1, AUDIT_NO_PROFILE_FILE=1, error="Missing Mac App Store provisioning profile")
case("MAS release rejects a development provisioning profile", mode="mas", expected=1, preserve=True,
     AUDIT_MAS_IDENTITY=1, AUDIT_PROFILE_DEV=1, error="Development profile")
case("MAS release rejects a mismatched application-identifier", mode="mas", expected=1, preserve=True,
     AUDIT_MAS_IDENTITY=1, AUDIT_PROFILE_WRONG_APPID=1, error="application-identifier mismatch")
case("MAS release rejects a signature without App Store identifiers", mode="mas", expected=1,
     AUDIT_MAS_IDENTITY=1, AUDIT_NO_SIGNED_ENTS=1, error="missing com.apple.application-identifier")
