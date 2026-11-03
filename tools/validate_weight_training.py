"""Validate isolated Lua fixtures with Lua 5.1 and the game's Kahlua VM.

Reads runtime sources and optional protein-boost sources; never launches the
game, opens a save, deploys files, or edits enabled-mod lists.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "SuQingWeightTraining"
LUA = MOD / "42/media/lua"
TESTS = ROOT / "tests"
COUNT_KINDS = {
    "core_tests.lua": "named_cases",
    "native_xp_compat_tests.lua": "named_cases",
    "runtime_tests.lua": "named_cases",
    "status_ui_tests.lua": "named_cases",
    "items_tests.lua": "counted_equal_assertions",
}


def long_string(value: str) -> str:
    equals = "=="
    while "]" + equals + "]" in value:
        equals += "="
    return "[" + equals + "[" + value + "]" + equals + "]"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path)
    parser.add_argument("--kahlua-runner-dir", type=Path)
    parser.add_argument("--protein-mod-root", type=Path,
                        help="Existing protein mod folder containing its 42 directory; read only")
    parser.add_argument("--without-protein", action="store_true",
                        help="Run without the optional external protein integration fixtures")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.kahlua_runner_dir and not args.game_root:
        parser.error("--kahlua-runner-dir requires --game-root")
    if args.protein_mod_root and args.without_protein:
        parser.error("--protein-mod-root and --without-protein are mutually exclusive")
    os.chdir(ROOT)

    if not LUA.is_dir():
        parser.error(f"runtime source directory is missing: {LUA}")
    suites = sorted(TESTS.glob("*_tests.lua"))
    if not suites:
        parser.error(f"no controlled *_tests.lua suites found in {TESTS}")

    protein_root = None
    if not args.without_protein:
        protein_root = args.protein_mod_root or (
            ROOT.parent / "suqing-project-zomboid-patches/src/SuQingProteinTrainingBoost"
        )
        if not protein_root.is_dir():
            if args.protein_mod_root:
                parser.error(f"protein source folder does not exist: {protein_root}")
            protein_root = None

    sources: dict[str, str] = {}
    modules: dict[str, str] = {}
    require_paths: list[str] = []

    def add_modules(base: Path, prefix: str = "") -> None:
        for kind in ("shared", "client"):
            directory = base / kind
            require_paths.append((directory / "?.lua").as_posix())
            for path in sorted(directory.rglob("*.lua")):
                name = path.relative_to(directory).with_suffix("").as_posix()
                key = (path.relative_to(ROOT).as_posix() if base == LUA
                       else prefix + path.relative_to(base).as_posix())
                if name in modules:
                    raise RuntimeError(f"duplicate module in fixture source map: {name}")
                sources[key] = path.read_text(encoding="utf-8-sig")
                modules[name] = key

    add_modules(LUA, "runtime/")
    # Early registry files run through dofile before native script parsing.
    # Include them as controlled sources, never as require-able Lua modules.
    registry = MOD / "42/media/registries.lua"
    if registry.is_file():
        sources[registry.relative_to(ROOT).as_posix()] = registry.read_text(encoding="utf-8-sig")
    if protein_root:
        add_modules(protein_root / "42/media/lua", "external-protein/")
        for name in ("SuQingProteinTrainingBoost/Core", "SuQingProteinTrainingBoost/XP"):
            if name not in modules:
                parser.error(f"protein source folder is missing required module: {name}")
    for suite in suites:
        sources[suite.relative_to(ROOT).as_posix()] = suite.read_text(encoding="utf-8-sig")

    from lupa.lua51 import LuaRuntime

    results = []
    expected_counts = {}
    for suite in suites:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().WEIGHT_PROTEIN_TEST_AVAILABLE = protein_root is not None
        lua.execute("local paths = ...; package.path = paths .. ';' .. package.path",
                    ";".join(require_paths))
        for path, code in sources.items():
            lua.execute("local code, path = ...; assert(loadstring(code, path))", code, path)
        outcome = lua.execute(sources[suite.relative_to(ROOT).as_posix()])
        if lua.eval("function(value) return type(value) == 'table' and type(value.run) == 'function' end")(outcome):
            outcome = outcome["run"]()
        checks = outcome if isinstance(outcome, (int, float)) and not isinstance(outcome, bool) else None
        expected_counts[suite.name] = checks
        results.append({"engine": "Lua 5.1", "suite": suite.name,
                        "checks": checks,
                        "count_kind": COUNT_KINDS.get(suite.name, "suite_reported_checks"),
                        "result": "PASS"})

    if args.kahlua_runner_dir:
        java = args.game_root / "jre64/bin/java.exe"
        classpath = os.pathsep.join((str(args.kahlua_runner_dir), str(args.game_root / "projectzomboid.jar")))
        scratch = ROOT / ".validation"
        scratch.mkdir(exist_ok=True)
        for suite in suites:
            bundle = ["package = { loaded = {} }", "local sources = {}", "local modules = {}"]
            for path, code in sources.items():
                bundle.append(f"sources[ {long_string(path)} ] = {long_string(code)}")
            for name, path in modules.items():
                bundle.append(f"modules[ {long_string(name)} ] = {long_string(path)}")
            bundle.append("""
function dofile(path)
    return assert(loadstring(assert(sources[path], 'missing controlled source: ' .. tostring(path)), path))()
end
function require(name)
    if package.loaded[name] then return package.loaded[name] end
    local value = dofile(assert(modules[name], 'unknown controlled module: ' .. tostring(name)))
    package.loaded[name] = value or true
    return package.loaded[name]
end
for path, code in pairs(sources) do assert(loadstring(code, path)) end
""")
            bundle.append("WEIGHT_PROTEIN_TEST_AVAILABLE = " + ("true" if protein_root else "false"))
            bundle.append("local outcome = dofile(" + long_string(suite.relative_to(ROOT).as_posix()) + ")")
            bundle.append("if type(outcome) == 'table' and type(outcome.run) == 'function' then outcome = outcome.run() end")
            bundle.append("return outcome")
            with tempfile.TemporaryDirectory(prefix="weight-training-", dir=scratch) as temporary:
                path = Path(temporary) / "suite.lua"
                path.write_text("\n".join(bundle), encoding="utf-8")
                result = subprocess.run([str(java), "-cp", classpath, "KahluaValidation", str(path)],
                                        cwd=args.game_root, capture_output=True, text=True,
                                        encoding="utf-8", errors="replace")
                print(result.stdout.strip())
                if result.returncode:
                    raise RuntimeError(f"Kahlua {suite.name} failed:\n{result.stderr}")
                count_match = re.search(r"\[true,\s*([0-9]+(?:\.[0-9]+)?)\]", result.stdout)
                checks = float(count_match.group(1)) if count_match else None
                if checks != expected_counts[suite.name]:
                    raise RuntimeError(f"Kahlua/Lua 5.1 returned different check counts for {suite.name}: "
                                       f"{checks} != {expected_counts[suite.name]}")
            results.append({"engine": "game Kahlua", "suite": suite.name,
                            "checks": checks,
                            "count_kind": COUNT_KINDS.get(suite.name, "suite_reported_checks"),
                            "result": "PASS"})

    counts_by_engine = {}
    for result in results:
        if result["checks"] is not None:
            counts = counts_by_engine.setdefault(result["engine"], {})
            kind = result["count_kind"]
            counts[kind] = counts.get(kind, 0) + result["checks"]

    report = {
        "result": "PASS", "suites": results, "syntax_files": len(sources),
        "counts_by_engine": counts_by_engine,
        "count_note": "Named cases and counted equal() assertions are separate metrics; internal guard assertions are additional.",
        "optional_protein_source": str(protein_root.resolve()) if protein_root else None,
        "gameplay_validation": "not performed; isolated movement/XP models and source integration fixtures",
        "runtime_sha256": {
            path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in MOD.rglob("*") if path.is_file()
        },
        "fixture_sha256": {
            suite.relative_to(ROOT).as_posix(): hashlib.sha256(suite.read_bytes()).hexdigest()
            for suite in suites
        },
        "external_protein_sha256": {
            path.relative_to(protein_root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted((protein_root / "42/media/lua").rglob("*.lua"))
        } if protein_root else {},
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": "PASS", "suites": len(results), "syntax_files": len(sources),
                      "protein_integration": protein_root is not None,
                      "counts_by_engine": counts_by_engine}, indent=2))


if __name__ == "__main__":
    main()
