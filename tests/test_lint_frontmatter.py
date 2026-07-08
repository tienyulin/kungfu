"""Tests for lint_frontmatter.py (lint_file)."""

import os
import tempfile
import unittest
from typing import Any

from _loader import load

lf: Any = load("skills/wiki-doc-author/scripts/lint_frontmatter.py")


class TestLintFile(unittest.TestCase):
    """lint_file enforces the frontmatter schema on markdown docs."""

    def _write(self, name: str, text: str) -> str:
        """Write a doc into the per-test temp dir and return its path."""
        path = os.path.join(self.dir.name, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return path

    def setUp(self):
        """Give each test its own temp directory."""
        # addCleanup handles teardown; a `with` block can't span setUp + tests
        self.dir = tempfile.TemporaryDirectory()  # pylint: disable=consider-using-with
        self.addCleanup(self.dir.cleanup)

    def test_valid_doc_passes(self):
        """A conforming reference doc has no violations."""
        p = self._write(
            "good.md", "---\ntype: reference\nsource_app: nightly\ntags: [cronjob]\n---\n# Job\nx\n"
        )
        self.assertEqual(lf.lint_file(p), [])

    def test_bad_type_flagged(self):
        """A type outside the controlled vocabulary is flagged."""
        p = self._write("bt.md", "---\ntype: cronjob\nsource_app: x\n---\n# X\nx\n")
        self.assertTrue(any("受控詞彙" in e for e in lf.lint_file(p)))

    def test_missing_required_flagged(self):
        """A missing required field (source_app) is flagged."""
        p = self._write("miss.md", "---\ntype: api\n---\n# X\nGET /x — y\n")
        self.assertTrue(any("source_app" in e for e in lf.lint_file(p)))

    def test_bad_source_app_flagged(self):
        """A source_app not in lower-hyphen form is flagged."""
        p = self._write("bs.md", "---\ntype: reference\nsource_app: Bad_App\n---\n# X\nx\n")
        self.assertTrue(any("source_app" in e for e in lf.lint_file(p)))

    def test_api_with_endpoint_line_passes(self):
        """An api doc with an endpoint line and no openapi.json passes."""
        p = self._write(
            "mb.md", "---\ntype: api\nsource_app: pay\n---\n# Pay\nPOST /charge — 扣款\n"
        )
        self.assertEqual(lf.lint_file(p), [])

    def test_api_without_endpoint_or_openapi_flagged(self):
        """An api doc with neither an endpoint line nor openapi.json is flagged."""
        p = self._write("ae.md", "---\ntype: api\nsource_app: pay\n---\n# Pay\n沒有端點。\n")
        self.assertTrue(any("endpoint" in e for e in lf.lint_file(p)))

    def test_api_with_companion_openapi_passes(self):
        """A companion openapi.json removes the endpoint-line requirement."""
        self._write("openapi.json", "{}")
        p = self._write(
            "oa.md", "---\ntype: api\nsource_app: pay\n---\n# Pay\n端點由 openapi 帶。\n"
        )
        self.assertEqual(lf.lint_file(p), [])


if __name__ == "__main__":
    unittest.main()
