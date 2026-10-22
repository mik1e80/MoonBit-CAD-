"""Exercise moon new -> registry add -> two tests -> runnable consumer.

Python 3.10+ standard library only. Never runs this repository's test suite.
The generated consumer and raw command logs are retained outside the repository.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[1]
MODULE = "mik1e80/cad_sketch"
VERSION = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "moon.mod").read_text(encoding="utf-8"), re.M).group(1)
LIBRARY = r'''///|
pub fn edited_length() -> Double {
  let sketch = @sketch.Sketch::new()
  let a = sketch.add_point(0.0, 0.0)
  let b = sketch.add_point(3.0, 0.5)
  sketch.constrain(Fix(a, 0.0, 0.0)) |> ignore
  sketch.constrain(Horizontal(sketch.add_line(a, b))) |> ignore
  let dimension = sketch.constrain(Distance(a, b, 5.0))
  let first = sketch.solve_and_apply().unwrap()
  if !first.report.is_satisfied() ||
    (sketch.point(b).unwrap().x - 5.0).abs() > 1.0e-6 {
    abort("Initial dimension did not solve")
  }
  if !sketch.set_constraint(dimension, Distance(a, b, 7.0)) {
    abort("Dimension edit failed")
  }
  let edited = sketch.solve_and_apply().unwrap()
  if !edited.report.is_satisfied() {
    abort("Edited sketch did not solve")
  }
  sketch.point(b).unwrap().x
}

///|
pub fn rejects_invalid_radius() -> Bool {
  let sketch = @sketch.Sketch::new()
  let center = sketch.add_point(0.0, 0.0)
  let circle = sketch.add_circle(center, -1.0)
  match sketch.solve_and_apply() {
    Err(InvalidRadius(id)) => id.index == circle.index
    _ => false
  }
}

///|
pub fn exported_svg() -> String {
  let sketch = @sketch.Sketch::new()
  let a = sketch.add_point(0.0, 0.0)
  let b = sketch.add_point(7.0, 0.0)
  sketch.add_line(a, b) |> ignore
  sketch.add_circle(a, 2.0) |> ignore
  sketch.to_svg(options={
    ..@sketch.SvgOptions::default(),
    title: "Consumer <SVG>",
    show_points: false,
  }).unwrap()
}
'''
TESTS = '''///|
test "installed library solves an edited dimension" {
  assert_true((@consumer.edited_length() - 7.0).abs() < 1.0e-6)
}

///|
test "installed library exposes typed errors" {
  assert_true(@consumer.rejects_invalid_radius())
}

///|
test "installed library exposes SVG export" {
  assert_true(@consumer.exported_svg().contains("<title>Consumer &lt;SVG&gt;</title>"))
}
'''
MAIN = r'''///|
fn main {
  let length = @consumer.edited_length()
  if (length - 7.0).abs() > 1.0e-6 {
    abort("Wrong edited dimension")
  }
  println("Length after edit: \{length}")
  println("SVG after edit: \{@consumer.exported_svg()}")
}
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "_build/consumer-test/latest.json")
    parser.add_argument("--archive", type=Path, help="Compare every uploaded source file with the registry installation")
    args = parser.parse_args()
    executable = "moon.exe" if os.name == "nt" else "moon"
    moon = str(Path(os.environ["MOON_HOME"]) / "bin" / executable) if os.getenv("MOON_HOME") else shutil.which(executable)
    if not moon:
        raise RuntimeError("MoonBit must be on PATH or MOON_HOME must be set")
    workspace = Path(tempfile.mkdtemp(prefix="cad-registry-consumer-")).resolve()
    assert not workspace.is_relative_to(ROOT), "Consumer must be outside repository"
    assert not any((p / "moon.work").exists() for p in (workspace, *workspace.parents))
    commands = []

    def run(*arguments: str, cwd: Path) -> str:
        step = len(commands) + 1
        result = subprocess.run([moon, *arguments], cwd=cwd, text=True, capture_output=True, timeout=180)
        (workspace / f"{step:02d}.stdout.log").write_text(result.stdout, encoding="utf-8")
        (workspace / f"{step:02d}.stderr.log").write_text(result.stderr, encoding="utf-8")
        commands.append({"command": ["moon", *arguments], "exit_code": result.returncode})
        print("moon " + " ".join(arguments), flush=True)
        print(result.stdout, end="", flush=True)
        if result.returncode:
            raise RuntimeError(f"Command failed; raw logs retained at {workspace}\n{result.stderr}")
        return result.stdout + "\n" + result.stderr

    toolchain = run("version", "--all", cwd=workspace)
    run("new", "consumer", "--user", "consumer_test", cwd=workspace)
    project = workspace / "consumer"
    assert not (project / ".mooncakes").exists(), "Expected fresh consumer"
    install_output = run("add", MODULE, cwd=project)
    if "failed to update registry index" in install_output:
        raise RuntimeError(f"Registry index refresh failed; retry with network access. Logs: {workspace}")
    manifest = (project / "moon.mod").read_text(encoding="utf-8")
    assert f'"{MODULE}@{VERSION}"' in manifest, "Unexpected registry version; review before updating proof"
    assert not (project / "moon.work").exists()
    dependency = project / ".mooncakes" / MODULE
    assert dependency.is_dir() and not dependency.is_symlink(), "Expected registry download"
    dependency_manifest = (dependency / "moon.mod").read_text(encoding="utf-8")
    assert re.search(rf'^version\s*=\s*"{re.escape(VERSION)}"', dependency_manifest, re.M)
    archive_match = {}
    if args.archive:
        matched = 0
        with zipfile.ZipFile(args.archive) as archive:
            for item in archive.infolist():
                if item.is_dir():
                    continue
                relative = item.filename.replace("\\", "/")
                destination = (dependency / relative).resolve()
                destination.relative_to(dependency.resolve())
                assert archive.read(item) == destination.read_bytes(), f"Registry differs: {relative}"
                matched += 1
        archive_match = {"uploaded_archive_sha256": hashlib.sha256(args.archive.read_bytes()).hexdigest(),
                         "registry_download_matches_archive": True, "matched_archive_files": matched}

    files = {
        "moon.pkg": 'import { "mik1e80/cad_sketch" @sketch, }\n\nimport { "consumer_test/consumer" @consumer, } for "test"\n',
        "consumer.mbt": LIBRARY,
        "consumer_test.mbt": TESTS,
        "cmd/main/moon.pkg": 'import { "consumer_test/consumer" @consumer, }\n\npkgtype(kind: "executable")\n',
        "cmd/main/main.mbt": MAIN,
    }
    for name, source in files.items():
        (project / name).write_text(source, encoding="utf-8")
    run("info", cwd=project)
    run("fmt", cwd=project)
    test_output = run("test", "--target", "js", "--deny-warn", cwd=project)
    assert re.search(r"Total tests:\s*3, passed:\s*3, failed:\s*0", test_output), "Expected exactly three consumer tests"
    output = run("run", "cmd/main", "--target", "js", "--deny-warn", cwd=project)
    match = re.search(r"^Length after edit: ([0-9.eE+-]+)\s*$", output, re.M)
    assert match, "Consumer executable did not report an actual result"
    length = float(match[1])
    assert math.isfinite(length) and abs(length - 7.0) < 1e-6
    svg_match = re.search(r"^SVG after edit: (<svg\b.*?</svg>)", output, re.M | re.S)
    assert svg_match, "Consumer executable did not export SVG"
    svg = ET.fromstring(svg_match[1])
    ns = "{http://www.w3.org/2000/svg}"
    assert svg.tag == ns + "svg"
    assert svg.find(ns + "title").text == "Consumer <SVG>"
    assert len(svg.findall(".//" + ns + "line")) == 1
    assert len(svg.findall(".//" + ns + "circle")) == 1
    source_hashes = {name: hashlib.sha256((project / name).read_bytes()).hexdigest() for name in files}
    report = {
        "schema": 1, "module": MODULE, "version": VERSION, "target": "js",
        "consumer_created_by_moon_new": True, "consumer_outside_repository": True,
        "workspace_or_path_override": False, "fresh_project_dependency_directory": True,
        "dependency_source": "Mooncakes registry", "registry_index_refresh_failed": False,
        "registry_cache_used": "Using cached" in install_output, "commands": commands,
        "tests": {"total": 3, "passed": 3, "failed": 0},
        "run": {"exit_code": 0, "edited_length": length, "expected_length": 7.0, "tolerance": 1e-6},
        "svg_xml_verified": True,
        **archive_match,
        "consumer_source_sha256": source_hashes,
        "toolchain": {name: match.group(1) for name in ("moon", "moonc", "moonrun")
                      if (match := re.search(rf"^{name} (\S+)", toolchain, re.M))},
        "repository_regression_suite_executed": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Consumer flow passed; raw project and logs: {workspace}")
    print(f"Report: {args.output}")


if __name__ == "__main__":
    main()
