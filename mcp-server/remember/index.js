#!/usr/bin/env node
// remember.mcp — Totem Biodynamic Memory Graph Traversal & Retrieval
// Traverses semantically compressed memory graphs to supplement bounded local model context.
// Tools:
//   - remember: Query-directed memory graph traversal and subgraph extraction
//   - remember_assert: Commits an invariant ground truth fact to the active persona's graph
//   - remember_convo_log: Reads raw chronological conversation logs for archival audit

import { existsSync, readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { serve, textResult, errorResult } from '../lib/mcp-stdio.js';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

function resolveMemoryDir(totem) {
  if (totem) {
    const candidates = [
      path.resolve(REPO_ROOT, 'totem_memory', 'records', String(totem)),
      path.resolve(REPO_ROOT, `local records - ${totem}`),
      path.resolve(REPO_ROOT, 'totems', String(totem)),
      path.resolve(homedir(), '.offcoder', 'totems', String(totem)),
      path.resolve(String(totem))
    ];
    for (const c of candidates) {
      if (existsSync(c)) return c;
    }
  }

  if (process.env.OFFCODER_TOTEM_DIR && existsSync(process.env.OFFCODER_TOTEM_DIR)) {
    return process.env.OFFCODER_TOTEM_DIR;
  }

  const defaultDir = path.resolve(REPO_ROOT, 'local records - 8080');
  if (existsSync(defaultDir)) return defaultDir;

  return defaultDir;
}

function loadJsonSafe(filePath, fallback) {
  try {
    if (!existsSync(filePath)) return fallback;
    const content = readFileSync(filePath, 'utf-8').trim();
    if (!content) return fallback;
    return JSON.parse(content);
  } catch {
    return fallback;
  }
}

function loadJsonlSafe(filePath) {
  try {
    if (!existsSync(filePath)) return [];
    const content = readFileSync(filePath, 'utf-8');
    return content
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.length > 0)
      .map(line => {
        try { return JSON.parse(line); } catch { return null; }
      })
      .filter(Boolean);
  } catch {
    return [];
  }
}

function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9_\-\/.]+/g, ' ')
    .split(' ')
    .filter(t => t.length >= 2);
}

function computeOverlapScore(queryTokens, targetText, tags = []) {
  if (!targetText && (!tags || tags.length === 0)) return 0;
  const targetLower = String(targetText || '').toLowerCase();
  const tagList = Array.isArray(tags) ? tags.map(t => String(t).toLowerCase()) : [];
  
  let score = 0;
  for (const token of queryTokens) {
    if (tagList.includes(token)) score += 3.0;
    if (targetLower.includes(token)) score += 1.0;
  }
  return score;
}

const tools = [
  {
    name: 'remember',
    summary: 'Memory Graph Traversal: Retrieves semantically linked knowledge and invariant facts',
    description: 'Traverses the active Totem persona memory graph. Extracts salient working knowledge nodes, linked ground-truth facts, and relational edges matching a query or domain. Designed to fit within small local model context windows (500-1200 tokens).',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['query'],
      properties: {
        query: {
          type: 'string',
          description: 'Search query, topic, file path, concept, or question to recall from memory.',
        },
        domain: {
          type: 'string',
          enum: ['arch', 'ops', 'heuristics', 'domain', 'all'],
          default: 'all',
          description: 'Filter by architectural, operational, heuristic, or domain knowledge.',
        },
        depth: {
          type: 'integer',
          minimum: 1,
          maximum: 2,
          default: 1,
          description: 'Graph traversal depth (1 = direct matches & linked facts; 2 = second-order relations).',
        },
        max_facts: {
          type: 'integer',
          minimum: 1,
          maximum: 20,
          default: 8,
          description: 'Maximum number of atomic verified facts to return.',
        },
        max_knowledge: {
          type: 'integer',
          minimum: 1,
          maximum: 10,
          default: 3,
          description: 'Maximum number of working knowledge summaries to return.',
        },
        totem: {
          type: 'string',
          description: 'Optional totem identifier or folder name (e.g. "8080" or "qwythos"). Defaults to active totem.',
        },
      },
    },
  },
  {
    name: 'remember_assert',
    summary: 'Memory Fact Assertion: Commits an immutable ground-truth fact to the memory graph',
    description: 'Asserts a new ground-truth invariant fact into the active Totem memory graph (facts.jsonl and MEMORY.md). Call this when uncovering important architectural decisions, path maps, or user requirements.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['content'],
      properties: {
        content: {
          type: 'string',
          description: 'Invariant fact content (e.g. "PROJECT PATHNAME: src/api.py hosts the FastAPI router").',
        },
        domain: {
          type: 'string',
          enum: ['arch', 'ops', 'heuristics', 'domain'],
          default: 'arch',
          description: 'Knowledge category domain.',
        },
        tags: {
          type: 'array',
          items: { type: 'string' },
          description: 'Semantic tags for indexing and retrieval.',
        },
        totem: {
          type: 'string',
          description: 'Optional totem identifier.',
        },
      },
    },
  },
  {
    name: 'remember_convo_log',
    summary: 'Raw Conversation Auditor: Reads chronological uncompressed turn history',
    description: 'Retrieves raw unfiltered conversation history from raw_convo.jsonl for historical auditing or curiosity. (Use "remember" for semantic recall; use this only for exact turn replays).',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        limit: {
          type: 'integer',
          minimum: 1,
          maximum: 50,
          default: 10,
          description: 'Number of recent turns to retrieve.',
        },
        totem: {
          type: 'string',
          description: 'Optional totem identifier.',
        },
      },
    },
  },
];

const handlers = {
  remember: async (args) => {
    const memoryDir = resolveMemoryDir(args.totem);
    const biodynamicDir = path.join(memoryDir, 'biodynamic');
    const query = String(args.query || '').trim();
    if (!query) {
      return errorResult({ code: 'EMPTY_QUERY', message: 'Query cannot be empty.' }, 'remember');
    }

    const domainFilter = args.domain && args.domain !== 'all' ? args.domain : null;
    const maxFacts = args.max_facts || 8;
    const maxKnowledge = args.max_knowledge || 3;
    const queryTokens = tokenize(query);

    // 1. Load Knowledge Graph components
    const workingKnowledge = loadJsonSafe(path.join(biodynamicDir, 'working_knowledge.json'), []);
    const facts = loadJsonlSafe(path.join(biodynamicDir, 'facts.jsonl'));
    const edges = loadJsonSafe(path.join(biodynamicDir, 'graph_edges.json'), []);

    // 2. Score Working Knowledge Nodes
    const scoredKnowledge = workingKnowledge
      .filter(wk => !domainFilter || wk.domain === domainFilter)
      .map(wk => {
        const textToMatch = `${wk.title} ${wk.originSeed || ''} ${wk.semanticSummary}`;
        const overlap = computeOverlapScore(queryTokens, textToMatch, wk.tags);
        const salience = Number(wk.salienceScore) || 1.0;
        const totalScore = overlap * (1.0 + salience * 0.5);
        return { ...wk, score: totalScore };
      })
      .filter(wk => wk.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, maxKnowledge);

    // 3. Collect associated facts from top knowledge nodes
    const associatedFactIds = new Set();
    for (const wk of scoredKnowledge) {
      if (Array.isArray(wk.associatedFactIds)) {
        for (const fid of wk.associatedFactIds) associatedFactIds.add(fid);
      }
    }

    // 4. Score & Gather Facts
    const scoredFacts = facts
      .filter(f => !domainFilter || f.domain === domainFilter)
      .map(f => {
        let score = computeOverlapScore(queryTokens, f.content, f.tags);
        if (associatedFactIds.has(f.id)) score += 5.0; // Boost linked facts
        return { ...f, score };
      })
      .filter(f => f.score > 0 || associatedFactIds.has(f.id))
      .sort((a, b) => b.score - a.score)
      .slice(0, maxFacts);

    // 5. If depth = 2, traverse graph edges
    const relatedEdgeNotes = [];
    if (args.depth === 2 && Array.isArray(edges) && edges.length > 0) {
      const activeIds = new Set([
        ...scoredKnowledge.map(k => k.id),
        ...scoredFacts.map(f => f.id)
      ]);
      for (const edge of edges) {
        if (activeIds.has(edge.sourceId) || activeIds.has(edge.targetId)) {
          relatedEdgeNotes.push(`• Relational Link: [${edge.sourceId}] --(${edge.relationship || 'relates_to'})--> [${edge.targetId}]`);
          if (relatedEdgeNotes.length >= 4) break;
        }
      }
    }

    // 6. Format Compact, High-Density Markdown Subgraph
    const lines = [];
    lines.push(`### 🧠 Totem Memory Subgraph: "${query}"`);
    lines.push(`*Store: ${path.basename(memoryDir)} | Filter: ${domainFilter || 'all domains'} | Matched Nodes: ${scoredKnowledge.length} | Facts: ${scoredFacts.length}*`);
    lines.push('');

    if (scoredKnowledge.length > 0) {
      lines.push('**Distilled Working Knowledge:**');
      for (const wk of scoredKnowledge) {
        lines.push(`- **[${wk.title}]** (Domain: ${wk.domain}, Salience: ${(wk.salienceScore || 1.0).toFixed(2)})`);
        lines.push(`  ${wk.semanticSummary.trim()}`);
      }
      lines.push('');
    }

    if (scoredFacts.length > 0) {
      lines.push('**Verified Invariant Facts:**');
      for (const f of scoredFacts) {
        lines.push(`• [${(f.domain || 'arch').toUpperCase()}] ${f.content}`);
      }
      lines.push('');
    }

    if (relatedEdgeNotes.length > 0) {
      lines.push('**Relational Graph Edges:**');
      lines.push(...relatedEdgeNotes);
      lines.push('');
    }

    if (scoredKnowledge.length === 0 && scoredFacts.length === 0) {
      // Fallback: provide top 3 most salient general facts
      lines.push('*(No direct keyword match found in graph. Showing active baseline invariants:)*');
      const fallbackFacts = facts.slice(0, 4);
      for (const f of fallbackFacts) {
        lines.push(`• [${(f.domain || 'arch').toUpperCase()}] ${f.content}`);
      }
    }

    return textResult(lines.join('\n'));
  },

  remember_assert: async (args) => {
    const memoryDir = resolveMemoryDir(args.totem);
    const biodynamicDir = path.join(memoryDir, 'biodynamic');
    mkdirSync(biodynamicDir, { recursive: true });

    const content = String(args.content || '').trim();
    if (!content) {
      return errorResult({ code: 'EMPTY_CONTENT', message: 'Fact content cannot be empty.' }, 'remember_assert');
    }

    const domain = args.domain || 'arch';
    const tags = Array.isArray(args.tags) ? args.tags : [];
    const factId = `fact-${Date.now().toString(36)}-${Math.random().toString(36).substring(2, 6)}`;
    const newFact = {
      id: factId,
      domain,
      veracity: 1.0,
      timestamp: Date.now() / 1000,
      tags,
      content,
    };

    // Append to facts.jsonl
    const factsPath = path.join(biodynamicDir, 'facts.jsonl');
    const prefix = (existsSync(factsPath) && !readFileSync(factsPath, 'utf-8').endsWith('\n')) ? '\n' : '';
    appendFileSync(factsPath, prefix + JSON.stringify(newFact) + '\n', 'utf-8');

    // Also append to MEMORY.md for instant prompt visibility
    const memoryMdPath = path.join(memoryDir, 'MEMORY.md');
    try {
      const factLine = `• [${domain.toUpperCase()}] ${content}\n`;
      appendFileSync(memoryMdPath, factLine, 'utf-8');
    } catch {}

    return textResult(`✅ Asserted ground-truth fact into ${path.basename(memoryDir)}:\nID: ${factId}\nDomain: [${domain.toUpperCase()}]\nContent: "${content}"`);
  },

  remember_convo_log: async (args) => {
    const memoryDir = resolveMemoryDir(args.totem);
    const rawDir = path.join(memoryDir, 'raw');
    const limit = args.limit || 10;

    const convoPath = path.join(rawDir, 'raw_convo.jsonl');
    const txPath = path.join(rawDir, 'raw_transactions.jsonl');
    
    let entries = loadJsonlSafe(convoPath);
    if (entries.length === 0) {
      entries = loadJsonlSafe(txPath);
    }

    if (entries.length === 0) {
      return textResult(`(No raw conversation turns recorded yet in ${path.basename(memoryDir)}/raw)`);
    }

    const slice = entries.slice(-limit);
    const output = slice.map((entry, idx) => {
      const time = entry.timestamp ? new Date(entry.timestamp * 1000).toLocaleTimeString() : `#${idx + 1}`;
      const role = entry.role || (entry.requestPayload ? 'turn' : 'log');
      const text = entry.text || entry.responseContent || JSON.stringify(entry).slice(0, 150);
      return `[${time}] ${role.toUpperCase()}: ${text}`;
    }).join('\n\n');

    return textResult(`### 📜 Raw Conversation History (Last ${slice.length} turns in ${path.basename(memoryDir)}):\n\n${output}`);
  }
};

serve({ name: 'remember', version: '1.0.0', tools, handlers });
