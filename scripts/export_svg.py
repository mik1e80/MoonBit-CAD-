"""Generate/check three standalone SVGs returned by the pure MoonBit exporter.

Python 3.10+ standard library; no drawing libraries. Runs only the bracket demo.
"""
from pathlib import Path
import argparse
import copy
import json
import math
import os
import shutil
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
NS = {"s": "http://www.w3.org/2000/svg"}


def inspect_svg(text: str, event: dict) -> list[dict]:
    root = ET.fromstring(text)
    assert root.tag == "{" + NS["s"] + "}svg"
    assert root.attrib["viewBox"] == "0 0 720 440"
    assert root.find("s:title", NS) is not None
    assert not root.findall(".//s:script", NS)
    lines = root.findall("s:g[@id='lines']/s:line", NS)
    circles = root.findall("s:g[@id='circles']/s:circle", NS)
    points = root.findall("s:g[@id='points']/s:circle", NS)
    assert len(lines) == 6 and len(circles) == 4 and len(points) == 12
    # Independent map from shared world bounds (-12,-12)..(180,100).
    scale = 360 / 112
    def screen(p): return [360 + (p[0] - 84) * scale, 236 - (p[1] - 44) * scale]
    def near(actual, expected):
        assert math.isfinite(float(actual)) and abs(float(actual) - expected) < 1e-7
    geometry = event["geometry"]
    expected_points = geometry["corners"] + geometry["axis_points"] + [h[:2] for h in geometry["holes"]]
    for i, (node, p) in enumerate(zip(points, expected_points)):
        assert node.attrib["data-point"] == str(i)
        x, y = screen(p)
        near(node.attrib["cx"], x); near(node.attrib["cy"], y)
    endpoints = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (6, 7)]
    for node, (a, b) in zip(lines, endpoints):
        x, y = screen(expected_points[a]); near(node.attrib["x1"], x); near(node.attrib["y1"], y)
        x, y = screen(expected_points[b]); near(node.attrib["x2"], x); near(node.attrib["y2"], y)
    for node, p in zip(circles, geometry["holes"]):
        x, y = screen(p)
        near(node.attrib["cx"], x); near(node.attrib["cy"], y); near(node.attrib["r"], p[2] * scale)
    return [node.attrib for node in lines + circles + points]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="update the three SVG files after inspection")
    parser.add_argument("--check", action="store_true", help="verify committed SVGs without updating them")
    args = parser.parse_args()
    assert not (args.write and args.check), "Choose --write or --check"
    executable = "moon.exe" if os.name == "nt" else "moon"
    moon = str(Path(os.environ["MOON_HOME"]) / "bin" / executable) if os.getenv("MOON_HOME") else shutil.which(executable)
    if not moon: raise RuntimeError("MoonBit must be on PATH or MOON_HOME must be set")
    result = subprocess.run([moon, "run", "examples/parametric_bracket", "--target", "js", "--deny-warn"],
                            cwd=ROOT, capture_output=True, text=True, timeout=120)
    if result.returncode: raise RuntimeError(result.stderr)
    events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    assert [e["stage"] for e in events] == ["initial", "widened", "larger_holes", "edited", "conflict", "recovered"]
    before, after, conflict = events[0], events[3], events[4]
    assert before["applied"] and after["applied"] and not conflict["applied"]
    assert before["parameters"]["width"] == 120 and after["parameters"]["width"] == 160
    assert after["geometry"] == conflict["geometry"], "Failed edit changed stored geometry"
    assert conflict["report"]["status"] in ("Stalled", "IterationLimit")
    shapes = {name: inspect_svg(event["svg"], event) for name, event in (("before", before), ("after", after), ("conflict", conflict))}
    assert shapes["after"] == shapes["conflict"], "Conflict SVG drew unapplied candidate geometry"
    # Check the independent reader rejects a corrupted circle radius.
    corrupted = copy.deepcopy(after)
    corrupted["geometry"]["holes"][0][2] += 1
    try: inspect_svg(after["svg"], corrupted)
    except AssertionError: pass
    else: raise AssertionError("SVG checker accepted a corrupted radius")
    folder = ROOT / "docs/images/svg-export"
    for name, event in (("before", before), ("after", after), ("conflict", conflict)):
        path = folder / (name + ".svg")
        if args.write:
            folder.mkdir(parents=True, exist_ok=True)
            path.write_text(event["svg"], encoding="utf-8", newline="\n")
        else:
            assert path.read_text(encoding="utf-8") == event["svg"], f"Stale {path}; review --write output"
    raw = ROOT / "_build/svg-export/events.json"
    raw.parent.mkdir(parents=True, exist_ok=True)
    raw.write_text(json.dumps(events, indent=2) + "\n", encoding="utf-8")
    print("Verified before.svg, after.svg, conflict.svg: same scale, stored geometry, 6 lines / 4 circles / 12 points each")


if __name__ == "__main__":
    main()
