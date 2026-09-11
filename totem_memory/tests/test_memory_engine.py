import unittest
from modular_memory.engine import TotemMemoryEngine
from modular_memory.models import Fact, WorkingKnowledge


class TestTotemMemoryEngine(unittest.TestCase):
    def setUp(self):
        self.engine = TotemMemoryEngine(totem_id="arch-01", totem_name="Architect Totem")

    def test_record_facts(self):
        f1 = self.engine.record_fact(
            content="Native macOS app bundle requires index.cjs in Contents/Resources/server",
            domain="arch",
            source_event="code_audit",
            tags=["bundle", "server", "macos"],
        )
        self.assertEqual(len(self.engine.bundle.facts), 1)
        self.assertEqual(f1.domain, "arch")
        self.assertTrue(f1.id.startswith("fact-"))

    def test_record_working_knowledge_with_provenance(self):
        wk = self.engine.record_working_knowledge(
            title="Resource Bundle Mirroring Invariant",
            semantic_summary="When server/index.cjs is modified, it must be copied directly into the app bundle resources before launching native WKWebView.",
            origin_seed="User reported server endpoint failure",
            journey_trace=["conv:session-1", "step:audit_bundle", "step:verify_sync"],
            domain="arch",
            tags=["bundle", "deployment"],
        )
        self.assertEqual(len(self.engine.bundle.working_knowledge), 1)
        self.assertEqual(wk.title, "Resource Bundle Mirroring Invariant")
        self.assertEqual(len(wk.relational_chain.journey_trace), 3)

    def test_reinforce_and_distill_to_wisdom_and_legacy(self):
        # Record working knowledge
        wk = self.engine.record_working_knowledge(
            title="Strict Invariant Persistence",
            semantic_summary="All API key modifications must atomically sync to both UI state and local auth.json storage.",
            origin_seed="Key synchronization failure bug",
            journey_trace=["conv:conv-001", "conv:conv-002"],
            domain="ops",
        )

        # Reinforce knowledge across 3 sessions
        self.engine.reinforce_knowledge(wk.id, conversation_id="conv-001")
        self.engine.reinforce_knowledge(wk.id, conversation_id="conv-002")
        self.engine.reinforce_knowledge(wk.id, conversation_id="conv-003")

        self.assertGreaterEqual(wk.reinforcement_count, 3)

        # Run cognitive distillation
        result = self.engine.distill()
        self.assertGreaterEqual(result["crystallized_count"], 1)
        self.assertEqual(len(self.engine.bundle.wisdom), 1)
        self.assertEqual(len(self.engine.bundle.legacy), 1)

        wisdom = self.engine.bundle.wisdom[0]
        self.assertIn("Strict Invariant Persistence", wisdom.declaration)

        legacy = self.engine.bundle.legacy[0]
        self.assertEqual(legacy.origin_aphorism_id, wisdom.id)

    def test_synthesize_prompt_context(self):
        self.engine.record_fact("Endpoint /api/modular/cli/exec executes in zsh")
        self.engine.record_working_knowledge(
            title="CLI Tool Calling",
            semantic_summary="CLI commands must be spawned with zsh -c and PAGER=cat to avoid pager traps.",
            domain="ops",
        )
        context = self.engine.synthesize_prompt_context()
        self.assertIn("Verified Ground Truth Facts", context)
        self.assertIn("Active Working Knowledge", context)

    def test_serialization(self):
        self.engine.record_fact("Test serialization fact")
        json_str = self.engine.to_json()
        restored = TotemMemoryEngine.from_json(json_str)
        self.assertEqual(len(restored.bundle.facts), 1)
        self.assertEqual(restored.bundle.totem_id, "arch-01")

    def test_memory_caching_and_invalidation(self):
        self.engine.record_fact("Fast inference via llama.cpp server")
        stats_initial = self.engine.get_cache_stats()
        self.assertEqual(stats_initial["cached_entries"], 0)

        # First call: cache miss, cached entry created
        c1 = self.engine.synthesize_prompt_context()
        stats_after_first = self.engine.get_cache_stats()
        self.assertEqual(stats_after_first["cache_misses"], 1)
        self.assertEqual(stats_after_first["cache_hits"], 0)
        self.assertEqual(stats_after_first["cached_entries"], 1)

        # Second call: cache hit!
        c2 = self.engine.synthesize_prompt_context()
        self.assertEqual(c1, c2)
        stats_after_second = self.engine.get_cache_stats()
        self.assertEqual(stats_after_second["cache_hits"], 1)

        # State mutation invalidates cache
        self.engine.record_fact("New invariant recorded")
        stats_after_mutation = self.engine.get_cache_stats()
        self.assertEqual(stats_after_mutation["cached_entries"], 0)

        # Third call: cache miss again with updated content
        c3 = self.engine.synthesize_prompt_context()
        self.assertIn("New invariant recorded", c3)
        stats_after_third = self.engine.get_cache_stats()
        self.assertEqual(stats_after_third["cache_misses"], 2)


if __name__ == "__main__":
    unittest.main()

