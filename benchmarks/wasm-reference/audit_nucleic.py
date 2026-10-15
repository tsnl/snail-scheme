"""Compare the ordered complete solution graph and all transformation values."""

import math
import unittest
from audit_alpha import read_program

# ---- Exact graph structure and bounded binary64 differences ----


def same_solutions(actual, expected):
    try:
        actual, expected = read_program(actual), read_program(expected)
        if not isinstance(actual, list) or len(actual) != len(expected):
            return False
        return all(same_solution(a, b) for a, b in zip(actual, expected))
    except (ValueError, TypeError, IndexError, StopIteration):
        return False


def same_solution(actual, expected):
    if not isinstance(actual, list) or len(actual) != len(expected):
        return False
    return all(same_variable(a, b) for a, b in zip(actual, expected))


def same_variable(actual, expected):
    if not isinstance(actual, list) or len(actual) != 3 or len(expected) != 3:
        return False
    if actual[:2] != expected[:2] or not isinstance(actual[2], list):
        return False
    if len(actual[2]) != 12 or len(expected[2]) != 12:
        return False
    for a, b in zip(actual[2], expected[2]):
        a, b = float(a), float(b)
        if not math.isfinite(a) or not math.isfinite(b) or not math.isclose(a, b, rel_tol=1e-11, abs_tol=1e-11):
            return False
    return True


# ---- Tests ----


class CompleteSolutionAuditTests(unittest.TestCase):
    original = "(((23 rA (1 0 0 0 1 0 0 0 1 0 0 0))))"

    def test_numerical_rounding_preserves_complete_graph(self):
        self.assertTrue(same_solutions(self.original, self.original.replace("1 0", "1.000000000001 0", 1)))

    def test_changed_identity_order_and_coordinate_are_rejected(self):
        for replacement in [self.original.replace("23", "22"), self.original.replace("rA", "rG"),
                            self.original.replace("1 0", "1.001 0", 1), self.original.replace("1 0", "1", 1),
                            self.original.replace("1 0", "NaN 0", 1), "()"]:
            self.assertFalse(same_solutions(self.original, replacement))


if __name__ == "__main__":
    unittest.main()
