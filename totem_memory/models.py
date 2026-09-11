"""
Data structures for the Multi-Tiered Cognitive Memory Engine.
Phases: Atlas -> Facts -> Working Knowledge -> Wisdom -> Legacy []
"""

from dataclasses import dataclass, field, asdict
from typing import List, Dict, Any, Optional
import time
import uuid


@dataclass
class Fact:
    """Layer 1: Discrete record of verifiable ground truth or operational event."""
    id: str = field(default_factory=lambda: f"fact-{uuid.uuid4().hex[:8]}")
    content: str = ""
    domain: str = "general"
    source_event: str = "observation"
    veracity: float = 1.0  # Confidence score 0.0 - 1.0
    created_at: float = field(default_factory=time.time)
    tags: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Fact":
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


@dataclass
class RelationalProvenance:
    """Causal & relational journey tracing how a knowledge element was seeded and evolved."""
    origin_seed: str = ""  # Initial user prompt, invariant requirement, or hypothesis
    journey_trace: List[str] = field(default_factory=list)  # Turn markers, decisions, tool executions
    causal_links: List[Dict[str, str]] = field(default_factory=list)  # [{'from': 'step_1', 'to': 'step_2', 'relation': 'caused'}]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class WorkingKnowledge:
    """
    Layer 2: Active living context. Cached semantic debriefings formed when facts are used,
    retaining the full relational chain that seeded the process.
    """
    id: str = field(default_factory=lambda: f"know-{uuid.uuid4().hex[:8]}")
    title: str = ""
    semantic_summary: str = ""
    domain: str = "general"
    relational_chain: RelationalProvenance = field(default_factory=RelationalProvenance)
    associated_fact_ids: List[str] = field(default_factory=list)
    reinforcement_count: int = 1
    salience_score: float = 1.0
    created_at: float = field(default_factory=time.time)
    last_reinforced_at: float = field(default_factory=time.time)
    tags: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        return d

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "WorkingKnowledge":
        d = data.copy()
        if "relational_chain" in d and isinstance(d["relational_chain"], dict):
            d["relational_chain"] = RelationalProvenance(**d["relational_chain"])
        return cls(**{k: v for k, v in d.items() if k in cls.__dataclass_fields__})


@dataclass
class WisdomAphorism:
    """
    Layer 3: Overriding aphoristic principles distilled after repeated usage cycles,
    deliberated across all relevant conversations, and seeded directly into directives.
    """
    id: str = field(default_factory=lambda: f"wis-{uuid.uuid4().hex[:8]}")
    declaration: str = ""  # Compact aphoristic directive (e.g. "Preserve token boundaries before AST slicing")
    rationale: str = ""    # Empirical justification synthesized across conversations
    domain: str = "general"
    source_knowledge_ids: List[str] = field(default_factory=list)
    relevant_conversations: List[str] = field(default_factory=list)  # Conversation IDs/Titles
    crystallized_at: float = field(default_factory=time.time)
    confidence: float = 0.95
    tags: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "WisdomAphorism":
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


@dataclass
class LegacyDeclaration:
    """
    Layer 4: Immutable eternal lineage compendium forming the Totem's core soul and legacy.
    """
    id: str = field(default_factory=lambda: f"leg-{uuid.uuid4().hex[:8]}")
    principle: str = ""
    domain: str = "general"
    origin_aphorism_id: str = ""
    enshrined_at: float = field(default_factory=time.time)
    invariant: bool = True

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "LegacyDeclaration":
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


@dataclass
class MemoryCategory:
    """Navigation Guide branch node."""
    id: str = ""
    name: str = ""
    description: str = ""
    keywords: List[str] = field(default_factory=list)
    subcategories: List[str] = field(default_factory=list)
    icon: str = "LuFolder"

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class MemoryAtlas:
    """Navigation Guide / Atlas for routing agent recall queries."""
    version: str = "1.0.0"
    description: str = "Totem Cognitive Navigation Guide & Categorical Atlas"
    categories: List[MemoryCategory] = field(default_factory=list)
    updated_at: float = field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "version": self.version,
            "description": self.description,
            "categories": [c.to_dict() for c in self.categories],
            "updated_at": self.updated_at,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "MemoryAtlas":
        cats = [
            MemoryCategory(**c) if isinstance(c, dict) else c
            for c in data.get("categories", [])
        ]
        return cls(
            version=data.get("version", "1.0.0"),
            description=data.get("description", ""),
            categories=cats,
            updated_at=data.get("updated_at", time.time()),
        )


@dataclass
class TotemMemoryBundle:
    """Full serialized memory unit attached to a Totem archetype."""
    totem_id: str = ""
    totem_name: str = ""
    atlas: MemoryAtlas = field(default_factory=MemoryAtlas)
    facts: List[Fact] = field(default_factory=list)
    working_knowledge: List[WorkingKnowledge] = field(default_factory=list)
    wisdom: List[WisdomAphorism] = field(default_factory=list)
    legacy: List[LegacyDeclaration] = field(default_factory=list)
    last_distilled_at: float = field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "totem_id": self.totem_id,
            "totem_name": self.totem_name,
            "atlas": self.atlas.to_dict(),
            "facts": [f.to_dict() for f in self.facts],
            "working_knowledge": [w.to_dict() for w in self.working_knowledge],
            "wisdom": [w.to_dict() for w in self.wisdom],
            "legacy": [l.to_dict() for l in self.legacy],
            "last_distilled_at": self.last_distilled_at,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TotemMemoryBundle":
        atlas_data = data.get("atlas", {})
        atlas = MemoryAtlas.from_dict(atlas_data) if isinstance(atlas_data, dict) else MemoryAtlas()
        facts = [Fact.from_dict(f) if isinstance(f, dict) else f for f in data.get("facts", [])]
        wk = [WorkingKnowledge.from_dict(w) if isinstance(w, dict) else w for w in data.get("working_knowledge", [])]
        wis = [WisdomAphorism.from_dict(w) if isinstance(w, dict) else w for w in data.get("wisdom", [])]
        leg = [LegacyDeclaration.from_dict(l) if isinstance(l, dict) else l for l in data.get("legacy", [])]
        return cls(
            totem_id=data.get("totem_id", ""),
            totem_name=data.get("totem_name", ""),
            atlas=atlas,
            facts=facts,
            working_knowledge=wk,
            wisdom=wis,
            legacy=leg,
            last_distilled_at=data.get("last_distilled_at", time.time()),
        )
