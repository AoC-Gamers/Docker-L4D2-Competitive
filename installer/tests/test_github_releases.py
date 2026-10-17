"""Offline regression coverage for release failures captured by the installer."""

import json
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile


LIB = Path(__file__).resolve().parents[1] / "lib"


class GitHubReleaseTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="release-test-")
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)

    def shell(self, script):
        env = {key: os.environ[key] for key in ("PATH", "HOME") if key in os.environ}
        env.update(TEST_LIB=str(LIB), DIR_TMP=str(self.root), NO_COLOR="1")
        return subprocess.run(
            ["bash", "-c", 'set -euo pipefail\nsource "$TEST_LIB/tools_stack.sh"\n'
             'source "$TEST_LIB/install_stack_runtime.sh"\n' + script],
            cwd=self.root, env=env, capture_output=True, text=True,
        )

    def test_captured_fatal_error_remains_visible(self):
        result = self.shell('result=$(error_exit "specific failure")\n')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("specific failure", result.stderr)

    def test_release_http_failures_remain_visible(self):
        for status, message, expected in (
            (403, "API rate limit exceeded", "Configure GITHUB_TOKEN"),
            (429, "Too many requests", "Configure GITHUB_TOKEN"),
            (403, "Resource not accessible", "access forbidden"),
            (404, "Not Found", "not accessible"),
        ):
            with self.subTest(status=status, message=message):
                (self.root / "response.json").write_text(json.dumps({"message": message}))
                result = self.shell('''
resolve_github_release_asset() { return 1; }
github_http_status() {
    cp "$DIR_TMP/response.json" "$2"
    printf '%s' ''' + str(status) + '''
}
result=$(download_github_release_source AoC-Gamers/L4D2-Family-Share channel/develop "" 'l4d2-family-share-*.zip' familyshare)
''')
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn(expected, result.stderr)

    def test_download_does_not_repeat_successful_metadata_request(self):
        result = self.shell('''
resolve_github_release_asset() {
    printf 'request\n' >> "$DIR_TMP/metadata-calls"
    printf '%s\n' demo.zip https://github.com/example/demo.zip https://api.github.com/repos/example/demo/releases/assets/1 2026-10-10T00:00:00Z
}
preflight_github_release_access() { error_exit "unexpected duplicate request"; }
download_file() { python3 -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("plugin","payload"); z.close()' "$2"; }
extract_archive() { touch "$2/extracted"; }
save_component_state() { :; }
result=$(download_github_release_source example/demo channel/develop "" '*.zip' demo)
test "$result" = true
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "metadata-calls").read_text(), "request\n")
        self.assertTrue((self.root / "demo/extracted").is_file())

    def test_expected_checksum_and_bad_archive_fail_before_extract(self):
        result = self.shell('''
resolve_github_release_asset() {
    printf '%s\\n' demo.zip https://github.com/example/demo.zip https://api.github.com/repos/example/demo/releases/assets/1 timestamp 1
}
download_file() { printf corrupt > "$2"; }
extract_archive() { touch "$DIR_TMP/unexpected-extraction"; }
STACK_EXPECTED_SHA256=0000000000000000000000000000000000000000000000000000000000000000
result=$(download_github_release_source example/demo channel/develop demo.zip "" demo)
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn("Checksum mismatch", result.stderr)
        self.assertFalse((self.root / "unexpected-extraction").exists())
        result = self.shell('''
printf corrupt > "$DIR_TMP/corrupt.zip"
extract_archive "$DIR_TMP/corrupt.zip" "$DIR_TMP/extracted"
''')
        self.assertNotEqual(result.returncode, 0)

    def test_missing_component_token_stops_before_download(self):
        result = self.shell('''
export GITHUB_TOKEN=fake-global-token
RESOLVED_COMPONENTS_JSON='[{"source_type":"github_release","folder":"familyshare","github_repo":"example/demo","release_tag":"channel/develop","asset_name_glob":"*.zip","github_token_env":"MISSING_TOKEN"}]'
download_github_release_source() { touch "$DIR_TMP/unexpected-download"; }
apply_stack_sources
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn("MISSING_TOKEN", result.stderr)
        self.assertFalse((self.root / "unexpected-download").exists())
        self.assertNotIn("fake-global-token", result.stdout + result.stderr)

    def test_optional_component_token_keeps_global_fallback(self):
        result = self.shell('''
export GITHUB_TOKEN=fake-global-token
token=$(resolve_component_github_token "")
test -z "$token"
test "$(github_auth_token)" = fake-global-token
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_explicit_component_token_keeps_precedence(self):
        result = self.shell('''
export GITHUB_TOKEN=fake-global-token PRIVATE_TOKEN=fake-component-token
token=$(resolve_component_github_token PRIVATE_TOKEN)
test "$(GITHUB_AUTH_TOKEN="$token" github_auth_token)" = fake-component-token
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_sdk_archive_digest_is_clean_on_first_extract_cache_hit_and_change(self):
        archive = self.root / "sdk.zip"
        for content in ("first SDK", "changed SDK"):
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("sdk/version.txt", content)
            expected = hashlib.sha256(archive.read_bytes()).hexdigest()
            result = self.shell('''
source "$TEST_LIB/stack_component_lib.sh"
first=$(stack_extract_cached_archive_by_sha "$DIR_TMP/sdk.zip" "$DIR_TMP/sdk-cache")
cached=$(stack_extract_cached_archive_by_sha "$DIR_TMP/sdk.zip" "$DIR_TMP/sdk-cache")
test "$first" = "$cached"
printf '%s\n' "$first"
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected + "\n")
            self.assertEqual((self.root / "sdk-cache/sdk/version.txt").read_text(), content)
            self.assertEqual((self.root / "sdk-cache/archive.sha256").read_text(), expected + "\n")


    def test_legacy_cache_reuse_does_not_advance_remote_channel(self):
        result = self.shell('''
mkdir demo
STACK_REUSE_SOURCES=true
component_cache_matches_source_prefix() { return 0; }
resolve_github_release_asset() { touch "$DIR_TMP/unexpected-network"; }
result=$(download_github_release_source example/demo channel/develop demo.zip "" demo)
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Legacy release cache', result.stderr)
        self.assertFalse((self.root/'unexpected-network').exists())

    def test_verified_legacy_tree_reuses_without_original_or_network(self):
        result=self.shell('''
export DIR_INSTALLER_LIB="$TEST_LIB"
mkdir demo
printf original > demo/plugin
tree=$(python3 "$TEST_LIB/source_identity.py" demo --payload)
jq -n --arg tree "$tree" '{sha256:"legacy-hash",tree_sha256:$tree}' > demo/.stack-source.json
STACK_REUSE_SOURCES=true
component_cache_matches_source_prefix() { return 0; }
resolve_github_release_asset() { touch "$DIR_TMP/unexpected-network"; }
result=$(download_github_release_source example/demo channel/develop demo.zip "" demo)
test "$result" = false
workspace=$(prepare_component_workspace component "$DIR_TMP/demo")
test "$(cat "$workspace/plugin")" = original
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.root/'unexpected-network').exists())

    def test_expected_original_hash_reuses_bytes_without_second_download(self):
        archive=self.root/'provider.zip'
        with zipfile.ZipFile(archive,'w') as z: z.writestr('plugin','original')
        sha=hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.root/'expected').write_text(sha)
        result=self.shell('''
download_file() { printf call >> "$DIR_TMP/downloads"; cp "$DIR_TMP/provider.zip" "$2"; }
sha=$(cat "$DIR_TMP/expected")
first=$(stack_acquire_original_archive https://example.invalid/exact "$sha" demo.zip)
rm "$DIR_TMP/provider.zip"
second=$(stack_acquire_original_archive https://example.invalid/exact "$sha" demo.zip)
test "$first" = "$second"
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual((self.root/'downloads').read_text(),'call')


if __name__ == "__main__":
    unittest.main()
