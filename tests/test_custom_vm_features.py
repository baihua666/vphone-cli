"""Offline DSC fixtures: feature gates, page hashes, dry-run and exact rollback.

Run: .venv/bin/python tests/test_custom_vm_features.py
"""

import contextlib
import hashlib
import io
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.patchers import custom_features
from scripts.patchers.cfw_patch_hv_vmm_dsc import patch_hv_vmm_in_dsc
from scripts.patchers.cfw_patch_hv_vmm import NEEDLE, MANGLED_NEEDLE

PAGE = 16384
MG = "/usr/lib/libMobileGestalt.dylib"
GPU = "/System/Library/Frameworks/CoreVideo.framework/CoreVideo"
AUTH = "/System/Library/PrivateFrameworks/AuthKit.framework/AuthKit"


def make_chunk(path, index, name):
    """Small real-format DSC mapping, Mach-O install name and SHA256 slots."""
    data = bytearray(PAGE * 2)
    data[:16] = b"dyld_v1  arm64e".ljust(16, b"\0")
    struct.pack_into("<II", data, 16, 0x100, 1)
    struct.pack_into("<QQ", data, 0x28, PAGE * 2, 128)
    struct.pack_into("<QQQII", data, 0x100,
                     0x180000000 + index * 0x10000, PAGE, PAGE, 5, 5)
    label = name.encode() + b"\0"
    cmdsize = (24 + len(label) + 7) & ~7
    struct.pack_into("<IIIIIIII", data, PAGE,
                     0xFEEDFACF, 0x100000C, 0, 6, 1, cmdsize, 0, 0)
    struct.pack_into("<IIIIII", data, PAGE + 32, 0xD, cmdsize, 24, 0, 0, 0)
    data[PAGE + 56:PAGE + 56 + len(label)] = label
    data[PAGE + 512:PAGE + 512 + len(NEEDLE)] = NEEDLE
    cd = bytearray(108)
    struct.pack_into(">IIIIIIIII", cd, 0,
                     0xFADE0C02, 108, 0x20001, 0, 44, 0, 0, 2, PAGE * 2)
    cd[36:40] = bytes([32, 2, 0, 14])
    cd[44:76] = hashlib.sha256(data[:PAGE]).digest()
    cd[76:108] = hashlib.sha256(data[PAGE:PAGE * 2]).digest()
    data += struct.pack(">IIIII", 0xFADE0CC0, 128, 1, 0, 20) + cd
    path.write_bytes(data)


class CustomVMFeaturesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.header = self.root / "features.h"
        self.paths = []
        for i, name in enumerate([MG, GPU, AUTH]):
            p = self.root / f"dyld_shared_cache_arm64e.{i:02d}"
            make_chunk(p, i, name)
            self.paths.append(p)
        self.gate = patch.object(custom_features, "FEATURE_HEADER", self.header)
        self.gate.start()
        self.addCleanup(self.gate.stop)
        self.flags(0, 0)

    def flags(self, master, feature):
        self.header.write_text(
            f"#define TB_VPHONE_CUSTOMIZATIONS {master}\n"
            f"#define TB_VPHONE_HIDE_MOBILEGESTALT_VM {feature}\n")

    def run_patch(self, dry_run=False):
        with contextlib.redirect_stdout(io.StringIO()):
            return patch_hv_vmm_in_dsc(self.root, dry_run=dry_run)

    def snapshot(self):
        return [p.read_bytes() for p in self.paths]

    def assert_hashes(self):
        for data in self.snapshot():
            for i in range(2):
                slot = PAGE * 2 + 20 + 44 + i * 32
                self.assertEqual(data[slot:slot + 32],
                                 hashlib.sha256(data[i * PAGE:(i + 1) * PAGE]).digest())

    def test_gates_round_trip_and_idempotence(self):
        self.run_patch()
        baseline = self.snapshot()
        for gates in [(0, 0), (0, 1), (1, 0)]:
            self.flags(*gates)
            self.run_patch()
            self.assertEqual(self.snapshot(), baseline)
        self.flags(1, 1)
        result = self.run_patch()
        enabled = self.snapshot()
        self.assertEqual(result[MG], 1)
        self.assertIn(NEEDLE, enabled[0])
        self.assertNotIn(MANGLED_NEEDLE, enabled[0])
        self.assertEqual(enabled[1:], baseline[1:])
        self.assert_hashes()
        self.run_patch()
        self.assertEqual(self.snapshot(), enabled)
        self.flags(0, 1)  # Master OFF wins and restores pre-experiment EXP bytes.
        self.run_patch()
        self.assertEqual(self.snapshot(), baseline)
        self.assert_hashes()

    def test_enable_on_pristine_cache(self):
        self.flags(1, 1)
        self.run_patch()
        mg, gpu, auth = self.snapshot()
        self.assertIn(NEEDLE, mg)
        self.assertIn(MANGLED_NEEDLE, gpu)
        self.assertIn(NEEDLE, auth)
        self.assert_hashes()

    def test_dry_run_in_both_directions(self):
        self.run_patch()
        baseline = self.snapshot()
        self.flags(1, 1)
        self.run_patch(dry_run=True)
        self.assertEqual(self.snapshot(), baseline)
        self.run_patch()
        enabled = self.snapshot()
        self.flags(0, 0)
        self.run_patch(dry_run=True)
        self.assertEqual(self.snapshot(), enabled)

    def test_invalid_macros_refuse_before_writing(self):
        original = self.snapshot()
        for text in ["", "#define TB_VPHONE_CUSTOMIZATIONS 2\n",
                     "#define TB_VPHONE_CUSTOMIZATIONS 1\n" * 2,
                     "#define TB_VPHONE_UNKNOWN 1\n"]:
            self.header.write_text(text)
            with self.assertRaises(ValueError):
                self.run_patch()
            self.assertEqual(self.snapshot(), original)

    def test_unsupported_cache_refuses_before_writing(self):
        self.flags(1, 1)
        data = bytearray(self.paths[0].read_bytes())
        struct.pack_into("<QQ", data, 0x28, 0, 0)
        self.paths[0].write_bytes(data)
        original = self.snapshot()
        with self.assertRaisesRegex(ValueError, "CodeDirectory"):
            self.run_patch()
        self.assertEqual(self.snapshot(), original)
        self.paths[0].unlink()
        with self.assertRaisesRegex(ValueError, "No MobileGestalt"):
            self.run_patch()


if __name__ == "__main__":
    unittest.main()
