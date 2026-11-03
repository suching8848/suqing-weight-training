"""Prepare a new reviewable Git/Workshop bundle without deployment or uploading."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
from zipfile import ZipFile, ZIP_DEFLATED

from package_mod import ROOT, MOD, manifest, validate


def png_info(path: Path) -> dict:
    blob = path.read_bytes()
    assert blob[:8] == b"\x89PNG\r\n\x1a\n", path
    width, height, bits, color = struct.unpack(">IIBB", blob[16:26])
    return {"width": width, "height": height, "bits": bits,
            "color_type": color, "bytes": len(blob)}


def archive(folder: Path, destination: Path) -> dict:
    expected = manifest(folder)
    with ZipFile(destination, "x", ZIP_DEFLATED) as output:
        for relative in expected:
            output.write(folder / relative, relative)
    with ZipFile(destination) as opened:
        assert opened.testzip() is None
        assert set(opened.namelist()) == set(expected)
        for relative, data in expected.items():
            assert hashlib.sha256(opened.read(relative)).hexdigest() == data["sha256"]
    return {"sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
            "file_count": len(expected), "bytes": destination.stat().st_size,
            "readback": "every member SHA-256 verified"}


def copy_public_source(destination: Path) -> dict:
    public_files = ["README.md", "README.en.md", "CHANGELOG.md", ".gitignore", ".gitattributes"]
    for name in public_files:
        shutil.copy2(ROOT / name, destination / name)
    for name in ("SuQingWeightTraining", "tests", "publishing"):
        shutil.copytree(ROOT / name, destination / name,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for name in ("package_mod.py", "prepare_release.py", "export_artwork.ps1", "validate_weight_training.py"):
        target = destination / "tools" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "tools" / name, target)
    for source in (ROOT / "art").rglob("*"):
        if source.is_file() and "references" not in source.relative_to(ROOT / "art").parts:
            target = destination / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for source in (ROOT / "docs/release").glob("*"):
        if source.is_file() and source.name != "handoff.md":
            target = destination / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    findings = []
    patterns = (r"(?i)C:[/\\]Users[/\\]", r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
                r"gh[pousr]_[A-Za-z0-9]{30,}", r"(?i)(?:api[_-]?key|access[_-]?token)\s*[=:]\s*['\"][A-Za-z0-9_-]{24,}")
    for source in destination.rglob("*"):
        if source.is_file() and source.suffix.lower() in {".md", ".txt", ".json", ".lua", ".py", ".ps1", ".java"}:
            text = source.read_text(encoding="utf-8-sig")
            if any(re.search(pattern, text) for pattern in patterns):
                # This tool contains the detector examples; no credentials are present there.
                if source.name != "prepare_release.py":
                    findings.append(source.relative_to(destination).as_posix())
    assert not findings, ("Private path/credential candidates require review", findings)
    return {"result": "PASS", "findings": [], "scope": "common credential signatures and Windows user paths; not proof that no secret can exist"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New directory outside this source tree")
    args = parser.parse_args()
    output = args.output.resolve()
    assert not output.is_relative_to(ROOT), "Output must be outside source tree"
    assert not output.exists(), "Refusing to replace an existing release"
    runtime = validate()
    art = {}
    expected_images = {
        "SuQingWeightTraining/42/media/textures/Item_SQWT_TrainingBelt.png": 128,
        "SuQingWeightTraining/42/media/ui/CategoryIcon/SuQingTrainingBelt.png": 128,
        "SuQingWeightTraining/42/icon.png": 128,
        "SuQingWeightTraining/42/poster.png": 512,
        "publishing/preview.png": 256,
        "publishing/cover-1024.png": 1024,
    }
    for name, size in expected_images.items():
        art[name] = png_info(ROOT / name)
        assert art[name]["width"] == art[name]["height"] == size, (name, art[name])
    assert art["publishing/preview.png"]["bytes"] < 1000 * 1024
    output.mkdir(parents=True)
    workshop = output / "Workshop/SuQingWeightTraining"
    target_mod = workshop / "Contents/mods/SuQingWeightTraining"
    shutil.copytree(MOD, target_mod)
    assert manifest(target_mod) == runtime["files"]
    shutil.copy2(ROOT / "publishing/preview.png", workshop / "preview.png")
    shutil.copy2(ROOT / "publishing/changenote.txt", workshop / "changenote.txt")
    metadata = json.loads((ROOT / "publishing/workshop.json").read_text(encoding="utf-8-sig"))
    assert metadata["publishedfileid"] is None, "A new draft must not reuse an existing item ID"
    description = (ROOT / "publishing/description.bbcode.txt").read_text(encoding="utf-8-sig")
    rows = ["version=1", "title=" + metadata["title"]]
    rows += ["description=" + line for line in description.splitlines()]
    rows += ["tags=" + ";".join(metadata["tags"]), "visibility=private", ""]
    (workshop / "workshop.txt").write_text("\n".join(rows), encoding="utf-8")
    public = output / "GitSource/suqing-weight-training"
    public.mkdir(parents=True)
    scan = copy_public_source(public)
    assert manifest(public / MOD.name) == runtime["files"]
    archives = {
        "SuQingWeightTraining-0.3.2-workshop.zip": archive(workshop, output / "SuQingWeightTraining-0.3.2-workshop.zip"),
        "suqing-weight-training-0.3.2-source.zip": archive(public, output / "suqing-weight-training-0.3.2-source.zip"),
    }
    result = {"version": runtime["version"], "mod_id": runtime["mod_id"],
              "runtime": runtime, "images": art, "public_source_scan": scan,
              "archives": archives, "workshop_draft": "private; no published item ID",
              "source_frozen_workshop_equal": True, "uploaded": False, "deployed": False,
              "gameplay": "0.3.1 user accepted; 0.3.2 artwork not yet visually checked in game"}
    (output / "release-manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    sums = "".join(f"{data['sha256']}  {name}\n" for name, data in archives.items())
    (output / "SHA256SUMS.txt").write_text(sums, encoding="utf-8")
    print(json.dumps({"output": str(output), "version": runtime["version"],
                      "runtime_files": runtime["file_count"], "archives": archives,
                      "public_source_scan": scan, "uploaded": False, "deployed": False}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
