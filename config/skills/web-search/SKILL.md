---
name: web-search
description: Search the web using the local SearXNG instance (searxng:8888). Use when you need to look up current information, documentation, or any web content that isn't in your training data.
---

# Web Search (SearXNG)

Local SearXNG metasearch engine at `http://searxng:8888`. Privacy-respecting, aggregates results from multiple engines.

## Search API

```bash
curl -s "http://searxng:8888/search?q=<query>&format=json"
```

### Parameters

| Param | Values | Description |
|---|---|---|
| `q` | URL-encoded string | Search query (required) |
| `format` | `json`, `html` | Response format. Always use `json` |
| `categories` | comma-separated list | Filter by category |
| `pageno` | 1, 2, 3... | Results page number |
| `time_range` | `day`, `week`, `month`, `year` | Filter by recency |
| `language` | `en`, `nl`, etc. | Language filter |

### Categories

Available: `general`, `news`, `videos`, `images`, `music`, `packages`, `it`, `files`, `books`, `science`, `software wikis`, `repos`, `dictionaries`, `shopping`, `social media`, `movies`, `translate`, `radio`, `q&a`, `map`, `weather`, `currency`, `icons`.

Default (no categories specified): `general`.

### Examples

```bash
# Basic search
curl -s "http://searxng:8888/search?q=nix+nix-shell+patterns&format=json&language=en"

# News search, recent week
curl -s "http://searxng:8888/search?q=openai&format=json&categories=news&time_range=week"

# Paginated
curl -s "http://searxng:8888/search?q=rust+async&format=json&pageno=2"

# Shopping
curl -s "http://searxng:8888/search?q=thinkpad+x1&format=json&categories=shopping"
```

## Response Structure

Each result in the `results` array has:

```json
{
  "url": "https://...",
  "title": "Page title",
  "content": "Snippet text",
  "engine": "google, duckduckgo, wikipedia, etc.",
  "engines": ["google", "duckduckgo"],
  "score": 0.5,
  "category": "general",
  "publishedDate": "2025-01-01" // nullable
}
```

Also in the response:
- `number_of_results` — total count
- `suggestions` — Did you mean? suggestions
- `answers` — direct answer boxes
- `infoboxes` — info cards
- `unresponsive_engines` — engines that failed

## Reading Full Pages

To fetch and convert a web page to readable markdown:

```bash
curl -s "http://searxng:8888/search?q=<query>&format=json" | jq -r '.results[0].url' | xargs curl -sL
```

Or fetch via a readability proxy if available. For pages with heavy JS, prefer direct `curl` of the raw HTML and extract text.

## Best Practices

1. **Be specific** — `"nix-shell ephemeral packages"` beats `"nix"`
2. **Use language filter** when you want English-only results
3. **Check `unresponsive_engines`** — if a key engine is down, retry without it or widen the query
4. **Use time_range for recency** — `time_range=year` for recent info, omit for historical
5. **Prefer Wikipedia results** — they have structured content and high scores
6. **Paginate** — if the first page doesn't have what you need, try `pageno=2`
7. **Multiple categories** — for broad research, try `categories=general,news,science`

## Quick One-liner: Search + Top Result

```bash
curl -s "http://searxng:8888/search?q=<query>&format=json&language=en" | jq -r '.results[:3][] | "\(.title)\n\(.url)\n\(.content)\n---"'
```
