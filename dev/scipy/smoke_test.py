"""Four scoped checks for the optional reference tool, not a regression suite."""
import copy
import unittest
import numpy as np

from reference import compare, geometry


def row(family, initial, points, radii=None):
    return dict(id="smoke:0", family=family, source="synthetic_control", seed=1,
                parameters=[6.0, 4.0, 1.0, 0.5],
                transform=dict(x=0.0, y=0.0, angle=0.0, scale=1.0),
                length_tolerance=1e-7, angular_tolerance=1e-8,
                initial_points=initial, initial_radii=[1.1] * len(radii or []),
                points=points, radii=radii or [], status="Satisfied")


class ReferenceSmokeTest(unittest.TestCase):
    def test_known_triangle_residual_and_comparison(self):
        case = row("triangle", [[0.1, -0.1], [6.1, 0.1], [3.1, 3.9]],
                   [[0, 0], [6, 0], [3, 4]])
        _, residual, _, _, _, _ = geometry(case)
        self.assertEqual(residual(np.array([0, 0, 6, 0, 3, 4])).tolist(), [0, 0, 0, 0, 0, 0])
        self.assertEqual(compare(case)["category"], "agree")

    def test_free_pose_is_aligned_without_fitting_scale(self):
        case = row("free_triangle", [[-2, -1], [-2, 4], [6, -8]],
                   [[100, 100], [100, 103], [96, 103]])
        result = compare(case)
        self.assertEqual(result["category"], "agree")
        self.assertGreater(result["raw_coordinate_gap_divided_by_scale"], 50)
        self.assertLess(result["coordinate_gap_divided_by_scale"], 1e-5)

    def test_false_moonbit_success_is_rejected(self):
        case = row("triangle", [[0.1, -0.1], [6.1, 0.1], [3.1, 3.9]],
                   [[0, 0], [6, 0], [4, 4]])
        self.assertEqual(compare(case)["category"], "moonbit_residual_not_met")

    def test_radius_difference_is_measured(self):
        case = row("mirror_circles",
                   [[-6.1, 0.1], [6.1, -0.1], [3.1, 4.1], [2.9, -3.9]],
                   [[-6, 0], [6, 0], [3, 4], [3, -4]], [1.00000005, 1.00000005])
        result = compare(copy.deepcopy(case))
        self.assertEqual(result["category"], "agree")
        self.assertAlmostEqual(result["radius_gap_in_length_tolerances"], 0.5, places=4)


if __name__ == "__main__":
    unittest.main()
