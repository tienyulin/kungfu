"""Tests for the skill validator (skill-author/scripts/validate_skill.py)."""

# tests legitimately exercise the validator's internal helpers
# pylint: disable=protected-access

import json
import os
import tempfile
import unittest
from typing import Any

from _loader import load

vs: Any = load("skills/skill-author/scripts/validate_skill.py")

_FM = "---\nname: {n}\ndescription: {d}\n---\n# body\n"
_GOOD_DESC = '測試用 skill。Triggers - "做測試"、"/demo-skill"。'


def _write(path: str, text: str) -> None:
    """Write text to path, creating parent dirs."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


class TestCheckName(unittest.TestCase):
    """_check_name enforces kebab-case, dir match and length."""

    def test_valid_name_passes(self):
        """A kebab name matching its dir has no errors."""
        self.assertFalse(vs._check_name("d/foo-bar", "foo-bar", "foo-bar"))

    def test_uppercase_rejected(self):
        """Non-kebab (uppercase) is flagged."""
        self.assertTrue(vs._check_name("d/foo", "Foo", "Foo"))

    def test_name_dir_mismatch_rejected(self):
        """name != dir is flagged."""
        self.assertTrue(vs._check_name("d/foo", "bar", "foo"))

    def test_over_long_rejected(self):
        """A name over MAX_NAME is flagged."""
        long = "a" * (vs.MAX_NAME + 1)
        self.assertTrue(vs._check_name("d/x", long, long))


class TestCheckDesc(unittest.TestCase):
    """_check_desc enforces the repo's Triggers convention."""

    def test_with_triggers_passes(self):
        """A description carrying 'Triggers -' has no errors."""
        self.assertFalse(vs._check_desc("d", 'x. Triggers - "a"、"/a"。')[0])

    def test_missing_triggers_rejected(self):
        """No Triggers tag is flagged."""
        self.assertTrue(vs._check_desc("d", "no trigger tag")[0])

    def test_empty_desc_rejected(self):
        """Empty description is flagged."""
        self.assertTrue(vs._check_desc("d", "")[0])


class TestValidateSkillAndMarketplace(unittest.TestCase):
    """validate_skill + _check_marketplace on real temp fixtures."""

    def test_valid_skill_dir_passes(self):
        """A well-formed skill dir validates clean."""
        with tempfile.TemporaryDirectory() as root:
            _write(
                os.path.join(root, "demo-skill/SKILL.md"), _FM.format(n="demo-skill", d=_GOOD_DESC)
            )
            errs, _ = vs.validate_skill(os.path.join(root, "demo-skill"))
            self.assertEqual(errs, [])

    def test_name_dir_mismatch_caught(self):
        """A frontmatter name unlike its dir is caught."""
        with tempfile.TemporaryDirectory() as root:
            _write(os.path.join(root, "wrong/SKILL.md"), _FM.format(n="mismatch", d=_GOOD_DESC))
            self.assertTrue(vs.validate_skill(os.path.join(root, "wrong"))[0])

    def test_marketplace_registration(self):
        """Registered skills pass; an unregistered one is flagged."""
        with tempfile.TemporaryDirectory() as root:
            _write(
                os.path.join(root, "demo-skill/SKILL.md"), _FM.format(n="demo-skill", d=_GOOD_DESC)
            )
            _write(os.path.join(root, "other/SKILL.md"), _FM.format(n="other", d=_GOOD_DESC))
            mkt = {
                "plugins": [
                    {"name": "demo-skill", "source": "./", "skills": ["./demo-skill"]},
                    {"name": "bundle", "source": "./", "skills": ["./demo-skill", "./other"]},
                ]
            }
            _write(os.path.join(root, ".claude-plugin/marketplace.json"), json.dumps(mkt))
            self.assertFalse(vs._check_marketplace(root, ["demo-skill"]))
            self.assertTrue(vs._check_marketplace(root, ["ghost"]))


if __name__ == "__main__":
    unittest.main()
