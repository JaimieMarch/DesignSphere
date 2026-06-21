from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "build_catalog.py"
SPEC = importlib.util.spec_from_file_location("build_catalog", MODULE_PATH)
assert SPEC and SPEC.loader
build_catalog = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = build_catalog
SPEC.loader.exec_module(build_catalog)


class CatalogClassificationTests(unittest.TestCase):
    def test_each_category_rule_has_a_representative_match(self):
        cases = {
            "dining_chair": "seating",
            "king_bed": "beds",
            "coffee_table": "tables",
            "book_shelf": "storage",
            "floor_lamp": "lighting",
            "tv_monitor": "media",
            "ceramic_vase": "decor",
            "unclassified_prop": "decor",
        }
        for name, expected in cases.items():
            with self.subTest(name=name):
                self.assertEqual(build_catalog.categorize(name), expected)

    def test_category_precedence_is_deterministic(self):
        self.assertEqual(build_catalog.categorize("chair_side_table"), "seating")
        self.assertEqual(build_catalog.categorize("bedside_table_lamp"), "beds")

    def test_placement_hint_precedence(self):
        ceiling = build_catalog.placement_for("ceiling_tv", "media")
        self.assertEqual((ceiling.classification, ceiling.plane), ("ceiling", "horizontal"))

        wall = build_catalog.placement_for("wall_clock", "decor")
        self.assertEqual((wall.classification, wall.plane), ("wall", "vertical"))

        tabletop = build_catalog.placement_for("ceramic_vase", "decor")
        self.assertEqual((tabletop.classification, tabletop.plane), ("table", "horizontal"))

    def test_category_defaults_control_stacking(self):
        for category in ("seating", "tables", "storage"):
            with self.subTest(category=category):
                placement = build_catalog.placement_for("ordinary", category)
                self.assertEqual(placement.classification, "floor")
                self.assertTrue(placement.canStack)
                self.assertFalse(placement.needsPhysics)
                self.assertTrue(placement.preserveRealWorldScale)

        self.assertFalse(build_catalog.placement_for("ordinary", "decor").canStack)
        self.assertFalse(build_catalog.placement_for("ordinary", "unknown").canStack)

    def test_id_and_display_name_normalization(self):
        self.assertEqual(build_catalog.model_id_from_folder("Modern_Chair_01_4k"), "modern_chair_01")
        self.assertEqual(build_catalog.model_id_from_folder("lamp_12"), "lamp_12")
        self.assertEqual(build_catalog.display_name("modern-arm_chair_01"), "Modern Arm Chair 01")


class CatalogDiscoveryTests(unittest.TestCase):
    def test_find_source_prefers_named_mesh_and_extension_order(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "chair"
            folder.mkdir()
            (folder / "a.glb").write_bytes(b"fallback")
            (folder / "chair.obj").write_bytes(b"named")
            self.assertEqual(build_catalog.find_source_mesh(folder), folder / "chair.obj")

            (folder / "chair.glb").write_bytes(b"preferred")
            self.assertEqual(build_catalog.find_source_mesh(folder), folder / "chair.glb")

    def test_find_source_returns_none_for_empty_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertIsNone(build_catalog.find_source_mesh(Path(temp)))

    def test_discovery_ignores_hidden_generated_and_repo_directories(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)
            self._mesh_folder(source, "valid_chair", ".glb")
            self._mesh_folder(source, ".hidden", ".glb")
            self._mesh_folder(source, "_catalog_build", ".glb")
            self._mesh_folder(source, "DesignSphere", ".glb")
            (source / "not-a-directory.glb").write_bytes(b"mesh")
            self.assertEqual(
                [(model_id, mesh.name) for model_id, mesh in build_catalog.discover_models(source)],
                [("valid_chair", "valid_chair.glb")],
            )

    def test_collision_prefers_blend_source(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)
            self._mesh_folder(source, "chair_01", ".glb")
            blend = self._mesh_folder(source, "chair_01_4k", ".blend")
            discovered = build_catalog.discover_models(source)
            self.assertEqual(discovered, [("chair_01", blend)])

    def test_textured_only_filters_non_blend_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)
            self._mesh_folder(source, "chair", ".glb")
            blend = self._mesh_folder(source, "sofa", ".blend")
            self.assertEqual(build_catalog.discover_models(source, textured_only=True), [("sofa", blend)])

    def test_sha256_reads_complete_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "payload"
            payload = b"abc" * 1_000_000
            path.write_bytes(payload)
            self.assertEqual(build_catalog.sha256_of(path), hashlib.sha256(payload).hexdigest())

    @staticmethod
    def _mesh_folder(source: Path, name: str, extension: str) -> Path:
        folder = source / name
        folder.mkdir()
        mesh = folder / f"{name}{extension}"
        mesh.write_bytes(b"mesh")
        return mesh


class CatalogConversionTests(unittest.TestCase):
    def test_external_converter_is_invoked_with_input_and_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            mesh = root / "model.glb"
            output = root / "out" / "model.usdz"
            mesh.write_bytes(b"mesh")
            args = argparse.Namespace(converter="custom-converter", blender="blender", downscale="1024")
            with mock.patch.object(build_catalog.subprocess, "run") as run:
                build_catalog.convert_to_usdz(args, mesh, output)
            run.assert_called_once_with(
                ["custom-converter", str(mesh), str(output)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.STDOUT,
            )
            self.assertTrue(output.parent.is_dir())

    def test_native_converter_builds_and_removes_intermediate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            mesh = root / "model.glb"
            output = root / "model.usdz"
            mesh.write_bytes(b"mesh")
            args = argparse.Namespace(converter="native", blender="blender", downscale="1024")

            def fake_run(command, **_kwargs):
                if command[0] == "usdcat":
                    Path(command[-1]).write_bytes(b"usdc")
                elif command[0] == "usdzip":
                    Path(command[1]).write_bytes(b"usdz")
                return subprocess.CompletedProcess(command, 0)

            with mock.patch.object(build_catalog.subprocess, "run", side_effect=fake_run) as run:
                build_catalog.convert_to_usdz(args, mesh, output)
            self.assertEqual([call.args[0][0] for call in run.call_args_list], ["usdcat", "usdzip"])
            self.assertTrue(output.exists())
            self.assertFalse(output.with_suffix(".usdc").exists())

    def test_native_converter_rejects_missing_intermediate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            mesh = root / "model.glb"
            mesh.write_bytes(b"mesh")
            args = argparse.Namespace(converter="native", blender="blender", downscale="1024")
            with mock.patch.object(build_catalog.subprocess, "run"):
                with self.assertRaises(subprocess.CalledProcessError):
                    build_catalog.convert_to_usdz(args, mesh, root / "model.usdz")

    def test_blender_converter_passes_downscale_and_validates_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            mesh = root / "model.blend"
            output = root / "model.usdz"
            mesh.write_bytes(b"mesh")
            args = argparse.Namespace(converter="native", blender="blender-bin", downscale="2048")

            def fake_run(command, **_kwargs):
                Path(command[-1]).write_bytes(b"usdz")
                return subprocess.CompletedProcess(command, 0)

            with mock.patch.object(build_catalog.subprocess, "run", side_effect=fake_run) as run:
                build_catalog.convert_to_usdz(args, mesh, output)
            command = run.call_args.args[0]
            self.assertEqual(command[:3], ["blender-bin", "--background", str(mesh)])
            self.assertEqual(run.call_args.kwargs["env"]["USDZ_DOWNSCALE"], "2048")
            self.assertTrue(output.exists())

    def test_thumbnail_handles_success_timeout_and_missing_tool(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            usdz = root / "model.usdz"
            png = root / "thumbs" / "model.png"

            def success(_command, **_kwargs):
                png.write_bytes(b"png")

            with mock.patch.object(build_catalog.subprocess, "run", side_effect=success):
                self.assertTrue(build_catalog.render_thumbnail(usdz, png, size=128, timeout=1))

            png.unlink()
            with mock.patch.object(build_catalog.subprocess, "run", side_effect=subprocess.TimeoutExpired("usdrecord", 1)):
                self.assertFalse(build_catalog.render_thumbnail(usdz, png, timeout=1))
            with mock.patch.object(build_catalog.subprocess, "run", side_effect=FileNotFoundError):
                self.assertFalse(build_catalog.render_thumbnail(usdz, png))


class CatalogBuildTests(unittest.TestCase):
    def test_invalid_source_and_empty_source_return_errors(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with redirect_stderr(io.StringIO()):
                self.assertEqual(build_catalog.build(self._args(root / "missing", root / "out")), 2)
            with redirect_stderr(io.StringIO()):
                self.assertEqual(build_catalog.build(self._args(root, root / "out")), 1)

    def test_dry_run_does_not_create_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            CatalogDiscoveryTests._mesh_folder(source, "chair", ".glb")
            output = root / "out"
            with redirect_stdout(io.StringIO()) as stdout:
                result = build_catalog.build(self._args(source, output, dry_run=True))
            self.assertEqual(result, 0)
            self.assertFalse(output.exists())
            self.assertIn("chair", stdout.getvalue())
            self.assertIn("seating", stdout.getvalue())

    def test_full_build_writes_deterministic_manifest_metadata(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            CatalogDiscoveryTests._mesh_folder(source, "modern_chair_4k", ".blend")
            output = root / "out"
            model_output = output / "models" / "modern_chair.usdz"
            model_output.parent.mkdir(parents=True)
            model_output.write_bytes(b"converted-model")

            with mock.patch.object(build_catalog, "render_thumbnail", return_value=False), redirect_stdout(io.StringIO()):
                result = build_catalog.build(self._args(source, output, skip_thumbnails=False))

            self.assertEqual(result, 0)
            manifest = json.loads((output / "catalog.json").read_text())
            self.assertEqual(manifest["version"], build_catalog.MANIFEST_VERSION)
            self.assertEqual(len(manifest["models"]), 1)
            entry = manifest["models"][0]
            self.assertEqual(entry["id"], "modern_chair")
            self.assertEqual(entry["displayName"], "Modern Chair")
            self.assertEqual(entry["category"], "seating")
            self.assertTrue(entry["textured"])
            self.assertEqual(entry["file"]["bytes"], len(b"converted-model"))
            self.assertEqual(entry["file"]["sha256"], hashlib.sha256(b"converted-model").hexdigest())
            self.assertNotIn("thumbnail", entry)

    def test_existing_thumbnail_is_referenced_when_rendering_is_skipped(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            CatalogDiscoveryTests._mesh_folder(source, "table", ".glb")
            output = root / "out"
            (output / "models").mkdir(parents=True)
            (output / "models" / "table.usdz").write_bytes(b"model")
            (output / "thumbnails").mkdir()
            (output / "thumbnails" / "table.png").write_bytes(b"png")
            with redirect_stdout(io.StringIO()):
                build_catalog.build(self._args(source, output, skip_thumbnails=True))
            entry = json.loads((output / "catalog.json").read_text())["models"][0]
            self.assertEqual(entry["thumbnail"]["url"], "thumbnails/table.png")

    def test_limit_is_applied_before_conversion(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            CatalogDiscoveryTests._mesh_folder(source, "chair", ".glb")
            CatalogDiscoveryTests._mesh_folder(source, "table", ".glb")
            with mock.patch.object(build_catalog, "convert_to_usdz") as convert, redirect_stdout(io.StringIO()):
                convert.side_effect = lambda _args, _mesh, output: output.write_bytes(b"model")
                build_catalog.build(self._args(source, root / "out", limit=1, skip_thumbnails=True))
            self.assertEqual(convert.call_count, 1)

    @staticmethod
    def _args(source: Path, output: Path, **overrides) -> argparse.Namespace:
        values = {
            "source": str(source),
            "out": str(output),
            "converter": "native",
            "dry_run": False,
            "force": False,
            "skip_thumbnails": True,
            "blender": "blender",
            "downscale": "1024",
            "textured_only": False,
            "limit": 0,
        }
        values.update(overrides)
        return argparse.Namespace(**values)


if __name__ == "__main__":
    unittest.main()
