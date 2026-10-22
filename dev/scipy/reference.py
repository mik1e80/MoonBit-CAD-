"""Optional SciPy reference experiment; never imported by the MoonBit runtime."""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

import numpy as np
import scipy
from scipy.optimize import least_squares

ROOT = Path(__file__).resolve().parents[2]
SIDES = np.array([3.0, 4.0, 5.0])
SETTINGS = dict(method="trf", jac="3-point", ftol=1e-12, xtol=1e-12,
                gtol=1e-12, max_nfev=200, x_scale=1.0, loss="linear")


def sha(data: str) -> str:
    return hashlib.sha256(data.encode()).hexdigest()


def command(args: list[str]) -> str:
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError(f"{args}: {result.stderr}\n{result.stdout}")
    return result.stdout


def inputs(target: str, output: Path) -> tuple[list[dict], str]:
    executable = "moon.exe" if os.name == "nt" else "moon"
    moon = str(Path(os.environ["MOON_HOME"]) / "bin" / executable) if os.getenv("MOON_HOME") else shutil.which(executable)
    if not moon:
        raise RuntimeError("MoonBit must be on PATH or MOON_HOME must be set")
    raw = command([moon, "run", "cmd/validation", "--target", target])
    (output / "moonbit-validation.jsonl").write_text(raw, encoding="utf-8")
    metadata, *models = [json.loads(line) for line in raw.splitlines() if line.strip()]
    assert metadata == dict(kind="validation_suite", schema=1, seed=20261022, cases=400)
    assert len(models) == 400
    assert len({(row["group"], row["index"]) for row in models}) == 400
    for row in models:
        row["id"] = f'{row["group"]}:{row["index"]}'
        row["source"] = "fresh_moonbit_js" if target == "js" else f"fresh_moonbit_{target}"
    # Reuse the first 100 published random samples without rerunning 1000 solves.
    folder = ROOT / "docs/validation-results"
    summary = json.loads((folder / "random-triangle-js.json").read_text(encoding="utf-8"))
    csv_text = (folder / "random-triangle-js.csv").read_text(encoding="utf-8")
    assert sha(csv_text) == summary["cases_csv_sha256"]
    digest = hashlib.sha256()
    for name in summary["source_files"]:
        digest.update((name + "\n" + (ROOT / name).read_text(encoding="utf-8")).encode())
    assert digest.hexdigest() == summary["source_sha256"], "Recorded random corpus is stale"
    samples = list(csv.DictReader(io.StringIO(csv_text)))
    assert len(samples) == 1000
    for i, row in enumerate(samples[:100]):
        assert int(row["index"]) == i and int(row["seed"]) == 20261022 + 97 * i
        assert not row["correctness_failures"]
        models.append(dict(
            id=f"random:{i}", source="recorded_moonbit_js", family="free_triangle",
            group="random", index=i, seed=int(row["seed"]), parameters=[3, 4, 5],
            transform=dict(x=0.0, y=0.0, angle=0.0, scale=1.0),
            length_tolerance=1e-7, angular_tolerance=1e-8,
            initial_points=json.loads(row["initial_points"]), initial_radii=[],
            points=json.loads(row["candidate_points"]), radii=[], status=row["status"],
            max_tolerance_ratio=float(row["reported_max_ratio"])))
    return models, command([moon, "version", "--all"]).strip()


def geometry(row: dict):
    """A numerically scaled representation of the same physical variables."""
    t = row["transform"]
    origin = np.array([t["x"], t["y"]])
    scale = t["scale"]
    initial = (np.array(row["initial_points"]) - origin) / scale
    radii = np.array(row["initial_radii"]) / scale
    n = len(initial)
    x0 = np.concatenate([initial.ravel(), radii])
    length_tol = row["length_tolerance"] / scale
    angle_tol = row["angular_tolerance"]
    family = row["family"]
    if family != "free_triangle":
        w, h, radius, fraction = row["parameters"]

    def target(x, y):
        c, s = math.cos(t["angle"]), math.sin(t["angle"])
        world = origin + np.array([x * c - y * s, x * s + y * c]) * scale
        return (world - origin) / scale

    def residual(x):
        points, rs = x[:n * 2].reshape(n, 2), x[n * 2:]
        norm = lambda v: math.hypot(*v)
        if family == "free_triangle":
            return np.array([norm(points[a] - points[b]) - side
                             for a, b, side in [(0, 1, 3), (1, 2, 4), (0, 2, 5)]]) / length_tol
        values = []
        def length(*components):
            values.extend(float(value) / length_tol for value in components)
        def angle(value):
            values.append(float(value) / angle_tol)
        def edge(a, b):
            return points[b] - points[a]
        def unit(v):
            return v / norm(v)
        def cross(a, b):
            return a[0] * b[1] - a[1] * b[0]
        targets = [target(0, 0), target(w, 0)] if family in ("triangle", "rectangle") else [target(-w, 0), target(w, 0)]
        for i in range(2):
            length(*(points[i] - targets[i]))
        if family == "triangle":
            length(norm(edge(0, 2)) - math.hypot(w * fraction, h))
            length(norm(edge(1, 2)) - math.hypot(w * (1 - fraction), h))
        elif family == "rectangle":
            ab, bc, cd, ad = (unit(edge(a, b)) for a, b in [(0, 1), (1, 2), (2, 3), (0, 3)])
            angle(np.dot(ab, bc))
            length(norm(edge(1, 2)) - h)
            angle(cross(ab, cd))
            length(norm(edge(2, 3)) - w)
            angle(cross(bc, ad))
        elif family == "mirror_circles":
            axis = unit(edge(0, 1))
            length(*(points[2] - target(w * fraction, h)))
            p, q = edge(0, 2), edge(0, 3)
            length(np.dot(q - p, axis), cross(axis, (p + q) / 2))
            length(rs[0] - radius, rs[0] - rs[1])
        elif family == "line_circle_tangent":
            axis = unit(edge(0, 1))
            length(rs[0] - radius)
            length(abs(cross(axis, edge(0, 2))) - rs[0])
            length(norm(edge(0, 2)) - math.hypot(w, radius))
        else:
            raise ValueError(f"Unknown family {family}")
        return np.array(values)

    lower, upper = np.full_like(x0, -np.inf), np.full_like(x0, np.inf)
    lower[n * 2:] = 0.0  # Positive-radius domain; all measured radii stay far from zero.
    return x0, residual, (lower, upper), n, origin, scale


def compare(row: dict) -> dict:
    x0, residual, bounds, n, origin, scale = geometry(row)
    moon_points = (np.array(row["points"]) - origin) / scale
    moon_radii = np.array(row["radii"]) / scale
    moon_x = np.concatenate([moon_points.ravel(), moon_radii])
    moon_ratio = float(np.max(np.abs(residual(moon_x))))
    record = dict(id=row["id"], family=row["family"], source=row["source"], seed=row["seed"],
                  initial_points=row["initial_points"], initial_radii=row["initial_radii"],
                  moonbit_points=row["points"], moonbit_radii=row["radii"],
                  moonbit_status=row["status"], moonbit_independent_ratio=moon_ratio,
                  scale=scale, length_tolerance=row["length_tolerance"])
    try:
        reference = least_squares(residual, x0, bounds=bounds, **SETTINGS)
        ref_points = reference.x[:n * 2].reshape(n, 2)
        ref_radii = reference.x[n * 2:]
        ref_ratio = float(np.max(np.abs(residual(reference.x))))
        raw_gap = float(np.max(np.abs(moon_points - ref_points)))
        aligned = ref_points
        alignment = "direct"
        if row["family"] == "free_triangle":
            # Rigid alignment only: no scale fitting or side-length adjustment.
            a, b = ref_points - ref_points.mean(axis=0), moon_points - moon_points.mean(axis=0)
            u, _, vt = np.linalg.svd(a.T @ b)
            aligned = a @ (u @ vt) + moon_points.mean(axis=0)
            alignment = "rigid_including_reflection"
        coordinate_gap = float(np.max(np.abs(moon_points - aligned)))
        radius_gap = float(np.max(np.abs(moon_radii - ref_radii))) if len(ref_radii) else None
        tolerance = row["length_tolerance"] / scale
        category = "agree"
        if row["status"] != "Satisfied" or not math.isfinite(moon_ratio) or moon_ratio > 1.00001:
            category = "moonbit_residual_not_met"
        elif not math.isfinite(ref_ratio) or ref_ratio > 1.00001 or np.any(ref_radii <= 0):
            category = "reference_residual_not_met"
        elif coordinate_gap > 100 * tolerance or (radius_gap is not None and radius_gap > 100 * tolerance):
            category = "different_configuration"
        record.update(
            category=category, scipy_success=bool(reference.success), scipy_status=int(reference.status),
            scipy_message=str(reference.message), scipy_nfev=int(reference.nfev),
            scipy_njev=int(reference.njev) if reference.njev is not None else None,
            scipy_independent_ratio=ref_ratio, scipy_points=(ref_points * scale + origin).tolist(),
            scipy_radii=(ref_radii * scale).tolist(), alignment=alignment,
            raw_coordinate_gap_divided_by_scale=raw_gap, coordinate_gap_divided_by_scale=coordinate_gap,
            coordinate_gap_world_units=coordinate_gap * scale,
            coordinate_gap_in_length_tolerances=coordinate_gap / tolerance,
            radius_gap_divided_by_scale=radius_gap,
            radius_gap_world_units=radius_gap * scale if radius_gap is not None else None,
            radius_gap_in_length_tolerances=radius_gap / tolerance if radius_gap is not None else None)
    except Exception as error:
        record.update(category="reference_exception", error=f"{type(error).__name__}: {error}")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=500, help="first N of the fixed 500-case corpus; use 8 for a smoke check")
    parser.add_argument("--write", action="store_true", help="save the full 500-case development snapshot and CSV")
    args = parser.parse_args()
    if not 1 <= args.count <= 500 or (args.write and args.count != 500):
        parser.error("--count must be 1..500; --write requires 500")
    output = ROOT / "_build/scipy-reference"
    output.mkdir(parents=True, exist_ok=True)
    models, moon_version = inputs("js", output)
    results = [compare(row) for row in models[:args.count]]
    source_files = ["dev/scipy/reference.py", "dev/scipy/requirements.txt", "cmd/validation/main.mbt",
                    "cmd/random_triangle/main.mbt", "errors.mbt", "model.mbt", "solver.mbt", "validate.mbt",
                    "residual.mbt", "autodiff.mbt", "linalg.mbt"]
    digest = hashlib.sha256()
    for name in source_files:
        digest.update((name + "\n" + (ROOT / name).read_text(encoding="utf-8")).encode())
    def maximum(key):
        values = [r[key] for r in results if r.get(key) is not None and math.isfinite(r[key])]
        return max(values) if values else None
    counts = {category: sum(r["category"] == category for r in results) for category in sorted({r["category"] for r in results})}
    summary = dict(schema=1, experiment="moonbit-vs-scipy-500-v1", cases=args.count,
                   categories=counts, settings=SETTINGS, source_sha256=digest.hexdigest(), source_files=source_files,
                   families={family: sum(r["family"] == family for r in results) for family in sorted({r["family"] for r in results})},
                   radius_cases=sum(bool(r["moonbit_radii"]) for r in results),
                   scipy_success_flag_count=sum(bool(r.get("scipy_success")) for r in results),
                   maxima={key: maximum(key) for key in [
                       "moonbit_independent_ratio", "scipy_independent_ratio",
                       "coordinate_gap_divided_by_scale", "coordinate_gap_in_length_tolerances",
                       "radius_gap_divided_by_scale", "radius_gap_in_length_tolerances"]},
                   environment=dict(python=sys.version, scipy=scipy.__version__, numpy=np.__version__,
                                    platform=platform.platform(), moon=moon_version),
                   unresolved=[{k: r[k] for k in ("id", "category", "scipy_status", "scipy_message", "error") if k in r}
                               for r in results if r["category"] != "agree"])
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=list(dict.fromkeys(key for r in results for key in r)), lineterminator="\n")
    writer.writeheader()
    writer.writerows({key: json.dumps(value, ensure_ascii=False, allow_nan=False) if isinstance(value, (list, dict))
                      else value for key, value in r.items()} for r in results)
    csv_text = stream.getvalue()
    summary["cases_csv_sha256"] = sha(csv_text)
    report = dict(summary=summary, cases=results)
    (output / f"js-{args.count}.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (output / f"js-{args.count}.csv").write_text(csv_text, encoding="utf-8", newline="\n")
    if args.write:
        folder = ROOT / "docs/validation-results"
        (folder / "scipy-reference-js.json").write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        (folder / "scipy-reference-js.csv").write_text(csv_text, encoding="utf-8", newline="\n")
    print(json.dumps(summary, indent=2))
    return 0 if counts.get("agree", 0) == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
