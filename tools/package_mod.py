"""Validate and copy this prototype's runtime files; does not enable the mod."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "SuQingWeightTraining"


def manifest(folder: Path) -> dict:
    return {
        path.relative_to(folder).as_posix(): {
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        for path in sorted(folder.rglob("*")) if path.is_file()
    }


def validate() -> dict:
    required = (
        "42/mod.info", "42/media/sandbox-options.txt",
        "42/media/lua/shared/SuQingWeightTraining/Core.lua",
        "42/media/lua/shared/SuQingWeightTraining/Items.lua",
        "42/media/lua/client/SuQingWeightTraining/Runtime.lua",
        "42/media/lua/client/SuQingWeightTraining_Bootstrap.lua",
        "42/media/lua/client/SuQingWeightTraining/StatusUI.lua",
    )
    for name in required:
        if not (MOD / name).is_file():
            raise ValueError(f"Missing runtime file: {name}")
    info = dict(line.split("=", 1) for line in (MOD / "42/mod.info").read_text(encoding="utf-8").splitlines()
                if "=" in line and not line.lstrip().startswith("#"))
    assert info["id"] == "SuQingWeightTraining", info
    assert info["modversion"] == "0.3.2", info
    for key in ("icon", "poster"):
        assert (MOD / "42" / info[key]).is_file(), ("Missing artwork", key)
    for name in ("42/media/textures/Item_SQWT_TrainingBelt.png",
                 "42/media/ui/CategoryIcon/SuQingTrainingBelt.png"):
        assert (MOD / name).is_file(), ("Missing artwork", name)
    for forbidden in ("javaPkgName", "javaJarFile", "ZBVersionMin", "require"):
        assert forbidden not in info, ("Unexpected external/Java dependency", forbidden)
    for path in MOD.rglob("*.json"):
        json.loads(path.read_text(encoding="utf-8"))
    for path in MOD.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".java", ".py", ".class", ".jar", ".dll"}:
            raise ValueError(f"Build-only file in runtime folder: {path}")
    (MOD / "common").mkdir(exist_ok=True)
    files = manifest(MOD)
    return {"mod_id": info["id"], "version": info["modversion"], "files": files,
            "file_count": len(files), "total_bytes": sum(item["bytes"] for item in files.values()),
            "gameplay_validation": "not performed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New parent directory for the packaged mod")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = validate()
    if args.output:
        destination = args.output.resolve() / MOD.name
        if destination.exists():
            raise FileExistsError(f"Will not replace an existing package: {destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(MOD, destination)
        assert manifest(destination) == result["files"], "Packaged files differ from source"
        assert (destination / "common").is_dir()
        result["package_path"] = str(destination)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "files"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
