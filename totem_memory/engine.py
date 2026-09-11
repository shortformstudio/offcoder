"""
Totem Cognitive Memory Engine.
Manages the 4-phase distillation hierarchy:
Atlas -> Facts -> Working Knowledge -> Wisdom -> Legacy []
"""

import json
import os
import time
from typing import List, Dict, Any, Optional, Callable
from .models import (
    Fact,
    WorkingKnowledge,
    RelationalProvenance,
    WisdomAphorism,
    LegacyDeclaration,
    MemoryAtlas,
    MemoryCategory,
    TotemMemoryBundle,
)
from .biodynamics import BiodynamicMemoryConsolidator


class TotemMemoryEngine:
    def __init__(
        self,
        bundle: Optional[TotemMemoryBundle] = None,
        totem_id: str = "default",
        totem_name: str = "Default Totem",
    ):
        if bundle:
            self.bundle = bundle
        else:
            self.bundle = TotemMemoryBundle(
                totem_id=totem_id,
                totem_name=totem_name,
                atlas=self._build_default_atlas(),
            )
        self.biodynamics = BiodynamicMemoryConsolidator()
        self._context_cache: Dict[str, str] = {}
        self._cache_hits = 0
        self._cache_misses = 0

    def _invalidate_cache(self) -> None:
        """Clears all cached prompt contexts upon state mutation."""
        self._context_cache.clear()

    def get_cache_stats(self) -> Dict[str, Any]:
        """Returns performance and capacity telemetry for the memory engine cache."""
        total = self._cache_hits + self._cache_misses
        return {
            "cached_entries": len(self._context_cache),
            "cache_hits": self._cache_hits,
            "cache_misses": self._cache_misses,
            "hit_ratio": (self._cache_hits / total) if total > 0 else 1.0,
            "total_facts": len(self.bundle.facts),
            "total_working_knowledge": len(self.bundle.working_knowledge),
            "total_wisdom": len(self.bundle.wisdom),
            "total_legacy": len(self.bundle.legacy),
        }


    def _build_default_atlas(self) -> MemoryAtlas:
        """Initializes categorical routing tree for the Totem memory atlas."""
        categories = [
            MemoryCategory(
                id="arch",
                name="Architecture & Systems",
                description="Structural invariants, module boundaries, dataflow patterns, and contracts",
                keywords=["architecture", "module", "refactor", "api", "database", "types"],
                subcategories=["dataflow", "contracts", "scalability"],
                icon="LuLayers",
            ),
            MemoryCategory(
                id="ops",
                name="Operations & Execution",
                description="CLI workflows, build pipelines, testing suites, and runtime health",
                keywords=["cli", "terminal", "build", "vite", "docker", "deploy", "logs"],
                subcategories=["sandbox", "tooling", "telemetry"],
                icon="LuTerminal",
            ),
            MemoryCategory(
                id="heuristics",
                name="Cognitive Heuristics & User Preferences",
                description="User interaction patterns, aesthetic standards, and domain heuristics",
                keywords=["preference", "style", "ui", "tone", "invariants", "rules"],
                subcategories=["design", "ergonomics", "safety"],
                icon="LuSparkles",
            ),
            MemoryCategory(
                id="domain",
                name="Domain Knowledge & Research",
                description="Specialized domain facts, biological/computational algorithms, and literature",
                keywords=["algorithm", "research", "math", "model", "inference", "memory"],
                subcategories=["cognition", "ml", "protocols"],
                icon="LuBrain",
            ),
        ]
        return MemoryAtlas(categories=categories)

    # ── Phase 1: Facts Logging ────────────────────────────────────────────────
    def record_fact(
        self,
        content: str,
        domain: str = "general",
        source_event: str = "observation",
        tags: Optional[List[str]] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Fact:
        """Records a concrete, verifiable operational fact or ground truth."""
        fact = Fact(
            content=content.strip(),
            domain=domain,
            source_event=source_event,
            tags=tags or [],
            metadata=metadata or {},
        )
        self.bundle.facts.append(fact)
        self._invalidate_cache()
        return fact

    # ── Phase 2: Working Knowledge Recording ──────────────────────────────────
    def record_working_knowledge(
        self,
        title: str,
        semantic_summary: str,
        origin_seed: str = "",
        journey_trace: Optional[List[str]] = None,
        associated_fact_ids: Optional[List[str]] = None,
        domain: str = "general",
        tags: Optional[List[str]] = None,
    ) -> WorkingKnowledge:
        """
        Records an active working knowledge debrief with its complete relational provenance.
        """
        provenance = RelationalProvenance(
            origin_seed=origin_seed,
            journey_trace=journey_trace or [],
        )
        wk = WorkingKnowledge(
            title=title.strip(),
            semantic_summary=semantic_summary.strip(),
            domain=domain,
            relational_chain=provenance,
            associated_fact_ids=associated_fact_ids or [],
            tags=tags or [],
        )
        self.bundle.working_knowledge.append(wk)
        self._invalidate_cache()
        return wk

    def reinforce_knowledge(self, knowledge_id: str, conversation_id: Optional[str] = None) -> bool:
        """Applies Hebbian reinforcement and updates the trajectory trace."""
        for wk in self.bundle.working_knowledge:
            if wk.id == knowledge_id:
                self.biodynamics.reinforce(wk, conversation_id)
                self._invalidate_cache()
                return True
        return False

    # ── Phase 3 & 4: Distillation & Legacy Consolidation ─────────────────────
    def distill(
        self,
        synthesizer_fn: Optional[Callable[[List[WorkingKnowledge]], str]] = None,
    ) -> Dict[str, Any]:
        """
        Consolidates working knowledge into aphoristic Wisdom principles
        and enshrines enduring truths into the Totem's Legacy compendium.
        """
        crystallized_count = 0
        new_wisdom_list: List[WisdomAphorism] = []

        for wk in self.bundle.working_knowledge:
            ready, reason = self.biodynamics.evaluate_crystallization_readiness(wk)
            if not ready:
                continue

            # Check if this knowledge is already crystallized into wisdom
            existing = any(wk.id in w.source_knowledge_ids for w in self.bundle.wisdom)
            if existing:
                continue

            # Synthesize aphoristic declaration
            if synthesizer_fn:
                declaration = synthesizer_fn([wk])
            else:
                declaration = f"Invariant: {wk.title.rstrip('.')}. {wk.semantic_summary[:120].strip()}"

            relevant_convs = [
                t.replace("conv:", "")
                for t in wk.relational_chain.journey_trace
                if t.startswith("conv:")
            ]

            wisdom = WisdomAphorism(
                declaration=declaration,
                rationale=f"Distilled from repeated application across {len(relevant_convs)} sessions: {wk.semantic_summary}",
                domain=wk.domain,
                source_knowledge_ids=[wk.id],
                relevant_conversations=relevant_convs,
                tags=wk.tags,
            )
            self.bundle.wisdom.append(wisdom)
            new_wisdom_list.append(wisdom)
            crystallized_count += 1

            # Check for legacy enshrinement (high confidence, multi-session invariants)
            if len(relevant_convs) >= 3 and wisdom.confidence >= 0.90:
                if not any(l.origin_aphorism_id == wisdom.id for l in self.bundle.legacy):
                    legacy_entry = LegacyDeclaration(
                        principle=wisdom.declaration,
                        domain=wisdom.domain,
                        origin_aphorism_id=wisdom.id,
                    )
                    self.bundle.legacy.append(legacy_entry)

        self.bundle.last_distilled_at = time.time()
        self._invalidate_cache()
        return {
            "crystallized_count": crystallized_count,
            "new_wisdom": [w.to_dict() for w in new_wisdom_list],
            "total_wisdom": len(self.bundle.wisdom),
            "total_legacy": len(self.bundle.legacy),
        }

    # ── Context Injection & Synthesis ─────────────────────────────────────────
    def synthesize_prompt_context(
        self, query: str = "", max_working_knowledge: int = 3, max_facts: int = 5
    ) -> str:
        """
        Synthesizes a dense, multi-tiered context block formatted for LLM consumption with memoized caching.
        """
        cache_key = f"{query.strip().lower()}:{max_working_knowledge}:{max_facts}"
        if cache_key in self._context_cache:
            self._cache_hits += 1
            return self._context_cache[cache_key]

        self._cache_misses += 1
        sections = []

        # 1. Legacy Invariants
        if self.bundle.legacy:
            legacy_lines = [f"• {l.principle}" for l in self.bundle.legacy]
            sections.append("### 🏛️ Totem Legacy Invariants:\n" + "\n".join(legacy_lines))

        # 2. Distilled Wisdom Aphorisms
        if self.bundle.wisdom:
            wisdom_lines = [f"• {w.declaration} (Rationale: {w.rationale})" for w in self.bundle.wisdom[:5]]
            sections.append("### 📜 Distilled Wisdom & Directives:\n" + "\n".join(wisdom_lines))

        # 3. Active Working Knowledge (Ranked by Salience)
        if self.bundle.working_knowledge:
            ranked_wk = sorted(
                self.bundle.working_knowledge,
                key=lambda w: self.biodynamics.compute_salience(w),
                reverse=True,
            )[:max_working_knowledge]

            wk_blocks = []
            for w in ranked_wk:
                trace_str = " -> ".join(w.relational_chain.journey_trace[-3:]) if w.relational_chain.journey_trace else "Direct"
                wk_blocks.append(
                    f"**[{w.title}]** (Domain: {w.domain}, Trace: {trace_str})\n"
                    f"{w.semantic_summary}"
                )
            sections.append("### 🧠 Active Working Knowledge & Relational Context:\n" + "\n\n".join(wk_blocks))

        # 4. Recent Verified Facts
        if self.bundle.facts:
            recent_facts = [f"• [{f.domain}] {f.content}" for f in self.bundle.facts[-max_facts:]]
            sections.append("### 📌 Verified Ground Truth Facts:\n" + "\n".join(recent_facts))

        result = "\n\n".join(sections)
        self._context_cache[cache_key] = result
        return result


    # ── Serialization ─────────────────────────────────────────────────────────
    def to_json(self, filepath: Optional[str] = None) -> str:
        data = self.bundle.to_dict()
        json_str = json.dumps(data, indent=2)
        if filepath:
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(json_str)
        return json_str

    @classmethod
    def from_json(cls, json_str_or_path: str) -> "TotemMemoryEngine":
        if os.path.exists(json_str_or_path):
            with open(json_str_or_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        else:
            data = json.loads(json_str_or_path)
        bundle = TotemMemoryBundle.from_dict(data)
        return cls(bundle=bundle)
