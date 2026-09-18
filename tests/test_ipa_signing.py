#!/usr/bin/env python3
"""Run the installer's signing functions with real ldid and iOS Mach-O fixtures.

macOS + Xcode + ldid required. Compile only the signing helpers on the host,
leaving iOS-only LaunchServices/container registration out of this test.
"""

from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


class IPASigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ldid = shutil.which("ldid")
        if not cls.ldid or not shutil.which("xcrun"):
            raise unittest.SkipTest("requires Xcode and ldid on macOS")
        cls.temp = tempfile.TemporaryDirectory(prefix="vphone-signing-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        source = (ROOT / "scripts/vphoned/vphoned_install.m").read_text()
        functions = []
        for name in (
            "vp_info_dictionary_for_app_path", "vp_app_main_executable_path_for_app_path",
            "vp_read_all_from_fd", "vp_run_process_with_output", "vp_get_static_code_ref",
            "vp_dump_entitlements_from_binary_at_path", "vp_sign_binary", "vp_sign_app",
        ):
            match = re.search(r"^static [^\n]*\b" + name + r"\(", source, re.M)
            if match is None:
                raise RuntimeError(f"signing helper not found: {name}")
            functions.append(source[match.start():source.index("\n}", match.start()) + 2])
        harness = cls.root / "sign.m"
        harness.write_text(
            "#import <Foundation/Foundation.h>\n#import <Security/Security.h>\n"
            "#include <spawn.h>\n#include <sys/wait.h>\n#include <unistd.h>\n"
            + "\n".join(functions) + r'''
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *output = nil;
        NSString *cert = argc > 3 ? @(argv[3]) : nil;
        int result = vp_sign_app(@(argv[1]), cert, @(argv[2]), &output);
        if (output) fprintf(stderr, "%s\n", output.UTF8String);
        return result;
    }
}
''')
        cls.signer = cls.root / "sign"
        run("xcrun", "--sdk", "macosx", "clang", "-fobjc-arc",
            "-Wno-deprecated-declarations", "-Wno-incompatible-pointer-types",
            str(harness), "-framework", "Foundation", "-framework", "Security",
            "-o", str(cls.signer))
        fixture = cls.root / "main.c"
        fixture.write_text("int main(void) { return 0; }\n")
        cls.binary = cls.root / "fixture"
        run("xcrun", "--sdk", "iphoneos", "clang", "-arch", "arm64",
            "-Wl,-no_adhoc_codesign", str(fixture), "-o", str(cls.binary))
        cls.library = cls.root / "library"
        run("xcrun", "--sdk", "iphoneos", "clang", "-arch", "arm64", "-dynamiclib",
            "-Wl,-no_adhoc_codesign", str(fixture), "-o", str(cls.library))

    def make_bundle(self, parent, name, package_type="APPL"):
        app = parent / name
        app.mkdir(parents=True)
        info = {"CFBundleIdentifier": "test." + name.split(".")[0],
                "CFBundleExecutable": "Main", "CFBundlePackageType": package_type}
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        shutil.copy(self.binary if package_type != "FMWK" else self.library, app / "Main")
        return app

    def entitlements(self, binary):
        data = run(self.ldid, "-e", str(binary))
        return plistlib.loads(data) if data else {}

    def check_signing(self, certificate):
        with tempfile.TemporaryDirectory(dir=self.root) as folder:
            app = self.make_bundle(Path(folder), "Host.app")
            plugin = self.make_bundle(app / "PlugIns", "Extension.appex", "XPC!")
            framework = self.make_bundle(app / "Frameworks", "Library.framework", "FMWK")
            # Real pre-existing extension permissions must survive the final bundle seal.
            ent = Path(folder) / "extension.plist"
            ent.write_bytes(plistlib.dumps({"keychain-access-groups": ["TEST.extension"]}))
            run(self.ldid, "-S" + str(ent), str(plugin / "Main"))
            args = [str(self.signer), str(app), self.ldid]
            if certificate:
                args.append(str(ROOT / "scripts/vphoned/signcert.p12"))
            run(*args)
            for bundle in (app, plugin):
                with self.subTest(bundle=bundle.name):
                    signed = self.entitlements(bundle / "Main")
                    self.assertEqual(signed.get("com.apple.private.security.container-required"),
                                     "test." + bundle.name.split(".")[0])
            self.assertEqual(self.entitlements(plugin / "Main").get("keychain-access-groups"),
                             ["TEST.extension"])
            # Dropping the recursive signing pass would leave the framework unsigned.
            self.assertIn(b"CDHash=", run(self.ldid, "-h", str(framework / "Main")))
            self.assertTrue((framework / "_CodeSignature/CodeResources").is_file())
            # Host codesign rejects ldid's certificate-free iOS signatures (no CMS).
            if certificate:
                run("codesign", "--verify", "--deep", str(app))

    # Known upstream limitation; the supported full bundle supplies a certificate.
    @unittest.expectedFailure
    def test_adhoc_preserves_entitlements_and_signs_nested_code(self):
        self.check_signing(certificate=False)

    def test_certificate_preserves_entitlements_and_signs_nested_code(self):
        self.check_signing(certificate=True)


if __name__ == "__main__":
    unittest.main()
