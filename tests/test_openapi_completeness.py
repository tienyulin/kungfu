"""Tests for openapi_completeness.py (find_gaps)."""

import unittest
from typing import Any

from _loader import load

oc: Any = load("skills/wiki-doc-author/scripts/openapi_completeness.py")

_COMPLETE = {
    "paths": {
        "/c": {
            "post": {
                "summary": "扣款",
                "parameters": [{"name": "id", "description": "帳號"}],
                "responses": {
                    "200": {
                        "description": "ok",
                        "content": {"application/json": {"example": {"ok": 1}}},
                    },
                    "400": {"description": "bad"},
                },
            }
        }
    }
}


class TestFindGaps(unittest.TestCase):
    """find_gaps flags missing summary / param desc / 4xx / inline example."""

    def test_complete_spec_has_no_gaps(self):
        """A fully documented operation reports nothing."""
        self.assertEqual(oc.find_gaps(_COMPLETE), [])

    def test_empty_specs_have_no_gaps(self):
        """Empty / pathless specs report nothing."""
        self.assertEqual(oc.find_gaps({}), [])
        self.assertEqual(oc.find_gaps({"paths": {}}), [])

    def test_non_http_keys_ignored(self):
        """Path-item level non-HTTP keys are not operations."""
        self.assertEqual(oc.find_gaps({"paths": {"/c": {"parameters": []}}}), [])

    def test_bare_operation_reports_each_gap(self):
        """A bare op flags summary, undocumented param, missing 4xx and example."""
        bare = {
            "paths": {"/c": {"post": {"parameters": [{"name": "id"}], "responses": {"200": {}}}}}
        }
        gaps = oc.find_gaps(bare)
        self.assertTrue(any("summary" in g for g in gaps))
        self.assertTrue(any("parameter 'id'" in g for g in gaps))
        self.assertTrue(any("4xx" in g for g in gaps))
        self.assertTrue(any("範例" in g for g in gaps))

    def test_ref_only_example_is_still_a_gap(self):
        """An example reachable only via $ref (not inline) still counts as missing."""
        ref_only = {
            "paths": {
                "/c": {
                    "post": {
                        "summary": "x",
                        "responses": {
                            "200": {"$ref": "#/components/x"},
                            "400": {"description": "e"},
                        },
                    }
                }
            }
        }
        self.assertTrue(any("範例" in g for g in oc.find_gaps(ref_only)))


if __name__ == "__main__":
    unittest.main()
