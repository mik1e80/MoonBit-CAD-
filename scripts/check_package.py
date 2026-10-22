"""Verify the actual source archive and consume it without registry publication.

Requires Python 3.10+, Node.js 18+ and MoonBit on PATH. No third-party packages.
"""

from pathlib import Path, PurePosixPath
import os
import re
import shutil
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
tool_home = os.environ.get("MOON_HOME")
home_moon = Path(tool_home) / "bin" / ("moon.exe" if os.name == "nt" else "moon") if tool_home else None
MOON = str(home_moon) if home_moon and home_moon.is_file() else shutil.which("moon")
if MOON is None:
    raise SystemExit("MoonBit must be on PATH")


def run(*args: str, cwd: Path = ROOT) -> None:
    subprocess.run([MOON, *args], cwd=cwd, check=True, timeout=180)


def main() -> None:
    manifest = (ROOT / "moon.mod").read_text(encoding="utf-8-sig")
    name = re.search(r'^name\s*=\s*"([^"]+)"', manifest, re.M).group(1)
    version = re.search(r'^version\s*=\s*"([^"]+)"', manifest, re.M).group(1)
    run("package", "--list")
    archive = ROOT / "_build" / "publish" / f"{name.replace('/', '-')}-{version}.zip"
    work = Path(tempfile.mkdtemp(prefix="cad-package-check-")).resolve()
    package = work / "package"
    consumer = work / "consumer"
    package.mkdir()
    consumer.mkdir()
    required = {
        "moon.mod", "moon.pkg", "LICENSE", "README.md", "README.mbt.md",
        "THIRD_PARTY_NOTICES.md", "docs/ARCHITECTURE.md", "docs/ACCEPTANCE.md",
        "model.mbt", "solver.mbt", "pkg.generated.mbti", "cmd/mirror_demo/main.mbt",
        "cmd/bracket_demo/main.mbt", "cmd/bracket_demo/moon.pkg",
        "cmd/bracket_demo/bracket_wbtest.mbt", "cmd/bracket_demo/pkg.generated.mbti",
        "docs/SHOWCASE.md", "docs/images/bracket-before-after.svg",
        "scripts/bracket_showcase.cjs", "docs/POSITIONING.md", "docs/ECOSYSTEM.md",
        "examples/four_bar/main.mbt", "examples/four_bar/moon.pkg",
        "examples/four_bar/four_bar_wbtest.mbt", "examples/four_bar/pkg.generated.mbti",
        "examples/four_bar/README.md", "docs/images/four-bar-motion.svg",
        "scripts/four_bar_showcase.cjs",
    }
    with zipfile.ZipFile(archive) as bundle:
        names = set()
        for entry in bundle.infolist():
            relative = PurePosixPath(entry.filename.replace("\\", "/"))
            if relative.is_absolute() or ".." in relative.parts or any(":" in p for p in relative.parts):
                raise RuntimeError("Unsafe package path")
            if any(p in {".git", ".mooncakes", "_build", "target"} for p in relative.parts):
                raise RuntimeError(f"Development artifacts in package: {relative}")
            names.add(relative.as_posix())
            destination = package.joinpath(*relative.parts)
            destination.resolve().relative_to(package.resolve())
            if entry.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with bundle.open(entry) as src, destination.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
    if missing := required - names:
        raise RuntimeError(f"Missing package files: {sorted(missing)}")
    license_text = (package / "LICENSE").read_text(encoding="utf-8")
    if "Version 2.0, January 2004" not in license_text or "limitations under the License" not in license_text:
        raise RuntimeError("Incomplete project license")
    (work / "moon.work").write_text('members = ["package", "consumer"]\n', encoding="utf-8")
    (consumer / "moon.mod").write_text(
        f'name = "audit/cad_consumer"\nversion = "0.1.0"\nimport {{ "{name}@{version}" }}\n',
        encoding="utf-8",
    )
    (consumer / "moon.pkg").write_text(f'import {{ "{name}" @cad }} for "test"\n', encoding="utf-8")
    (consumer / "consumer_test.mbt").write_text('''///|
test "public API from packaged source" {
  let s = @cad.Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(3.0, 0.5)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(s.add_line(a, b))) |> ignore
  s.constrain(Distance(a, b, 5.0)) |> ignore
  let r = s.solve_and_apply().unwrap()
  assert_true(r.report.is_satisfied())
  assert_true((s.point(b).unwrap().x - 5.0).abs() < 1.0e-6)
  let other = @cad.Sketch::new()
  let foreign = other.add_point(0.0, 0.0)
  assert_true(s.point(foreign) is None)
  assert_false(s.set_point(foreign, { x: 9.0, y: 9.0 }))
}

///|
test "mirror API from packaged source" {
  let s = @cad.Sketch::new()
  let a = s.add_point(10.0, 0.0)
  let b = s.add_point(10.0, 10.0)
  let p = s.add_point(6.0, 3.0)
  let q = s.add_point(13.0, 2.5)
  s.constrain(Fix(a, 10.0, 0.0)) |> ignore
  s.constrain(Fix(b, 10.0, 10.0)) |> ignore
  s.constrain(Fix(p, 6.0, 3.0)) |> ignore
  s.constrain(Mirror(p, q, s.add_line(a, b))) |> ignore
  let r = s.solve_and_apply().unwrap()
  assert_true(r.report.is_satisfied())
  assert_true((r.point(q).unwrap().x - 14.0).abs() < 1.0e-6)
  assert_true((r.point(q).unwrap().y - 3.0).abs() < 1.0e-6)
}
''', encoding="utf-8")
    run("check", "--target", "all", "--deny-warn", cwd=consumer)
    for target in ("wasm", "wasm-gc", "js", "native"):
        run("test", "--target", target, cwd=consumer)
    subprocess.run(
        [MOON, "run", "cmd/bracket_demo"], cwd=package,
        stdout=subprocess.DEVNULL, check=True, timeout=180,
    )
    node = shutil.which("node")
    if node is None:
        raise RuntimeError("Node.js 18+ is required to verify the packaged showcase")
    subprocess.run(
        [node, "scripts/bracket_showcase.cjs", "--check"],
        cwd=package, check=True, timeout=180,
    )
    subprocess.run(
        [MOON, "run", "examples/four_bar"], cwd=package,
        stdout=subprocess.DEVNULL, check=True, timeout=180,
    )
    subprocess.run(
        [node, "scripts/four_bar_showcase.cjs", "--check"],
        cwd=package, check=True, timeout=180,
    )
    print(f"Package, both showcases and downstream consumer verified; workspace retained at {work}")


if __name__ == "__main__":
    main()
