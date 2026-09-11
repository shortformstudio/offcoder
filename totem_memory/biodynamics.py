"""
Biodynamic & Neuromorphic Memory Consolidation Functions.
Implements Synaptic Tagging & Capture (STC), Long-Term Potentiation (LTP),
Hebbian Reinforcement, and Multi-Session Crystallization Gates.
"""

import math
import time
from typing import List, Tuple
from .models import WorkingKnowledge, WisdomAphorism, LegacyDeclaration


class BiodynamicMemoryConsolidator:
    def __init__(
        self,
        half_life_seconds: float = 86400.0 * 7.0,  # 7-day half-life for active memory decay
        reinforcement_boost: float = 0.35,
        crystallization_min_reinforcements: int = 3,
        crystallization_min_conversations: int = 2,
    ):
        self.half_life_seconds = half_life_seconds
        self.decay_lambda = math.log(2) / max(1.0, half_life_seconds)
        self.reinforcement_boost = reinforcement_boost
        self.crystallization_min_reinforcements = crystallization_min_reinforcements
        self.crystallization_min_conversations = crystallization_min_conversations

    def compute_salience(self, knowledge: WorkingKnowledge, current_time: float = None) -> float:
        """
        Calculates synaptic salience using neuromorphic exponential decay
        tempered by logarithmic Hebbian reinforcement.
        """
        now = current_time or time.time()
        elapsed = max(0.0, now - knowledge.last_reinforced_at)
        decay_factor = math.exp(-self.decay_lambda * elapsed)

        # Logarithmic reinforcement scaling prevents runaway saturation
        reinforcement_multiplier = 1.0 + math.log1p(knowledge.reinforcement_count * self.reinforcement_boost)

        salience = knowledge.salience_score * decay_factor * reinforcement_multiplier
        return max(0.01, min(10.0, salience))

    def reinforce(self, knowledge: WorkingKnowledge, conversation_id: str = None) -> None:
        """
        Applies Long-Term Potentiation (LTP) to working knowledge entry upon usage.
        """
        knowledge.reinforcement_count += 1
        knowledge.last_reinforced_at = time.time()
        knowledge.salience_score = min(5.0, knowledge.salience_score + 0.25)

        if conversation_id:
            trace = knowledge.relational_chain.journey_trace
            if conversation_id not in trace:
                trace.append(f"conv:{conversation_id}")

    def evaluate_crystallization_readiness(
        self, knowledge: WorkingKnowledge
    ) -> Tuple[bool, str]:
        """
        Evaluates whether a piece of working knowledge has earned crystallization
        into an overarching Wisdom Aphorism.
        """
        if knowledge.reinforcement_count < self.crystallization_min_reinforcements:
            return (
                False,
                f"Needs {self.crystallization_min_reinforcements - knowledge.reinforcement_count} more reinforcements (current: {knowledge.reinforcement_count})",
            )

        conv_count = len(
            [t for t in knowledge.relational_chain.journey_trace if t.startswith("conv:")]
        )
        if conv_count < self.crystallization_min_conversations:
            return (
                False,
                f"Needs presence across at least {self.crystallization_min_conversations} distinct conversations (current: {conv_count})",
            )

        if not knowledge.semantic_summary or len(knowledge.semantic_summary.strip()) < 15:
            return False, "Semantic debriefing is insufficient for crystallization"

        return True, "Ready for Wisdom Crystallization"
