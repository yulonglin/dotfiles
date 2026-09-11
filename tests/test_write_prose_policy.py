"""Check writer metadata against the real router source without applying it."""

import copy
import importlib.machinery
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader(
    "writer_policy_wire", str(ROOT / "custom_bins/model-router-wire")
)
spec = importlib.util.spec_from_loader(loader.name, loader)
wire = importlib.util.module_from_spec(spec)
loader.exec_module(wire)
wire.SOURCE = ROOT / "config/model-router.toml"
wire.AGENTS_DIR = ROOT / "claude/agents"


class WriterPolicyTests(unittest.TestCase):
    def setUp(self):
        self.source = wire.load_source()
        self.writers = [
            model
            for model in wire.enabled(self.source)
            if "writer-priority" in model and wire.effort_of(model) is not None
        ]

    def test_priorities_are_positive_and_unique(self):
        self.assertTrue(self.writers, "At least one writer must be available")
        priorities = []
        for model in self.source["models"]:
            if "writer-priority" not in model:
                continue
            priority = model["writer-priority"]
            self.assertIs(type(priority), int)
            self.assertGreater(priority, 0)
            self.assertNotEqual(model["provider"], "anthropic")
            priorities.append(priority)
        self.assertEqual(len(priorities), len(set(priorities)))

    def test_eligible_writers_have_matching_generated_agents(self):
        for model in self.writers:
            with self.subTest(model=model["id"]):
                self.assertEqual(
                    wire.agent_path(model).read_text(), wire.render_agent(model)
                )

    def test_writer_metadata_does_not_change_generated_output(self):
        without_policy = copy.deepcopy(self.source)
        for model in without_policy["models"]:
            model.pop("writer-priority", None)
        self.assertEqual(
            wire.render_router_config(self.source),
            wire.render_router_config(without_policy),
        )
        self.assertEqual(
            wire.render_settings(self.source, {}, "test-only"),
            wire.render_settings(without_policy, {}, "test-only"),
        )
        for model, plain in zip(self.source["models"], without_policy["models"]):
            if wire.effort_of(model) is not None:
                self.assertEqual(wire.render_agent(model), wire.render_agent(plain))


if __name__ == "__main__":
    unittest.main()
