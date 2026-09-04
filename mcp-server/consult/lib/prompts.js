export const PROMPTS = [
  {
    id: 'kickoff_context_primer',
    title: 'Kickoff — prime the auditor with project context',
    purpose: 'First message in a fresh thread so every later consult inherits stable context.',
    fills: ['YOUR_ROLE', 'PROJECT_NAME', 'ONE_LINE_DESCRIPTION', 'STACK', 'BRIEF'],
    text: `I am {{YOUR_ROLE}} working on {{PROJECT_NAME}}, {{ONE_LINE_DESCRIPTION}}. Stack: {{STACK}}. You are my external auditor for this entire conversation; hold this context for all follow-ups without asking again. I will paste code, specs, and designs and request audits using structured prompts. Acknowledge in one sentence and wait for the first artifact. Project brief: {{BRIEF}}`,
  },
  {
    id: 'code_audit_deep',
    title: 'Deep code audit across five axes',
    purpose: 'Comprehensive hostile-but-fair code review with severity tags and ranked fixes.',
    fills: ['PROJECT_NAME', 'CODE'],
    text: `Act as a principal software engineer performing a hostile but fair audit of source from my project {{PROJECT_NAME}}. Audit along five axes, in order: (1) correctness — logic errors, unhandled edge cases, race conditions, error-path failures; (2) security — injection, broken authn/authz, secret leakage, unsafe deserialization, supply-chain risk; (3) performance — algorithmic complexity, N+1 patterns, memory growth, blocking IO on hot paths; (4) interface design — API shape, naming, type safety, contract clarity; (5) maintainability — dead code, duplication, hidden coupling, test gaps. Hard rules: cite every finding as FILE:LINE or function name when lines are unavailable; tag severity P0 ship-blocker, P1 fix soon, P2 should fix, P3 nit; give a concrete fix for every finding; when context is missing state exactly what you need instead of guessing; do not praise the code. End with a table titled TOP FIXES ranked by impact over effort, ten rows maximum. Code: {{CODE}}`,
  },
  {
    id: 'security_audit',
    title: 'OWASP-driven security audit',
    purpose: 'Security-only pass with exploit sketches and remediation order.',
    fills: ['PROJECT_NAME', 'CODE'],
    text: `Perform a security-focused audit of the following code from {{PROJECT_NAME}}. Walk OWASP Top 10 explicitly; for each category output either a finding with FILE:LINE evidence plus an exploit scenario, or "no finding". Then cover: authentication and session handling, authorization on every privileged path, input validation boundaries, secrets management, dangerous dependencies, data at rest and in transit. For each finding give severity critical/high/medium/low, a proof-of-concept sketch, and the minimal remediation. Close with a prioritized remediation order assuming an attacker has network access to the deployed app. Red flags you cannot prove must be labeled as hypotheses needing evidence. Code: {{CODE}}`,
  },
  {
    id: 'architecture_review',
    title: 'Architecture and boundaries review',
    purpose: 'Structural assessment with migration paths for the biggest risks.',
    fills: ['PROJECT_NAME', 'ARCHITECTURE_DESCRIPTION'],
    text: `Review the architecture described below for {{PROJECT_NAME}}. Assess: module boundaries and coupling, data flow coherence, state ownership, failure isolation, scaling ceilings, deployment fit. Name the single biggest structural risk and three secondary risks. For each risk state why it will hurt, its trigger conditions, and an incremental migration path that ships in safe steps. Prefer ASCII box-and-arrow diagrams over prose where structure matters. Be direct about tradeoffs and avoid generic advice. Context: {{ARCHITECTURE_DESCRIPTION}}`,
  },
  {
    id: 'ui_design_critique',
    title: 'UI/UX design critique',
    purpose: 'Design audit producing implementable corrections, not vibes.',
    fills: ['PROJECT_NAME', 'UI_DESCRIPTION'],
    text: `You are a senior product designer critiquing the following interface for {{PROJECT_NAME}}. Evaluate: visual hierarchy, layout rhythm and spacing consistency, typographic scale, color and contrast — name specific WCAG AA failures with ratios, interaction affordances, empty/error/loading states, motion, accessibility including focus order, labels, and target sizes. For each issue state what a user experiences, why it fails, and a corrected treatment with concrete values. Then propose one improved layout described precisely enough to implement without follow-up questions. Interface description or markup: {{UI_DESCRIPTION}}`,
  },
  {
    id: 'bug_triage',
    title: 'Symptom-driven bug triage',
    purpose: 'Ranked root-cause hypotheses with cheap discriminating tests.',
    fills: ['PROJECT_NAME', 'SYMPTOM', 'EXPECTED', 'EVIDENCE'],
    text: `I have a bug in {{PROJECT_NAME}}. Symptom: {{SYMPTOM}}. Expected behavior: {{EXPECTED}}. Relevant code and logs: {{EVIDENCE}}. Produce: (1) the five most probable root causes ranked by likelihood, each with the precise mechanism that produces the symptom; (2) the cheapest discriminating test, breakpoint, or log line for each hypothesis that would confirm or kill it; (3) the fix for your leading candidate. If the evidence is insufficient say so and list exactly what to capture next.`,
  },
  {
    id: 'performance_review',
    title: 'Performance audit',
    purpose: 'Complexity traps, redundant work, and ranked optimizations.',
    fills: ['PROJECT_NAME', 'CODE'],
    text: `Audit the following code from {{PROJECT_NAME}} for performance. Find: hot-path complexity traps — state the complexity class, redundant work such as recomputation, repeated IO, and N+1 patterns, allocation churn, lock contention risks, startup-cost contributors. Quantify expected impact where possible, e.g. O(n squared) scan at n near 10k is roughly 100M operations per request. For each finding give the optimization, expected gain, and the risk of behavior change. Rank by throughput-or-latency win per unit of risk. Code: {{CODE}}`,
  },
  {
    id: 'refactor_blueprint',
    title: 'Safe incremental refactor plan',
    purpose: 'Stepwise refactor sequence where no step leaves the system broken.',
    fills: ['PROJECT_NAME', 'PAIN_POINTS', 'OVERVIEW'],
    text: `Design a safe incremental refactor plan for {{PROJECT_NAME}}. Current pain points: {{PAIN_POINTS}}. Code and module overview: {{OVERVIEW}}. Output a numbered sequence of small independently shippable steps; every step states: scope touched, invariant preserved, test that proves safety, rollback strategy, estimated touch count in files and lines. No step may leave the system half-working. Finish with a definition of done and the signals that would tell us to stop and reconsider.`,
  },
  {
    id: 'spec_polish',
    title: 'Specification perfecting',
    purpose: 'Turns ambiguous specs into testable requirements.',
    fills: ['PROJECT_NAME', 'DOCUMENT'],
    text: `Perfect the following specification or design document for {{PROJECT_NAME}}. Hunt for: ambiguity a competent engineer could interpret two ways, unstated assumptions, missing failure modes and edge cases, undefined success metrics, scope creep, contradictions between sections. Rewrite ambiguous statements as testable requirements using given/when/then where useful. Return three sections: (1) findings list quoting the offending passage, (2) rewritten passages, (3) open questions ordered by how much they block implementation. Document: {{DOCUMENT}}`,
  },
  {
    id: 'verify_findings',
    title: 'Adversarial cross-model verification',
    purpose: 'Feed one model\u2019s findings to the other to confirm, refute, or extend them.',
    fills: ['PROJECT_NAME', 'FINDINGS'],
    text: `Adversarial verification task. Another AI auditor produced the findings below about {{PROJECT_NAME}}. Attack them: mark each CONFIRMED when you can reconstruct the failure mechanism, REFUTED when you can explain precisely why it cannot occur as claimed, or UNVERIFIABLE with the missing evidence named. Do not soften refutations. Flag anything resembling hallucination: wrong APIs, impossible line references, invented vulnerabilities. Then add any material finding the first auditor missed. Findings under verification: {{FINDINGS}}`,
  },
  {
    id: 'synthesis_merge',
    title: 'Merge two audits into one plan',
    purpose: 'Deduplicates and adjudicates two models\u2019 outputs into a single work plan.',
    fills: ['PROJECT_NAME', 'AUDIT_A', 'AUDIT_B'],
    text: `Two independent audits of {{PROJECT_NAME}} appear below. Merge them into one authoritative remediation plan: deduplicate overlapping findings and note agreement since cross-model agreement raises confidence; resolve contradictions by reasoning from the evidence given; re-score severity using combined signal; produce one final ranked work plan with S/M/L effort estimates. Mark every item where the auditors disagreed and explain your adjudication in one line. Audit A: {{AUDIT_A}} ---- Audit B: {{AUDIT_B}}`,
  },
  {
    id: 'release_signoff',
    title: 'Release-readiness gate',
    purpose: 'PASS/FAIL/CONDITIONAL gate check before shipping.',
    fills: ['PROJECT_NAME', 'VERSION', 'RELEASE_SUMMARY'],
    text: `Release-readiness gate for {{PROJECT_NAME}} v{{VERSION}}. From the summary below answer strictly PASS, FAIL, or CONDITIONAL for each gate: functionality complete against spec, known P0/P1 bugs, security review status, performance budgets met, rollback plan exists, observability in place, docs current. Every FAIL cites the specific gap and its owner-actionable fix. Close with the exact sentence you would place in the signoff record, or the shortest list of blockers standing between us and it. Summary: {{RELEASE_SUMMARY}}`,
  },
  {
    id: 'kimi_design_system_review',
    title: 'Kimi UI/UX design and aesthetic system review',
    purpose: 'Deep design critique analyzing spatial rhythm, typography, color harmony, and component styling.',
    fills: ['PROJECT_NAME', 'DESIGN_TOKENS_OR_VIEW', 'TARGET_PLATFORM'],
    text: `You are the lead product designer at Kimi performing an elite aesthetic and functional UI/UX review of {{PROJECT_NAME}} for {{TARGET_PLATFORM}}. Analyze: (1) Component harmony and visual hierarchy; (2) Typography scales, line heights, and legibility; (3) Color tokens, dark mode elevation, contrast, and glassmorphism/materials; (4) Micro-interactions, states (hover/active/disabled/focused), and animation physics; (5) Layout rhythm, padding consistency, and responsive scaling. Deliver concrete token fixes, CSS/SwiftUI code snippets, and a revised component blueprint. Artifact: {{DESIGN_TOKENS_OR_VIEW}}`,
  },
];

export function listPrompts() {
  return PROMPTS.map(({ id, title, purpose, fills }) => ({ id, title, purpose, fill_with: fills }));
}

export function getPrompt(id) {
  const p = PROMPTS.find((t) => t.id === id);
  if (!p) throw new Error(`unknown template_id "${id}". available: ${PROMPTS.map((t) => t.id).join(', ')}`);
  return p;
}
