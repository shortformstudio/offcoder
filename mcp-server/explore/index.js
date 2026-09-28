#!/usr/bin/env node
// explore.mcp — model-augmented exploration of the web.
// Tools: explore_search, explore_read, explore_plan, explore_wander.
// Search via DuckDuckGo HTML, extraction in-process, optional local-model digests.

import { serve, textResult, errorResult } from '../lib/mcp-stdio.js';

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';
const MODEL_URL = process.env.EXPLORE_MODEL_URL ?? 'http://127.0.0.1:8000/v1/chat/completions';
const MODEL_NAME = process.env.EXPLORE_MODEL ?? 'qwythos/qwythos';
const MAX_FETCH_BYTES = 2_000_000;

// ---------- html utilities ----------

const ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', mdash: '—', ndash: '–',
  hellip: '…', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', copy: '©', reg: '®',
};

function decodeEntities(text) {
  return String(text)
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&([a-z]+);/gi, (match, name) => ENTITIES[name.toLowerCase()] ?? match);
}

function stripHtml(html) {
  return decodeEntities(
    String(html)
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ')
      .replace(/<nav[\s\S]*?<\/nav>/gi, ' ')
      .replace(/<header[\s\S]*?<\/header>/gi, ' ')
      .replace(/<footer[\s\S]*?<\/footer>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
  ).replace(/[ \t\r\f\v]+/g, ' ').replace(/\n\s*\n\s*\n+/g, '\n\n').trim();
}

function pageTitle(html) {
  const match = String(html).match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return match ? decodeEntities(match[1]).trim() : '';
}

function resolveUrl(href, base) {
  try {
    return new URL(href, base).toString();
  } catch {
    return href;
  }
}

function unwrapDuckDuckGo(href) {
  try {
    const url = new URL(href, 'https://duckduckgo.com');
    const target = url.searchParams.get('uddg');
    return target ? decodeURIComponent(target) : href;
  } catch {
    return href;
  }
}

// ---------- fetch ----------

async function fetchText(url, { timeout = 20000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(url, {
      redirect: 'follow',
      signal: controller.signal,
      headers: { 'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9' },
    });
    const reader = response.body?.getReader();
    if (!reader) return { status: response.status, url: response.url, text: await response.text() };
    const chunks = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      chunks.push(value);
      if (total > MAX_FETCH_BYTES) break;
    }
    const merged = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) { merged.set(chunk, offset); offset += chunk.byteLength; }
    return { status: response.status, url: response.url, text: new TextDecoder('utf-8').decode(merged) };
  } finally {
    clearTimeout(timer);
  }
}

// ---------- search ----------

function parseDuckDuckGo(html) {
  const results = [];
  const linkRe = /<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  const snippetRe = /<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
  const snippets = [];
  let match;
  while ((match = snippetRe.exec(html)) !== null) snippets.push(stripHtml(match[1]));
  let index = 0;
  while ((match = linkRe.exec(html)) !== null) {
    const url = unwrapDuckDuckGo(match[1]);
    if (url.startsWith('https://duckduckgo.com')) continue;
    results.push({ title: stripHtml(match[2]), url, snippet: snippets[index] ?? '' });
    index++;
  }
  if (results.length) return results;

  // lite.duckduckgo.com fallback shape
  const liteRe = /<a[^>]+class="result-link"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  while ((match = liteRe.exec(html)) !== null) {
    results.push({ title: stripHtml(match[2]), url: unwrapDuckDuckGo(match[1]), snippet: '' });
  }
  return results;
}

function unwrapBing(href) {
  try {
    const url = new URL(href, 'https://www.bing.com');
    const encoded = url.searchParams.get('u');
    if (encoded && encoded.startsWith('a1')) {
      const base64 = encoded.slice(2).replace(/-/g, '+').replace(/_/g, '/');
      const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
      return Buffer.from(padded, 'base64').toString('utf-8');
    }
    return href;
  } catch {
    return href;
  }
}

function parseBing(html) {
  const results = [];
  const blockRe = /<li class="b_algo"[\s\S]*?<\/li>/gi;
  let block;
  while ((block = blockRe.exec(html)) !== null) {
    const link = block[0].match(/<h2[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (!link) continue;
    const url = unwrapBing(link[1]);
    if (url.includes('bing.com/ck/a')) continue;
    const snippet = block[0].match(/<p[^>]*>([\s\S]*?)<\/p>/i);
    results.push({ title: stripHtml(link[2]), url, snippet: snippet ? stripHtml(snippet[1]) : '' });
  }
  return results;
}

async function searchWikipedia(query, limit) {
  const url = `https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=${limit}&srsearch=${encodeURIComponent(query)}`;
  const response = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!response.ok) return [];
  const data = await response.json();
  return (data?.query?.search ?? []).map((entry) => ({
    title: entry.title,
    url: `https://en.wikipedia.org/wiki/${encodeURIComponent(entry.title.replaceAll(' ', '_'))}`,
    snippet: stripHtml(entry.snippet ?? ''),
  }));
}

async function search(query, limit = 6) {
  const attempts = [
    async () => parseBing(await (await fetch(`https://www.bing.com/search?q=${encodeURIComponent(query)}`, {
      headers: { 'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9' },
    })).text()),
    async () => parseDuckDuckGo(await (await fetch('https://html.duckduckgo.com/html/', {
      method: 'POST',
      headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded', 'Accept-Language': 'en-US,en;q=0.9' },
      body: new URLSearchParams({ q: query, kl: 'us-en' }),
    })).text()),
    async () => searchWikipedia(query, limit),
  ];
  let lastError = null;
  for (const attempt of attempts) {
    try {
      const results = await attempt();
      if (results.length) return results.slice(0, limit);
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError) throw new Error(`search failed: ${lastError.message}`);
  return [];
}

// ---------- model digest ----------

async function digest(text, instruction) {
  const payload = {
    model: MODEL_NAME,
    messages: [
      { role: 'system', content: 'You compress web research into dense, factual digests. No preamble.' },
      { role: 'user', content: `${instruction}\n\n---\n${text.slice(0, 12000)}` },
    ],
    stream: false,
    temperature: 0.2,
  };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 90000);
  try {
    const response = await fetch(MODEL_URL, {
      method: 'POST',
      signal: controller.signal,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!response.ok) throw new Error(`model status ${response.status}`);
    const data = await response.json();
    return data?.choices?.[0]?.message?.content?.trim() ?? '';
  } finally {
    clearTimeout(timer);
  }
}

// ---------- tools ----------

const tools = [
  {
    name: 'explore_search',
    summary: 'Web Search Engine: Retrieves ranked web results with snippets',
    description: 'Search the open web using multiple resilient backends (Bing, DuckDuckGo, Wikipedia). Returns ranked search results containing page titles, canonical URLs, and descriptive text snippets. Use this tool when researching external technical documentation, package versions, APIs, or debugging errors.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['query'],
      properties: {
        query: {
          type: 'string',
          description: 'Search query string. Be specific with keywords, version numbers, and framework names.',
        },
        limit: {
          type: 'integer',
          minimum: 1,
          maximum: 12,
          default: 6,
          description: 'Maximum number of ranked results to return (between 1 and 12).',
        },
      },
    },
  },
  {
    name: 'explore_read',
    summary: 'Web Page Reader: Fetches and extracts clean readable page text',
    description: 'Fetch any publicly accessible web page and return clean, readable text with scripts, styling, navbars, and headers stripped out. Use this after finding candidate URLs via explore_search to read full documentation, articles, or source code.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['url'],
      properties: {
        url: {
          type: 'string',
          description: 'Full HTTP or HTTPS URL of the page to read (e.g. https://docs.example.com/api).',
        },
        max_chars: {
          type: 'integer',
          minimum: 500,
          maximum: 40000,
          default: 12000,
          description: 'Maximum character count of extracted body text to return.',
        },
      },
    },
  },
  {
    name: 'explore_plan',
    summary: 'Autonomous Research Synthesizer: Researches a topic end-to-end',
    description: 'Conduct end-to-end research on a subject: automatically runs multi-angle searches, fetches and extracts top sources, and compiles a structured, cited markdown brief. Set summarize=true to activate local-model synthesis into concise takeaways.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['subject'],
      properties: {
        subject: {
          type: 'string',
          description: 'Primary research topic or technical question to investigate.',
        },
        queries: {
          type: 'array',
          items: { type: 'string' },
          description: 'Optional supplementary query variations to broaden coverage.',
        },
        pages: {
          type: 'integer',
          minimum: 1,
          maximum: 6,
          default: 3,
          description: 'Number of top search result pages to fetch and digest.',
        },
        summarize: {
          type: 'boolean',
          default: false,
          description: 'Whether to use the local model to generate structured digests and bulleted syntheses.',
        },
      },
    },
  },
  {
    name: 'explore_wander',
    summary: 'Domain Crawler: Explores internal links and maps page structure',
    description: 'Crawl outward from a seed URL within the same domain, extracting page titles, body excerpts, and internal links. Returns a structured map of the target site or documentation hierarchy.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['url'],
      properties: {
        url: {
          type: 'string',
          description: 'Starting seed URL (e.g. https://framework.org/docs).',
        },
        depth: {
          type: 'integer',
          minimum: 1,
          maximum: 2,
          default: 1,
          description: 'Link crawl depth from starting URL.',
        },
        max_pages: {
          type: 'integer',
          minimum: 2,
          maximum: 12,
          default: 6,
          description: 'Maximum total pages to visit and index.',
        },
      },
    },
  },
];

const handlers = {
  async explore_search(args) {
    if (!args.query || !args.query.trim()) {
      return errorResult({
        code: 'EMPTY_QUERY',
        message: 'Search query cannot be empty or whitespace only.',
        remediation: 'Provide a meaningful technical query string.',
      }, 'explore_search');
    }
    const results = await search(args.query.trim(), args.limit ?? 6);
    return textResult(JSON.stringify({ ok: true, query: args.query, count: results.length, results }, null, 2));
  },

  async explore_read(args) {
    try {
      new URL(args.url);
    } catch {
      return errorResult({
        code: 'INVALID_URL',
        message: `Invalid URL format: "${args.url}"`,
        remediation: 'Provide a valid URL starting with http:// or https://',
      }, 'explore_read');
    }
    try {
      const { status, url, text } = await fetchText(args.url);
      const title = pageTitle(text);
      const body = stripHtml(text);
      const max = args.max_chars ?? 12000;
      return textResult(JSON.stringify({
        ok: status >= 200 && status < 400,
        status,
        url,
        title,
        chars: body.length,
        text: body.slice(0, max),
      }, null, 2));
    } catch (err) {
      return errorResult({
        code: 'NETWORK_FETCH_ERROR',
        message: `Failed to fetch page: ${err.message}`,
        remediation: 'Verify that the server is online and accessible, and check for network timeouts.',
      }, 'explore_read');
    }
  },

  async explore_plan(args) {
    const queries = [args.subject, ...(args.queries ?? [])];
    const seen = new Set();
    const sources = [];
    for (const query of queries) {
      let results = [];
      try {
        results = await search(query, 5);
      } catch (error) {
        results = [];
      }
      for (const result of results) {
        if (seen.has(result.url) || sources.length >= (args.pages ?? 3) * 2) continue;
        seen.add(result.url);
        sources.push(result);
      }
    }

    const brief = [];
    const read = [];
    for (const source of sources.slice(0, args.pages ?? 3)) {
      try {
        const { text } = await fetchText(source.url);
        const body = stripHtml(text);
        read.push({ ...source, excerpt: body.slice(0, 6000) });
      } catch (error) {
        read.push({ ...source, excerpt: '', error: error.message });
      }
    }

    brief.push(`# research brief — ${args.subject}`);
    brief.push(`queries: ${queries.join(' · ')}`);
    brief.push(`sources read: ${read.filter((r) => r.excerpt).length}/${read.length}`);
    for (const source of read) {
      brief.push(`\n## ${source.title || source.url}\n${source.url}`);
      if (source.excerpt) {
        if (args.summarize) {
          try {
            const summary = await digest(source.excerpt, 'Digest this source into 4-6 dense bullets. Keep concrete facts, numbers, and names.');
            brief.push(summary || source.excerpt.slice(0, 1200));
          } catch {
            brief.push(source.excerpt.slice(0, 1200));
          }
        } else {
          brief.push(source.excerpt.slice(0, 1200));
        }
      } else if (source.error) {
        brief.push(`(unreadable: ${source.error})`);
      }
    }

    if (args.summarize && read.some((r) => r.excerpt)) {
      const combined = read.map((r) => `SOURCE: ${r.title}\n${r.excerpt.slice(0, 2500)}`).join('\n\n');
      try {
        const synthesis = await digest(combined, `Synthesize a planning brief for "${args.subject}" from these sources: what is true, what is contested, what to do next. 8 bullets max.`);
        if (synthesis) brief.push(`\n## synthesis\n${synthesis}`);
      } catch {
        // synthesis is optional
      }
    }

    return textResult(brief.join('\n'));
  },

  async explore_wander(args) {
    const maxPages = args.max_pages ?? 6;
    const start = args.url;
    const { text } = await fetchText(start);
    const base = new URL(start);
    const visited = new Map();

    const links = [];
    const linkRe = /<a[^>]+href="([^"]+)"/gi;
    let match;
    while ((match = linkRe.exec(text)) !== null) {
      const url = resolveUrl(match[1], start);
      try {
        const parsed = new URL(url);
        if (parsed.hostname === base.hostname && !parsed.hash && !/\.(png|jpe?g|gif|svg|pdf|zip)$/i.test(parsed.pathname)) {
          if (!links.includes(url)) links.push(url);
        }
      } catch {
        // skip
      }
      if (links.length >= maxPages * 3) break;
    }

    visited.set(start, { title: pageTitle(text), excerpt: stripHtml(text).slice(0, 400) });
    for (const url of links.slice(0, maxPages - 1)) {
      try {
        const page = await fetchText(url);
        visited.set(url, { title: pageTitle(page.text), excerpt: stripHtml(page.text).slice(0, 400) });
      } catch (error) {
        visited.set(url, { title: '', excerpt: `(unreadable: ${error.message})` });
      }
    }

    const map = [...visited.entries()].map(([url, page]) => ({ url, title: page.title, excerpt: page.excerpt }));
    return textResult(JSON.stringify({ ok: true, origin: start, pages: map }, null, 2));
  },
};

serve({ name: 'explore', version: '1.0.0', tools, handlers });
