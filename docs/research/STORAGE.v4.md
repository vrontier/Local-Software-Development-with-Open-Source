# Storage-Index-Search System (SISS) — Design Specification v4

> **v1**: GPT-OSS-120B on Pegasus (2026-02-12) — initial design
> **v2**: Claude Opus 4.6 (2026-02-12) — corrected MCP, tiered architecture, Rust core
> **v3**: Qwen3-Coder-Next 80B on Max (2026-02-12) — added observability, operational concerns
> **v4**: Claude Opus 4.6 (2026-02-12) — synthesis: fixes v3 errors, fills fundamental gaps,
> restores v2 completeness, adds embedding model strategy and content chunking

---

## What Changed in v4

| Area | Previous State | v4 Change |
|------|---------------|-----------|
| **Embedding model** | All versions assumed chat models generate embeddings | Dedicated embedding model (`nomic-embed-text-v1.5`, 768-dim GGUF) |
| **Content chunking** | Not addressed in any version | Full chunking strategy for ASCII, JSON, XML |
| **MCP spec accuracy** | v3 fabricated "MCP 1.1" requirements | Corrected to actual MCP spec; good practices kept without false attribution |
| **NAS role** | v3 over-corrected to "ingest only" | NAS is source of truth at Tier 1 with graceful degradation |
| **Dual-hash** | v3 added BLAKE2b (unnecessary) | SHA-256 only, with periodic integrity verification |
| **LLM workers** | v3 proposed Ray/Celery (Python) | Tokio async tasks (Tier 1), NATS JetStream (Tier 2+) |
| **Embedding fallback** | v3 proposed all-MiniLM (dimension mismatch) | Single embedding model, consistent dimensions |
| **Observability** | Missing from v2, added in v3 | Kept from v3 with corrections |
| **Backup/maintenance** | Missing from v2, added in v3 | Kept from v3 |
| **File size handling** | Not addressed | Configurable limits, metadata-only indexing for oversized files |
| **LLM infrastructure** | Only Pegasus + Stella | Adds Max (Qwen3-Coder-Next 80B) for large-document summarization |
| **Content intelligence** | Basic tags and summaries | Entity extraction, cross-file relationships, synonym generation, anomaly detection |

---

## 1. Architecture

### 1.1 Tiered Deployment

```
TIER 1: MVP — Docker Compose (single host or Synology NAS)
├── SISS Core (Rust, single binary)
│   ├── REST API (:8080)
│   ├── MCP Server (stdio + SSE :3000)
│   ├── Ingestor (file watcher + scanner)
│   └── Parser (ASCII, JSON, XML)
├── Meilisearch (full-text search + facets)
├── PostgreSQL 17 + pgvector (metadata, schemas, embeddings)
├── Caddy (reverse proxy, auto-TLS)
├── NAS mount (source of truth, NFS/SMB)
└── LLMs (optional, network-accessible)
    ├── Stella  — Qwen3-8B at stella.home.arpa:8000
    ├── Pegasus — GPT-OSS-120B at pegasus.home.arpa:8000
    └── Max     — Qwen3-Coder-Next 80B at max.home.arpa:8080

TIER 2: Scale — K3s (2-5 nodes)
├── Adds: Redis, NATS JetStream, horizontal API replicas
├── Adds: MinIO as read-through cache for NAS files
├── Adds: Dedicated embedding model instance
└── NAS: still source of truth, served via MinIO cache

TIER 3: Production — K8s (5+ nodes)
├── Adds: OpenSearch (replaces Meilisearch), Keycloak, Istio
├── Adds: Patroni HA Postgres, MinIO erasure-coded
├── Adds: Prometheus + Grafana + Jaeger + Loki
└── MinIO: distributed serving layer
```

### 1.2 Tier 1 Architecture Detail

```
                        Clients
                 ┌────────┼────────┐
                 │        │        │
              Web UI   CLI/SDK   AI Agents
                 │        │        │
                 └────────┼────────┘
                          │
                    ┌─────┴──────┐
                    │   Caddy    │  :443 (HTTPS)
                    └─────┬──────┘
                          │
              ┌───────────┼───────────┐
              │                       │
     ┌────────┴────────┐    ┌────────┴────────┐
     │  REST API       │    │  MCP Server     │
     │  :8080          │    │  :3000 (SSE)    │
     │  (Axum/Rust)    │    │  stdio (local)  │
     └────────┬────────┘    └────────┬────────┘
              │                       │
              └───────────┬───────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
  ┌──────┴──────┐  ┌─────┴──────┐  ┌─────┴──────────┐
  │ PostgreSQL  │  │ Meilisearch│  │ NAS (NFS/SMB)  │
  │ :5432       │  │ :7700      │  │ /volume1/data  │
  │ metadata    │  │ full-text  │  │ SOURCE OF      │
  │ schemas     │  │ facets     │  │ TRUTH          │
  │ pgvector    │  │ filters    │  │                │
  └─────────────┘  └────────────┘  └────────────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
  ┌──────┴──────┐  ┌─────┴──────┐  ┌─────┴──────────┐
  │ Stella      │  │ Pegasus    │  │ Max            │
  │ Qwen3-8B   │  │ GPT-OSS-   │  │ Qwen3-Coder-  │
  │ + embedding │  │ 120B       │  │ Next 80B      │
  │ model       │  │ schema     │  │ large-doc     │
  │ (optional)  │  │ analysis   │  │ summarization │
  └─────────────┘  └────────────┘  └────────────────┘
```

**Key design principles:**

- **NAS is source of truth at Tier 1.** Files are not duplicated. The search index
  (Meilisearch + PostgreSQL) is local and always available. File downloads are streamed
  from NAS through the Rust API. If NAS goes down, search still works but downloads
  return 503 with `Retry-After`.
- **Single Rust binary.** API, MCP server, ingestor, and parser compiled together.
  No JVM, no Python, no GC pauses.
- **LLMs are optional and async.** Core indexing (parse, hash, store metadata, index
  in Meilisearch) works without any LLM. Embeddings and summaries are queued as
  background tasks.

---

## 2. Component Breakdown

### 2.1 Tier 1 (MVP)

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Core Service** | **Rust** (Axum, Tokio) | Single binary, ~12 MB, safe concurrency. Parsers: `serde_json`, `quick-xml`. |
| **Search Engine** | **Meilisearch** | Sub-50ms search, typo tolerance, faceted filtering, ~200 MB RAM for 1M docs. |
| **Metadata DB** | **PostgreSQL 17 + pgvector** | JSONB for metadata, GIN indexes, `pg_trgm` for fuzzy matching, pgvector for embeddings. WAL archiving enabled. |
| **Reverse Proxy** | **Caddy** | Auto-TLS, reverse proxy, rate limiting. |
| **File Storage** | **Synology NAS** (NFS/SMB) | Source of truth. Files served directly via API. Not duplicated. |
| **MCP Server** | **Rust** (`rmcp` crate) | JSON-RPC 2.0 over stdio (local) and SSE (remote). |
| **Embedding Model** | **nomic-embed-text-v1.5** (GGUF, 768-dim) | Dedicated embedding model, 137M params, ~270 MB. Runs on Stella alongside Qwen3-8B or as a separate llama-server on any host. |
| **Summarization** | **Pegasus** (GPT-OSS-120B) or **Max** (Qwen3-Coder-Next 80B) | Async queue. Pegasus for deep analysis, Max for large documents (256K context). |
| **Task Queue** | **Tokio bounded channels** | In-process async job queue for LLM tasks. No external dependency. |
| **Container Runtime** | **Docker Compose** | Health checks, restart policies. |

### 2.2 Tier 2 Additions

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Event Bus + Task Queue** | **NATS JetStream** | Replaces Tokio channels. Durable pub/sub, work queues for LLM jobs, back-pressure. |
| **Cache** | **Redis** (or Valkey) | Query result cache, rate limiting counters. |
| **File Cache** | **MinIO** (S3-compatible) | Read-through cache for NAS files. First download copies file to MinIO; subsequent downloads served from MinIO. |
| **Real-time** | **WebSocket + SSE** | Push notifications for index updates. |
| **Secrets** | **Sealed Secrets** or **SOPS** | Encrypted secrets in Git, decrypted in cluster. |

### 2.3 Tier 3 Additions

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Search Engine** | **OpenSearch** (replaces Meilisearch) | Sharding, k-NN vector search, cross-cluster replication. |
| **Object Store** | **MinIO** (erasure-coded, 4+2) | Distributed blob serving, HA. |
| **Auth** | **Keycloak** + **OPA** | OIDC identity, fine-grained ABAC policies. |
| **Secrets** | **HashiCorp Vault** | Full secret lifecycle management. |
| **Service Mesh** | **Istio** or **Linkerd** | mTLS, traffic shaping, observability. |
| **HA Postgres** | **Patroni** | Auto-failover, streaming replication. |
| **Observability** | **Prometheus + Grafana + Jaeger + Loki** | Metrics, dashboards, traces, logs. |

---

## 3. Data Flow

### 3.1 Ingestion Pipeline

```
NAS File System (source of truth)
     │
     ├── inotify watcher (real-time, Linux) ──┐
     │                                         │
     └── periodic scan (configurable interval) ┤
                                               │
                                               ▼
                                   ┌──────────────────┐
                                   │ File Discovery    │
                                   │                   │
                                   │ 1. Stat file      │
                                   │ 2. Check mtime    │
                                   │    vs last scan   │
                                   │ 3. If changed:    │
                                   │    compute SHA-256│
                                   │ 4. Dedup check    │
                                   └────────┬─────────┘
                                            │
                          ┌─────────────────┼─────────────────┐
                          │                 │                 │
                    unchanged          new file         changed file
                    (skip)                 │                 │
                                          └────────┬────────┘
                                                   │
                                                   ▼
                                      ┌────────────────────┐
                                      │ Content Detection   │
                                      │ (magic bytes +      │
                                      │  extension + UTF-8  │
                                      │  validation)        │
                                      └────────┬───────────┘
                                               │
                              ┌────────────────┼────────────────┐
                              │                │                │
                              ▼                ▼                ▼
                     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
                     │ ASCII Parser │  │ JSON Parser  │  │ XML Parser   │
                     │              │  │              │  │              │
                     │ Detect       │  │ serde_json   │  │ quick-xml    │
                     │ structure:   │  │ recursive    │  │ SAX-style    │
                     │ CSV, TSV,    │  │ walk:        │  │ streaming:   │
                     │ log format,  │  │ field types, │  │ namespace    │
                     │ key=value,   │  │ nesting,     │  │ tracking,    │
                     │ freeform     │  │ array sizes, │  │ attribute    │
                     │              │  │ JSON Schema  │  │ extraction,  │
                     │ Chunk by     │  │ generation   │  │ element tree │
                     │ paragraph    │  │              │  │              │
                     │ or N lines   │  │ Chunk by     │  │ Chunk by     │
                     │              │  │ top-level    │  │ configurable │
                     │              │  │ array items  │  │ XPath node   │
                     └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
                            │                 │                 │
                            └────────┬────────┘─────────────────┘
                                     │
                                     ▼
                   ┌────────────────────────────────┐
                   │ Index Writer                    │
                   │                                 │
                   │ 1. PostgreSQL: file metadata,   │
                   │    schema, extracted fields,    │
                   │    chunk records                │
                   │ 2. Meilisearch: chunk content   │
                   │    for full-text search         │
                   │ 3. Queue: LLM tasks (async)     │
                   │    - embedding per chunk         │
                   │    - entity extraction           │
                   │    - summary per file            │
                   └────────────────────────────────┘
                                     │
                                     ▼ (async, non-blocking)
                   ┌────────────────────────────────┐
                   │ LLM Pipeline (optional)         │
                   │                                 │
                   │ 1. Entity extraction:           │
                   │    Regex: IPs, URLs, emails     │
                   │    Stella: contextual entities  │
                   │    → stored in entities table   │
                   │                                 │
                   │ 2. Embedding model:             │
                   │    nomic-embed-text-v1.5 (GGUF) │
                   │    → 768-dim vector per chunk   │
                   │    → stored in pgvector         │
                   │                                 │
                   │ 3. Summarization (per file):    │
                   │    Pegasus: deep schema analysis│
                   │    Max: large docs (256K ctx)   │
                   │    → stored in files.ai_summary │
                   │                                 │
                   │ 4. Relationship builder:        │
                   │    Entity co-occurrence scan    │
                   │    Pegasus: describe relations  │
                   │    → stored in relationships    │
                   │                                 │
                   │ 5. Anomaly detection:           │
                   │    Schema baseline comparison   │
                   │    Credential pattern scan      │
                   │    Stella: assess anomalies     │
                   │    → stored in anomalies table  │
                   └────────────────────────────────┘
```

### 3.2 Deduplication Strategy

Files are content-addressed by SHA-256.

1. **Fast path**: Check file `mtime` against last scan timestamp. If unchanged, skip entirely (no hash computation).
2. **Hash check**: If mtime changed, compute SHA-256.
   - Hash matches stored value → file content unchanged (mtime was touched by backup, NAS snapshot, etc.). Update `last_seen_at`, skip re-index.
   - Hash exists but path differs → same content in new location. Create `file_paths` entry (dedup link).
   - Hash changed for existing path → content modified. Create `file_versions` entry, re-parse, re-index.
   - New hash + new path → fully new file. Full pipeline.
3. **Periodic integrity scan** (configurable, default weekly): Re-hash a random sample of indexed files and compare to stored SHA-256. Flag mismatches as potential bitrot for investigation.

### 3.3 Content Chunking Strategy

Large files need chunking for search quality and embedding generation.

| File Type | Chunking Strategy | Default Chunk Size | Overlap |
|-----------|------------------|--------------------|---------|
| **ASCII (freeform)** | Split by double-newline (paragraph) or every N lines | 100 lines | 10 lines |
| **ASCII (structured: CSV, TSV, logs)** | Split by N rows, preserve header | 500 rows | 0 (header repeated) |
| **JSON (object)** | Single chunk (unless > max size) | 64 KB | n/a |
| **JSON (array)** | Split by top-level array elements, N per chunk | 100 elements | 0 |
| **JSON (nested)** | Flatten to configurable JSONPath boundaries | 64 KB | n/a |
| **XML** | Split by configurable XPath node (e.g., `//record`, `//entry`) | Per node | 0 |
| **XML (flat)** | Split by N sibling elements under root | 100 elements | 0 |

**Chunk storage:**
- Each chunk is a separate Meilisearch document with `file_id` + `chunk_index`
- Each chunk gets its own embedding vector (stored in a `chunk_embeddings` table)
- Search returns chunk-level results, grouped and deduplicated by `file_id`
- File-level summary (LLM-generated) covers the entire file, not per-chunk

**File size limits:**
- Files > 100 MB (configurable): index metadata only (name, size, hash, path, mime). No content parsing, no chunking, no embedding.
- Files 10-100 MB: streaming parser, chunked indexing, sampled embedding (every Nth chunk)
- Files < 10 MB: full parse, full chunk, full embedding

### 3.4 Embedding Model Strategy

**The problem**: Chat/completion models (Qwen3-8B, GPT-OSS-120B, Qwen3-Coder-Next)
produce poor-quality embeddings compared to purpose-built embedding models. Their
hidden-state representations are optimized for next-token prediction, not semantic
similarity.

**The solution**: Run a dedicated embedding model.

| Model | Dimensions | Params | GGUF Size | Quality |
|-------|-----------|--------|-----------|---------|
| **nomic-embed-text-v1.5** (recommended) | 768 | 137M | ~270 MB | Excellent, Matryoshka support |
| bge-large-en-v1.5 | 1024 | 326M | ~650 MB | Slightly better quality |
| snowflake-arctic-embed-m | 768 | 109M | ~220 MB | Fast, compact |

**Deployment**: Run as a second llama-server instance on any host with `--embedding` flag:

```bash
# On Stella (alongside Qwen3-8B on port 8000):
~/llama.cpp/build/bin/llama-server \
  -m /mnt/models/nomic-embed-text-v1.5.Q8_0.gguf \
  --embedding --port 8001 \
  --host 0.0.0.0 \
  -c 8192 -ngl 999 --no-mmap
```

**API**: Standard `/v1/embeddings` endpoint. Input text, output 768-dim vector.

**Consistency**: All embeddings use the same model and dimension. No mixed-dimension fallback. If the embedding service is down, files are indexed without embeddings and queued for embedding when service recovers.

### 3.5 LLM Task Distribution

| LLM | Role | Best For | API |
|-----|------|----------|-----|
| **Embedding model** (on Stella) | Embeddings | All chunks (768-dim vectors) | `stella.home.arpa:8001/v1/embeddings` |
| **Stella** (Qwen3-8B) | Classification + Entity extraction | File classification, tag suggestion, named entity extraction, anomaly review | `stella.home.arpa:8000/v1/chat/completions` |
| **Pegasus** (GPT-OSS-120B) | Deep analysis | Schema inference, cross-file relationship description, complex summarization, synonym generation | `pegasus.home.arpa:8000/v1/chat/completions` |
| **Max** (Qwen3-Coder-Next 80B) | Large documents | Summarizing files >32K tokens (256K context), bulk entity extraction from large XML/JSON | `max.home.arpa:8080/v1/chat/completions` |

**Fallback chain**: If an LLM is unavailable, the task is:
1. Retried 3 times with exponential backoff
2. If still failing, queued as `pending` in `llm_jobs` table
3. A health check runs every 60s; when the LLM comes back, pending jobs resume
4. Core indexing (metadata, full-text, structured fields) **never** waits for LLMs

### 3.6 Advanced LLM Intelligence

Beyond basic tagging and summarization, the LLM pipeline can build a deep understanding
of the data corpus. These features are async, optional, and progressively enhance search
quality as they complete.

#### 3.6.1 Entity Extraction

An LLM scans each file's content and extracts **named entities** — structured data points
that make unstructured content queryable.

**Entity types extracted:**

| Entity Type | Examples | Extracted From |
|-------------|----------|----------------|
| `hostname` | `db-prod-01.example.com`, `10.0.1.50` | All file types |
| `ip_address` | `192.168.1.1`, `2001:db8::1` | ASCII logs, XML/JSON configs |
| `port` | `5432`, `8080` | All file types |
| `username` | `admin`, `llm-agent` | Logs, configs |
| `filepath` | `/etc/nginx/nginx.conf` | All file types |
| `database` | `prod_main`, `analytics_db` | Configs, connection strings |
| `url` | `https://api.example.com/v1` | All file types |
| `email` | `ops@example.com` | All file types |
| `date_reference` | `2026-01-15`, `last Tuesday` | Logs, reports |
| `version` | `v2.3.1`, `PostgreSQL 17.2` | All file types |
| `error_code` | `HTTP 503`, `ECONNREFUSED`, `ORA-12154` | Logs, XML |
| `credential_ref` | `AWS_ACCESS_KEY_ID`, `PGPASSWORD` | Configs (flag, don't store values) |
| `custom` | User-defined via config | Configurable patterns |

**How it works:**
- **Fast path (regex, no LLM)**: IP addresses, URLs, emails, file paths, and common
  patterns are extracted via regex during parsing. Zero LLM cost, runs on every file.
- **LLM path (Stella)**: For each chunk, Stella classifies ambiguous entities, resolves
  context (e.g., is "production" a tag, an environment name, or a general word?), and
  extracts domain-specific entities.
- **Prompt template**:

```
Analyze this {mime_type} content and extract all named entities.
For each entity, provide:
- type: one of [hostname, ip_address, port, username, filepath, database, url,
  email, version, error_code, service_name, config_key]
- value: the exact entity string
- context: the surrounding phrase (max 100 chars)
- confidence: high/medium/low

Content:
{chunk_content}

Return as JSON array.
```

**Storage**: Entities are stored in a dedicated table and indexed for fast lookup.
This turns "grep for an IP address across 100K files" into a sub-50ms query.

#### 3.6.2 Cross-File Relationship Mapping

Files often reference each other implicitly. A JSON config might specify a database
hostname that also appears in 50 log files and 3 XML deployment descriptors. SISS
builds a **relationship graph** by connecting files through shared entities.

**Relationship types:**

| Relationship | How Detected | Example |
|-------------|-------------|---------|
| `references_same_host` | Same `hostname` or `ip_address` entity | config.json and access.log both reference `db-prod-01` |
| `references_same_service` | Same `url` or `port` + `hostname` combination | deployment.xml and monitoring.json both reference `api:8080` |
| `same_schema` | Same `schema_id` in PostgreSQL | All files matching a discovered JSON schema |
| `semantic_similarity` | Cosine similarity > 0.85 between file-level embeddings | Two different config files for similar services |
| `version_chain` | Same `file_path`, different `sha256` over time | file_versions history |
| `references_file` | One file contains the path of another file | Dockerfile references `nginx.conf` |
| `shared_credentials` | Same `credential_ref` entity (key name only, not value) | Multiple configs using `PGPASSWORD` |

**How it works:**
1. **Entity co-occurrence** (no LLM needed): After entity extraction, a background job
   finds files sharing 2+ entities of the same type/value. These form automatic edges.
2. **LLM-enhanced relationships** (Pegasus): For files with high entity overlap, Pegasus
   analyzes the pair and describes the relationship in natural language.

```
Given these two files share the entities [db-prod-01, port 5432, database prod_main],
describe the relationship between them:

File A (db-config.json): {summary}
File B (migration-log.txt): {summary}

Describe in one sentence how these files are related.
```

3. **Graph storage**: Relationships are stored as edges in PostgreSQL with source file,
   target file, relationship type, shared entities, and confidence score. This can be
   exported as a knowledge graph (e.g., for visualization in a graph UI or queried via API).

#### 3.6.3 Auto-Generated Search Synonyms

Domain-specific data often uses different terms for the same concept. A search for
"server" should also find "host", "node", "instance", "machine". Standard search
engines don't know this without a synonym dictionary.

**How it works:**
1. **Corpus analysis**: After initial indexing, batch-process the top 1000 most-frequent
   terms through Stella with this prompt:

```
Given these terms frequently appear in a corpus of {description}:
{term_list}

For each term, suggest synonyms and related terms that a user searching
for one might also want to find. Only include synonyms that are genuinely
interchangeable in this domain context.

Return as JSON: {"term": ["synonym1", "synonym2"]}
```

2. **Synonym storage**: Stored in a `synonyms` table and pushed to Meilisearch's
   [synonym configuration](https://www.meilisearch.com/docs/reference/api/synonyms):

```json
PUT /indexes/chunks/settings/synonyms
{
  "server": ["host", "node", "instance", "machine"],
  "database": ["db", "datastore", "schema"],
  "config": ["configuration", "settings", "conf"],
  "error": ["exception", "failure", "fault"],
  "deploy": ["deployment", "release", "rollout"]
}
```

3. **Refresh cycle**: Re-generate synonyms monthly or when >10% of corpus changes.
   Synonyms are additive — new terms extend the dictionary, old terms remain unless
   manually removed.

4. **User overrides**: Admins can add/remove synonyms via the API. User-defined
   synonyms take priority over LLM-generated ones.

#### 3.6.4 Anomaly Detection

When files share a schema, deviations become detectable. If 500 JSON config files all
have `{"host": "...", "port": ..., "database": "..."}` but one also has
`{"password": "hunter2"}`, that's worth flagging.

**Detection methods:**

| Method | LLM Required | Detects |
|--------|-------------|---------|
| **Schema outlier** | No | File has fields not present in >95% of schema siblings |
| **Value outlier** | No | Numeric field value is >3 standard deviations from schema mean |
| **Missing fields** | No | File is missing fields present in >95% of schema siblings |
| **Content anomaly** | Yes (Stella) | Unusual content patterns, potential misconfigurations, unexpected data |
| **Size anomaly** | No | File is >3x larger or smaller than schema siblings' median |
| **Credential exposure** | Regex | File contains patterns matching API keys, passwords, tokens |

**How it works:**
1. **Statistical baseline**: For each schema with >10 files, compute field presence
   frequency, numeric value distributions, and median file size.
2. **Outlier scan** (no LLM, runs on every index): Compare each new file against its
   schema baseline. Flag deviations as anomalies with severity.
3. **LLM review** (Stella, async): For medium/high-severity anomalies, have Stella
   explain what's unusual and whether it's likely a problem:

```
This {mime_type} file matches schema "{schema_name}" (used by {file_count} files).
However, it has these deviations:
{anomaly_list}

Is this likely a problem (misconfiguration, data quality issue, security risk)
or a legitimate variation? Explain in one sentence.
```

**Anomaly severity:**

| Severity | Criteria | Action |
|----------|----------|--------|
| `critical` | Credential exposure (regex match) | Immediate flag, block from search results by default |
| `high` | New fields containing "password", "secret", "key", "token" | Flag + LLM review |
| `medium` | Schema outlier (extra/missing fields) | Queue for LLM review |
| `low` | Size or value outlier | Log, visible in file metadata |
| `info` | Legitimate variation confirmed by LLM | Dismiss, update baseline |

### 3.7 Search & Retrieval

```
Client Request
       │
       ▼
  ┌──────────┐     ┌──────────────────────────────────────┐
  │ Parse    │     │ Query Router                          │
  │ query    │────►│                                       │
  │ intent   │     │  "text search"    → Meilisearch       │
  └──────────┘     │  "JSONPath"       → PostgreSQL        │
                   │  "XPath"          → PostgreSQL        │
                   │  "semantic"       → pgvector          │
                   │  "entity search"  → entities table    │
                   │  "related files"  → relationships     │
                   │  "hybrid"         → all + RRF merge   │
                   └──────────────┬───────────────────────┘
                                  │
                                  ▼
                        ┌─────────────────┐
                        │ Result Merger   │
                        │ & Re-ranker     │
                        │                 │
                        │ Reciprocal Rank │
                        │ Fusion (RRF)    │
                        │                 │
                        │ Dedup by        │
                        │ file_id (chunks │
                        │ grouped)        │
                        └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │ Response:       │
                        │ - file metadata │
                        │ - best chunk    │
                        │   highlights    │
                        │ - ai_summary    │
                        │ - download URL  │
                        │ - NAS path      │
                        └─────────────────┘
```

**NAS unavailability**: If NAS mount is unreachable during a download request:
- Return HTTP 503 with `Retry-After: 30` header
- Search results still work (Meilisearch/PostgreSQL are local)
- Metadata and AI summaries still returned
- At Tier 2+, MinIO cache serves previously-accessed files

---

## 4. API Specification

### 4.1 REST JSON API

**Base URL**: `https://siss.home.arpa/api/v1`

#### File Operations

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| `GET` | `/files` | List files with filtering, pagination, faceting | Cursor or offset pagination |
| `GET` | `/files/{id}` | File metadata, schema, AI summary, chunks | |
| `GET` | `/files/{id}/content` | Stream raw file content from NAS | Chunked transfer for large files |
| `GET` | `/files/{id}/download` | Download with `Content-Disposition: attachment` | HMAC-signed URL at Tier 2+ |
| `GET` | `/files/{id}/schema` | Inferred schema (JSON Schema or element tree) | |
| `GET` | `/files/{id}/versions` | Version history (by path) | |
| `GET` | `/files/{id}/chunks` | List chunks with content previews | |
| `POST` | `/files` | Upload file (multipart) | Optional ClamAV scan |
| `POST` | `/files/batch` | Upload multiple files | Returns 202 + job ID |
| `PATCH` | `/files/{id}` | Update tags, description | |
| `DELETE` | `/files/{id}` | Soft-delete (remove from index, keep on NAS) | |

#### Search Operations

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| `GET` | `/search` | Simple full-text search | `?q=term&cursor=xxx` |
| `POST` | `/search` | Advanced search with DSL | See query DSL below |
| `POST` | `/search/semantic` | Vector similarity search | Requires embedding model |
| `POST` | `/search/hybrid` | Combined text + semantic + structured | RRF re-ranking |
| `POST` | `/search/xpath` | XPath query across XML files | |
| `POST` | `/search/jsonpath` | JSONPath query across JSON files | |

#### Entity & Relationship Operations

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| `GET` | `/entities` | List entities with filtering | `?type=hostname&value=db-prod*` |
| `GET` | `/entities/{type}/{value}/files` | Find all files containing a specific entity | e.g. `/entities/hostname/db-prod-01/files` |
| `GET` | `/files/{id}/entities` | List all entities extracted from a file | |
| `GET` | `/files/{id}/related` | Get files related to this file (via shared entities) | Includes relationship type and confidence |
| `GET` | `/relationships` | Browse the relationship graph | Filter by type, min confidence |
| `GET` | `/anomalies` | List detected anomalies | Filter by severity, schema |
| `GET` | `/files/{id}/anomalies` | Anomalies for a specific file | |
| `PATCH` | `/anomalies/{id}` | Dismiss or acknowledge an anomaly | |
| `GET` | `/synonyms` | List active synonym mappings | |
| `PUT` | `/synonyms` | Add/update user-defined synonyms | |
| `DELETE` | `/synonyms/{term}` | Remove a synonym mapping | |

#### Schema & Analytics

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/schemas` | List discovered schemas with file counts |
| `GET` | `/schemas/{id}` | Schema definition (JSON Schema) |
| `GET` | `/schemas/{id}/files` | Files matching this schema |
| `GET` | `/stats` | Index stats (file count, size, types, LLM health) |
| `GET` | `/stats/facets/{field}` | Top values for a field |

#### Ingestion Control

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/ingest/scan` | Trigger NAS re-scan (returns 202 + job ID) |
| `GET` | `/ingest/status` | Queue depth, processing rate, LLM job counts |
| `POST` | `/ingest/reindex/{id}` | Force re-index of a file |

#### Health & Operations

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/healthz` | Liveness probe (always 200 if process is running) |
| `GET` | `/readyz` | Readiness probe (checks PostgreSQL, Meilisearch, NAS) |
| `GET` | `/metrics` | Prometheus metrics endpoint |

#### Advanced Search DSL

```json
POST /api/v1/search
{
  "query": {
    "text": "database connection configuration",
    "filters": {
      "mime": ["application/json", "text/xml"],
      "tags": ["production"],
      "size_range": {"min": 1024, "max": 10485760},
      "indexed_after": "2026-01-01T00:00:00Z"
    },
    "json_path": "$.database.connections[?(@.host)]",
    "xpath": "//server[@environment='production']",
    "semantic": {
      "text": "database connection pooling settings",
      "weight": 0.3
    }
  },
  "sort": [{"field": "relevance", "order": "desc"}],
  "facets": ["mime", "tags", "schema_id"],
  "cursor": "eyJpZCI6MTAwfQ==",
  "size": 20,
  "highlight": true
}
```

**Response:**

```json
{
  "total": 142,
  "cursor": "eyJpZCI6MTIwfQ==",
  "took_ms": 23,
  "items": [
    {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "name": "db-config.json",
      "path": "/volume1/data/configs/db-config.json",
      "mime": "application/json",
      "size": 2048,
      "sha256": "a1b2c3...",
      "schema_id": "sch-001",
      "tags": ["production", "database"],
      "ai_summary": "PostgreSQL connection pool configuration for the production cluster with read replicas.",
      "chunk_match": {
        "chunk_index": 0,
        "highlight": "...max_<em>connections</em>: 100, <em>database</em>: prod_main..."
      },
      "indexed_at": "2026-02-10T14:30:00Z",
      "score": 0.94
    }
  ],
  "facets": {
    "mime": [
      {"value": "application/json", "count": 89},
      {"value": "text/xml", "count": 53}
    ]
  }
}
```

**Error model:**

```json
{
  "error": {
    "code": "INVALID_QUERY",
    "message": "Invalid JSONPath expression at position 12",
    "details": {
      "expression": "$.database[invalid",
      "position": 12,
      "expected": "bracket close or filter expression"
    }
  }
}
```

### 4.2 MCP Server

**Protocol**: JSON-RPC 2.0 over stdio (local agents) and SSE (remote agents at `/mcp`)

**Note**: Pagination and range access on tools/resources below are engineering best
practices for large result sets, not MCP specification requirements.

#### Server Manifest

```json
{
  "name": "siss",
  "version": "1.0.0",
  "description": "Search, retrieve, and manage indexed files on NAS storage",
  "capabilities": {
    "tools": true,
    "resources": true,
    "prompts": true
  }
}
```

#### Tools

```json
[
  {
    "name": "search_files",
    "description": "Full-text search across all indexed ASCII, XML, and JSON files. Returns matching files with relevance-ranked highlights and chunk context.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Free-text search query"
        },
        "mime_filter": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Filter by MIME types, e.g. ['application/json', 'text/xml']"
        },
        "tags": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Filter by tags"
        },
        "max_results": {
          "type": "integer",
          "default": 10,
          "description": "Maximum results to return (1-100)"
        },
        "cursor": {
          "type": "string",
          "description": "Pagination cursor from previous response"
        }
      },
      "required": ["query"]
    }
  },
  {
    "name": "search_semantic",
    "description": "Semantic similarity search using vector embeddings. Finds conceptually related files even without exact keyword matches. Requires embedding model to be running.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Natural language description of what you're looking for"
        },
        "max_results": {
          "type": "integer",
          "default": 10
        }
      },
      "required": ["query"]
    }
  },
  {
    "name": "search_hybrid",
    "description": "Combined full-text and semantic search with reciprocal rank fusion. Best overall search quality.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "query": {"type": "string"},
        "semantic_weight": {
          "type": "number",
          "default": 0.3,
          "description": "Weight for semantic results (0-1). Higher = more semantic, lower = more keyword."
        },
        "max_results": {"type": "integer", "default": 10}
      },
      "required": ["query"]
    }
  },
  {
    "name": "query_jsonpath",
    "description": "Execute a JSONPath query across all indexed JSON files. Returns matching values with file context.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "expression": {
          "type": "string",
          "description": "JSONPath expression, e.g. '$.servers[*].hostname'"
        },
        "file_filter": {
          "type": "string",
          "description": "Optional glob pattern to limit which files to query, e.g. 'configs/*.json'"
        }
      },
      "required": ["expression"]
    }
  },
  {
    "name": "query_xpath",
    "description": "Execute an XPath query across all indexed XML files. Returns matching nodes with file context.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "expression": {
          "type": "string",
          "description": "XPath expression, e.g. '//server[@env=\"prod\"]/@hostname'"
        },
        "file_filter": {
          "type": "string",
          "description": "Optional glob pattern to limit which files to query"
        }
      },
      "required": ["expression"]
    }
  },
  {
    "name": "get_file",
    "description": "Retrieve the content of a file by ID or NAS path. Large files are returned truncated with a byte count; use offset/length for paging through large content.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "file_id": {"type": "string", "description": "File UUID"},
        "path": {"type": "string", "description": "NAS path (alternative to file_id)"},
        "offset": {"type": "integer", "default": 0, "description": "Byte offset to start reading from"},
        "length": {"type": "integer", "default": 102400, "maximum": 1048576, "description": "Max bytes to return (default 100KB, max 1MB)"}
      }
    }
  },
  {
    "name": "get_file_schema",
    "description": "Get the inferred schema (JSON Schema or element tree) for a structured file.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "file_id": {"type": "string"}
      },
      "required": ["file_id"]
    }
  },
  {
    "name": "upload_file",
    "description": "Upload a new file to the NAS and trigger indexing.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "name": {"type": "string", "description": "Filename with extension"},
        "path": {"type": "string", "description": "Target directory on NAS"},
        "content_base64": {"type": "string", "description": "File content as base64"},
        "tags": {"type": "array", "items": {"type": "string"}}
      },
      "required": ["name", "path", "content_base64"]
    }
  },
  {
    "name": "upload_batch",
    "description": "Upload multiple files in one operation. Returns a job ID for tracking.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "files": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": {"type": "string"},
              "path": {"type": "string"},
              "content_base64": {"type": "string"},
              "tags": {"type": "array", "items": {"type": "string"}}
            },
            "required": ["name", "path", "content_base64"]
          }
        }
      },
      "required": ["files"]
    }
  },
  {
    "name": "list_schemas",
    "description": "List all discovered document schemas with file counts.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "mime_filter": {"type": "string"},
        "cursor": {"type": "string"}
      }
    }
  },
  {
    "name": "get_stats",
    "description": "Index statistics: total files, storage used, type distribution, queue status, LLM health.",
    "inputSchema": {
      "type": "object",
      "properties": {}
    }
  },
  {
    "name": "trigger_rescan",
    "description": "Trigger a NAS re-scan to discover new or changed files. Returns a job ID.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "path": {"type": "string", "description": "Limit scan to a specific directory"}
      }
    }
  },
  {
    "name": "search_entities",
    "description": "Search for extracted entities (hostnames, IPs, URLs, database names, etc.) across all indexed files. Useful for finding all files that reference a specific server, service, or resource.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "entity_type": {
          "type": "string",
          "enum": ["hostname", "ip_address", "port", "username", "filepath", "database", "url", "email", "version", "error_code", "service_name", "config_key"],
          "description": "Type of entity to search for"
        },
        "value": {
          "type": "string",
          "description": "Entity value or prefix to search for (supports wildcards: 'db-prod*')"
        },
        "max_results": {"type": "integer", "default": 20}
      },
      "required": ["value"]
    }
  },
  {
    "name": "find_related_files",
    "description": "Find files related to a given file through shared entities (same hostnames, IPs, services), structural similarity (same schema), or semantic similarity (similar content meaning). Returns the relationship type and shared context.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "file_id": {"type": "string", "description": "Source file UUID"},
        "relationship_types": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Filter by relationship types: 'references_same_host', 'same_schema', 'semantic_similarity', 'references_file', etc."
        },
        "min_confidence": {
          "type": "number",
          "default": 0.5,
          "description": "Minimum confidence score (0-1)"
        },
        "max_results": {"type": "integer", "default": 10}
      },
      "required": ["file_id"]
    }
  },
  {
    "name": "get_anomalies",
    "description": "List detected anomalies across the indexed corpus. Anomalies include schema outliers, credential exposures, unusual field values, and content deviations. Useful for security audits and data quality checks.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "severity": {
          "type": "string",
          "enum": ["critical", "high", "medium", "low"],
          "description": "Filter by minimum severity"
        },
        "status": {
          "type": "string",
          "enum": ["open", "acknowledged", "dismissed"],
          "default": "open"
        },
        "max_results": {"type": "integer", "default": 20}
      }
    }
  },
  {
    "name": "explore_entity_graph",
    "description": "Starting from an entity (e.g., hostname 'db-prod-01'), traverse the relationship graph to discover all connected files and entities up to N hops away. Returns a subgraph showing how files are interconnected.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "entity_type": {"type": "string"},
        "entity_value": {"type": "string"},
        "max_hops": {
          "type": "integer",
          "default": 2,
          "maximum": 4,
          "description": "Maximum relationship hops to traverse"
        },
        "max_nodes": {
          "type": "integer",
          "default": 50,
          "description": "Maximum files to return in subgraph"
        }
      },
      "required": ["entity_type", "entity_value"]
    }
  }
]
```

#### Resources

```json
[
  {
    "uri": "siss://stats",
    "name": "Index Statistics",
    "description": "Current index health: file counts by type, storage, queue depth, LLM status",
    "mimeType": "application/json"
  },
  {
    "uri": "siss://schemas",
    "name": "Schema Registry",
    "description": "All discovered document schemas with file counts",
    "mimeType": "application/json"
  },
  {
    "uri": "siss://file/{file_id}",
    "name": "File Content",
    "description": "Raw content of a specific indexed file",
    "mimeType": "application/octet-stream"
  },
  {
    "uri": "siss://recent",
    "name": "Recently Indexed",
    "description": "Last 50 files added to the index",
    "mimeType": "application/json"
  },
  {
    "uri": "siss://entities/{type}",
    "name": "Entity Index",
    "description": "All extracted entities of a given type (e.g., siss://entities/hostname)",
    "mimeType": "application/json"
  },
  {
    "uri": "siss://anomalies",
    "name": "Open Anomalies",
    "description": "Currently open anomalies sorted by severity",
    "mimeType": "application/json"
  },
  {
    "uri": "siss://synonyms",
    "name": "Synonym Dictionary",
    "description": "Active search synonym mappings (LLM-generated and user-defined)",
    "mimeType": "application/json"
  }
]
```

#### Prompts

```json
[
  {
    "name": "explore_data",
    "description": "Guided exploration of the indexed data. Starts with stats, suggests searches based on discovered schemas.",
    "arguments": [
      {
        "name": "focus",
        "description": "Optional area of interest, e.g. 'XML configs' or 'JSON API responses'",
        "required": false
      }
    ]
  },
  {
    "name": "find_related",
    "description": "Given a file, find semantically and structurally related files.",
    "arguments": [
      {
        "name": "file_id",
        "description": "The source file to find relatives of",
        "required": true
      }
    ]
  },
  {
    "name": "audit_corpus",
    "description": "Security and quality audit of the indexed corpus. Reviews open anomalies, credential exposures, schema deviations, and provides a prioritized action list.",
    "arguments": [
      {
        "name": "focus",
        "description": "Focus area: 'security' (credentials, exposures), 'quality' (schema deviations, outliers), or 'all'",
        "required": false
      }
    ]
  },
  {
    "name": "trace_entity",
    "description": "Trace an entity (hostname, IP, service) across the corpus. Shows all files referencing it, how they're connected, and what role the entity plays in each context.",
    "arguments": [
      {
        "name": "entity",
        "description": "The entity to trace, e.g., 'db-prod-01' or '10.0.1.50'",
        "required": true
      }
    ]
  }
]
```

#### MCP Configuration

**Local (stdio) — for Claude Code, etc.:**

```json
{
  "mcpServers": {
    "siss": {
      "command": "siss",
      "args": ["mcp", "--mode", "stdio"],
      "env": {
        "SISS_API_URL": "https://siss.home.arpa/api/v1",
        "SISS_API_KEY": "your-api-key"
      }
    }
  }
}
```

**Remote (SSE) — for Claude Desktop, etc.:**

```json
{
  "mcpServers": {
    "siss": {
      "url": "https://siss.home.arpa/mcp",
      "headers": {
        "Authorization": "Bearer your-api-key"
      }
    }
  }
}
```

---

## 5. Storage & Schema Design

### 5.1 NAS Directory Structure

```
/volume1/data/                    <-- SISS-watched root (configurable)
 ├── configs/                     <-- XML/JSON config files
 ├── logs/                        <-- ASCII log files
 ├── exports/                     <-- data exports
 └── uploads/                     <-- files uploaded via SISS API (writable)
```

At Tier 1, files are served directly from NAS via the API. No duplication.
At Tier 2+, MinIO caches files on first access (read-through).

### 5.2 PostgreSQL Schema

```sql
-- Core file registry
CREATE TABLE files (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sha256          CHAR(64) NOT NULL,
    size            BIGINT NOT NULL,
    mime            TEXT NOT NULL,
    encoding        TEXT,                          -- UTF-8, ASCII, etc.
    created_at      TIMESTAMPTZ DEFAULT now(),
    modified_at     TIMESTAMPTZ,                   -- NAS file mtime
    indexed_at      TIMESTAMPTZ,
    reindexed_at    TIMESTAMPTZ,
    status          TEXT DEFAULT 'pending'
                    CHECK (status IN ('pending','indexing','indexed','failed','deleted','metadata_only')),
    schema_id       UUID REFERENCES schemas(id),
    chunk_count     INTEGER DEFAULT 0,
    ai_summary      TEXT,                          -- LLM-generated summary
    ai_tags         TEXT[],                        -- LLM-classified tags
    user_tags       TEXT[],                        -- user-assigned tags
    metadata        JSONB DEFAULT '{}',
    description     TEXT                           -- user-provided description
);

-- Multiple paths can point to same content (dedup)
CREATE TABLE file_paths (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    nas_path        TEXT NOT NULL UNIQUE,
    discovered_at   TIMESTAMPTZ DEFAULT now(),
    last_seen_at    TIMESTAMPTZ DEFAULT now(),
    is_primary      BOOLEAN DEFAULT true
);

-- Content chunks (for search and embedding)
CREATE TABLE chunks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    chunk_index     INTEGER NOT NULL,
    content_preview TEXT,                           -- first 1000 chars
    byte_offset     BIGINT,                        -- position in original file
    byte_length     BIGINT,
    token_count     INTEGER,                       -- estimated token count
    embedding       vector(768),                   -- from dedicated embedding model
    UNIQUE (file_id, chunk_index)
);

-- Inferred schemas (deduplicated across similar files)
CREATE TABLE schemas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT,
    mime            TEXT NOT NULL,
    schema_json     JSONB NOT NULL,                -- JSON Schema representation
    schema_hash     CHAR(64) NOT NULL UNIQUE,      -- SHA-256 of canonical schema
    file_count      INTEGER DEFAULT 0,
    sample_file_id  UUID REFERENCES files(id),
    created_at      TIMESTAMPTZ DEFAULT now(),
    description     TEXT                           -- LLM-generated description
);

-- File version history
CREATE TABLE file_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    sha256          CHAR(64) NOT NULL,
    size            BIGINT NOT NULL,
    captured_at     TIMESTAMPTZ DEFAULT now()
);

-- Extracted structured fields (for JSONPath/XPath queries)
CREATE TABLE extracted_fields (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    field_path      TEXT NOT NULL,                  -- "$.database.host" or "//server/@name"
    field_type      TEXT NOT NULL,                  -- string, number, boolean, array, object
    value_text      TEXT,
    value_numeric   DOUBLE PRECISION,
    value_boolean   BOOLEAN
);

-- Extracted entities (hostnames, IPs, URLs, etc.)
CREATE TABLE entities (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    chunk_id        UUID REFERENCES chunks(id) ON DELETE CASCADE,
    entity_type     TEXT NOT NULL,                  -- 'hostname', 'ip_address', 'url', etc.
    value           TEXT NOT NULL,                  -- the entity value
    normalized      TEXT NOT NULL,                  -- lowercase, trimmed for matching
    context         TEXT,                           -- surrounding text (max 200 chars)
    confidence      TEXT DEFAULT 'high',            -- 'high', 'medium', 'low'
    source          TEXT DEFAULT 'regex',           -- 'regex' or 'llm'
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- Cross-file relationships (built from shared entities)
CREATE TABLE file_relationships (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id  UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    target_file_id  UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    relationship    TEXT NOT NULL,                  -- 'references_same_host', 'semantic_similarity', etc.
    shared_entities JSONB,                          -- [{"type": "hostname", "value": "db-prod-01"}, ...]
    confidence      REAL NOT NULL DEFAULT 0.5,      -- 0.0 to 1.0
    description     TEXT,                           -- LLM-generated explanation
    created_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE (source_file_id, target_file_id, relationship)
);

-- Search synonyms (LLM-generated + user overrides)
CREATE TABLE synonyms (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    term            TEXT NOT NULL,
    synonyms        TEXT[] NOT NULL,                -- ['host', 'node', 'instance']
    source          TEXT DEFAULT 'llm',             -- 'llm' or 'user'
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE (term, source)
);

-- Anomaly detection results
CREATE TABLE anomalies (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    schema_id       UUID REFERENCES schemas(id),
    anomaly_type    TEXT NOT NULL,                  -- 'schema_outlier', 'value_outlier', 'credential_exposure', etc.
    severity        TEXT NOT NULL,                  -- 'critical', 'high', 'medium', 'low', 'info'
    description     TEXT NOT NULL,                  -- what's unusual
    details         JSONB,                          -- {"extra_fields": ["password"], "expected": "..."}
    llm_assessment  TEXT,                           -- LLM explanation (null if not yet reviewed)
    status          TEXT DEFAULT 'open',            -- 'open', 'acknowledged', 'dismissed', 'resolved'
    created_at      TIMESTAMPTZ DEFAULT now(),
    resolved_at     TIMESTAMPTZ
);

-- Audit logging
CREATE TABLE audit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         TEXT,                           -- API key identifier or 'system'
    action          TEXT NOT NULL,                  -- 'search', 'download', 'upload', 'delete', 'index'
    resource_type   TEXT NOT NULL,                  -- 'file', 'schema', 'search'
    resource_id     UUID,
    metadata        JSONB,                          -- e.g. {"query": "...", "results": 42}
    ip_address      INET,
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- LLM job tracking
CREATE TABLE llm_jobs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID REFERENCES files(id) ON DELETE CASCADE,
    chunk_id        UUID REFERENCES chunks(id) ON DELETE CASCADE,
    job_type        TEXT NOT NULL,                  -- 'embedding', 'summary', 'classification', 'entity_extraction', 'relationship', 'anomaly_review', 'synonym_generation'
    status          TEXT NOT NULL DEFAULT 'pending',-- 'pending', 'processing', 'done', 'failed'
    engine          TEXT NOT NULL,                  -- 'nomic-embed', 'pegasus', 'max', 'stella'
    attempts        INTEGER DEFAULT 0,
    error_message   TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_files_sha256 ON files(sha256);
CREATE INDEX idx_files_status ON files(status);
CREATE INDEX idx_files_mime ON files(mime);
CREATE INDEX idx_files_user_tags ON files USING GIN (user_tags);
CREATE INDEX idx_files_ai_tags ON files USING GIN (ai_tags);
CREATE INDEX idx_files_metadata ON files USING GIN (metadata);
CREATE INDEX idx_file_paths_nas ON file_paths(nas_path);
CREATE INDEX idx_file_paths_file ON file_paths(file_id);
CREATE INDEX idx_chunks_file ON chunks(file_id);
CREATE INDEX idx_chunks_embedding ON chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_extracted_path ON extracted_fields(field_path, file_id);
CREATE INDEX idx_extracted_value ON extracted_fields(field_path, value_text);
CREATE INDEX idx_schemas_hash ON schemas(schema_hash);
CREATE INDEX idx_audit_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id, created_at);
CREATE INDEX idx_llm_jobs_status ON llm_jobs(status, job_type);
CREATE INDEX idx_entities_type_value ON entities(entity_type, normalized);
CREATE INDEX idx_entities_file ON entities(file_id);
CREATE INDEX idx_entities_value ON entities(normalized);
CREATE INDEX idx_relationships_source ON file_relationships(source_file_id);
CREATE INDEX idx_relationships_target ON file_relationships(target_file_id);
CREATE INDEX idx_relationships_type ON file_relationships(relationship);
CREATE INDEX idx_anomalies_file ON anomalies(file_id);
CREATE INDEX idx_anomalies_severity ON anomalies(severity, status);
CREATE INDEX idx_synonyms_term ON synonyms(term);
```

### 5.3 Meilisearch Index

```json
{
  "uid": "chunks",
  "primaryKey": "id",
  "searchableAttributes": [
    "content",
    "file_name",
    "ai_summary",
    "user_tags",
    "ai_tags",
    "entities"
  ],
  "filterableAttributes": [
    "file_id",
    "mime",
    "user_tags",
    "ai_tags",
    "schema_id",
    "size",
    "indexed_at",
    "status"
  ],
  "sortableAttributes": [
    "indexed_at",
    "size",
    "file_name"
  ],
  "distinctAttribute": "file_id",
  "faceting": {
    "maxValuesPerFacet": 100
  },
  "pagination": {
    "maxTotalHits": 10000
  },
  "typoTolerance": {
    "enabled": true,
    "minWordSizeForTypos": {
      "oneTypo": 4,
      "twoTypos": 8
    }
  }
}
```

Note: `distinctAttribute: "file_id"` ensures search results are deduplicated by file
(returns the best-matching chunk per file).

### 5.4 OpenSearch Mapping (Tier 3)

```json
{
  "mappings": {
    "properties": {
      "chunk_id": {"type": "keyword"},
      "file_id": {"type": "keyword"},
      "chunk_index": {"type": "integer"},
      "content": {
        "type": "text",
        "analyzer": "standard",
        "fields": {
          "keyword": {"type": "keyword"},
          "ngrams": {"type": "text", "analyzer": "edge_ngram_analyzer"}
        }
      },
      "file_name": {"type": "text", "fields": {"keyword": {"type": "keyword"}}},
      "ai_summary": {"type": "text"},
      "ai_tags": {"type": "keyword"},
      "user_tags": {"type": "keyword"},
      "json_fields": {"type": "object", "dynamic": true},
      "xml_fields": {"type": "object", "dynamic": true},
      "embedding": {
        "type": "knn_vector",
        "dimension": 768,
        "method": {"name": "hnsw", "space_type": "cosinesimil", "engine": "nmslib"}
      },
      "indexed_at": {"type": "date"},
      "size": {"type": "long"},
      "mime": {"type": "keyword"}
    }
  },
  "settings": {
    "analysis": {
      "analyzer": {
        "edge_ngram_analyzer": {
          "tokenizer": "edge_ngram_tokenizer",
          "filter": ["lowercase"]
        }
      },
      "tokenizer": {
        "edge_ngram_tokenizer": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 10,
          "token_chars": ["letter", "digit"]
        }
      }
    }
  }
}
```

---

## 6. Scaling Strategy

### 6.1 Tier Transition Triggers

| Metric | Tier 1 → 2 | Tier 2 → 3 |
|--------|-----------|-----------|
| **Indexed files** | > 500K | > 5M |
| **Concurrent clients** | > 20 | > 100 |
| **Search QPS** | > 50 | > 500 |
| **NAS availability requirements** | > 99% uptime needed | > 99.9% uptime needed |

### 6.2 Search Engine Migration (Meilisearch → OpenSearch)

Zero-downtime switchover at Tier 2→3 boundary:

1. **Deploy OpenSearch** alongside Meilisearch
2. **Dual-write**: Index writer sends documents to both engines
3. **Backfill**: Run re-indexer to populate OpenSearch with existing documents
4. **Verify**: Compare search results from both engines for a sample of queries
5. **Feature flag**: `SEARCH_ENGINE=meilisearch` → `SEARCH_ENGINE=opensearch`
6. **Cutover**: Flip flag, monitor error rates for 24h
7. **Rollback**: If OpenSearch error rate > 5%, flip flag back
8. **Decommission**: After 7 days stable, remove Meilisearch

### 6.3 NAS Bandwidth

| NAS Link | Throughput | Files/min (avg 50 KB) | Tier |
|----------|------------|----------------------|------|
| 1 GbE | ~110 MB/s | ~2,200 | Tier 1 |
| 2.5 GbE | ~280 MB/s | ~5,600 | Tier 2 |
| 10 GbE | ~1.1 GB/s | ~22,000 | Tier 3 |

At Tier 2+, MinIO caching reduces NAS read load by 80-90% for download operations.

---

## 7. Security

### 7.1 Tier 1 (MVP)

| Layer | Approach |
|-------|----------|
| **Transport** | Caddy auto-TLS |
| **Authentication** | API keys (`Authorization: Bearer <key>`), bcrypt-hashed in PostgreSQL |
| **Authorization** | RBAC: `admin`, `editor` (read + upload + tag), `reader` (read only) |
| **Rate Limiting** | Caddy rate limit per IP; configurable per API key |
| **NAS Mount** | `nosuid,nodev,noexec` for read path; separate writable mount for uploads |
| **Input Validation** | Rust serde deserialization (type-safe at boundary) |
| **Secrets** | Environment variables via `.env` file (not committed to Git) |
| **Audit** | All API requests logged to `audit_logs` table |

### 7.2 Tier 2

| Addition | Details |
|----------|---------|
| **Secrets** | Sealed Secrets or SOPS (encrypted in Git, decrypted in cluster) |
| **MCP Auth** | API key passed in MCP connection env or SSE header |
| **Signed Downloads** | HMAC-signed URLs with 15-minute expiry |
| **ClamAV** | Optional upload scanning (recommended if accepting untrusted files) |

### 7.3 Tier 3

| Addition | Details |
|----------|---------|
| **Secrets** | HashiCorp Vault (full lifecycle management) |
| **Identity** | Keycloak OIDC + OPA fine-grained policies |
| **File ACLs** | Per-file owner/group/permission in PostgreSQL, enforced by OPA |
| **mTLS** | Istio/Linkerd for all inter-service communication |
| **Encryption at Rest** | MinIO SSE-S3, PostgreSQL TDE |

---

## 8. Deployment

### 8.1 Docker Compose (Tier 1)

```yaml
services:
  siss:
    image: ghcr.io/your-org/siss:latest
    ports:
      - "8080:8080"
      - "3000:3000"
    environment:
      DATABASE_URL: postgres://siss:${POSTGRES_PASSWORD}@postgres:5432/siss
      MEILI_URL: http://meilisearch:7700
      MEILI_MASTER_KEY: ${MEILI_MASTER_KEY}
      NAS_ROOT: /mnt/nas/data
      NAS_UPLOAD_ROOT: /mnt/nas/uploads
      EMBEDDING_URL: http://stella.home.arpa:8001
      PEGASUS_URL: http://pegasus.home.arpa:8000
      MAX_URL: http://max.home.arpa:8080
      STELLA_URL: http://stella.home.arpa:8000
      LLM_ENABLED: "true"
      MAX_FILE_SIZE_MB: "100"
    volumes:
      - nas-data:/mnt/nas/data:ro
      - nas-uploads:/mnt/nas/uploads:rw
    healthcheck:
      test: ["CMD", "/usr/local/bin/siss", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      meilisearch:
        condition: service_healthy

  postgres:
    image: pgvector/pgvector:pg17
    environment:
      POSTGRES_DB: siss
      POSTGRES_USER: siss
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--data-checksums"
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U siss"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  meilisearch:
    image: getmeili/meilisearch:v1.13
    environment:
      MEILI_MASTER_KEY: ${MEILI_MASTER_KEY}
      MEILI_ENV: production
    volumes:
      - meili-data:/meili_data
    ports:
      - "7700:7700"
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:7700/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
    restart: unless-stopped

volumes:
  pgdata:
  meili-data:
  caddy-data:
  nas-data:
    driver: local
    driver_opts:
      type: nfs4
      o: addr=flashstore.home.arpa,ro,hard,intr,noatime,nofail,rsize=1048576,wsize=1048576
      device: ":/volume1/data"
  nas-uploads:
    driver: local
    driver_opts:
      type: nfs4
      o: addr=flashstore.home.arpa,rw,hard,intr,noatime,nofail,rsize=1048576,wsize=1048576
      device: ":/volume1/uploads"
```

**Caddyfile:**

```
siss.home.arpa {
    reverse_proxy /api/* siss:8080
    reverse_proxy /mcp/* siss:3000
    reverse_proxy /metrics siss:8080

    rate_limit {
        zone api {
            key {remote_host}
            events 100
            window 1m
        }
    }

    log {
        output file /var/log/caddy/access.log
        format json
    }
}
```

### 8.2 Synology DSM Direct

Run directly on the NAS using Container Manager:
- No NFS needed (bind-mount `/volume1/data` directly)
- Eliminates network bottleneck for Tier 1
- Constraints: limited CPU (typically ARM or Celeron)

### 8.3 K3s (Tier 2)

```bash
helm install siss ./charts/siss \
  --set replicas.api=2 \
  --set replicas.ingestor=2 \
  --set nats.enabled=true \
  --set redis.enabled=true \
  --set minio.enabled=true \
  --set nas.server=flashstore.home.arpa \
  --set nas.path=/volume1/data
```

---

## 9. Observability & Operations

### 9.1 Metrics (Prometheus)

| Metric | Type | Description |
|--------|------|-------------|
| `siss_files_indexed_total` | Counter | Total files indexed |
| `siss_files_failed_total` | Counter | Failed indexing attempts |
| `siss_search_duration_seconds` | Histogram | Search request latency |
| `siss_search_requests_total` | Counter | Search requests by type (text/semantic/hybrid) |
| `siss_ingest_queue_depth` | Gauge | Files waiting to be indexed |
| `siss_llm_requests_total` | Counter | LLM API calls by engine and type |
| `siss_llm_errors_total` | Counter | LLM API errors by engine |
| `siss_llm_duration_seconds` | Histogram | LLM call latency |
| `siss_nas_available` | Gauge | NAS mount reachable (1/0) |
| `siss_nas_latency_seconds` | Histogram | NAS read latency |
| `siss_chunks_total` | Gauge | Total content chunks in index |
| `siss_embeddings_total` | Gauge | Chunks with embeddings |

### 9.2 Structured Logging

JSON logs with correlation IDs:

```json
{
  "timestamp": "2026-02-12T10:30:00Z",
  "level": "info",
  "message": "file indexed",
  "trace_id": "abc123",
  "request_id": "req-456",
  "file_id": "f47ac10b-...",
  "chunks": 3,
  "duration_ms": 450,
  "llm_queued": true
}
```

Tier 1: Log to file (stdout for Docker). Tier 2+: Ship to Loki.

### 9.3 Health Checks

| Endpoint | Checks | Use |
|----------|--------|-----|
| `GET /healthz` | Process alive | Kubernetes liveness probe |
| `GET /readyz` | PostgreSQL + Meilisearch connected, NAS mounted | Kubernetes readiness probe |
| `GET /readyz?verbose=true` | Per-component status with latency | Debugging |

### 9.4 Maintenance Runbooks

| Task | Schedule | Procedure |
|------|----------|-----------|
| **PostgreSQL VACUUM** | Weekly | `VACUUM ANALYZE chunks, extracted_fields, audit_logs;` |
| **Meilisearch snapshot** | Daily | `POST /snapshots` → copy to backup location |
| **Integrity scan** | Weekly | Re-hash random 1% of indexed files, compare to stored SHA-256 |
| **Audit log rotation** | Monthly | Archive logs older than 90 days to compressed JSON |
| **LLM job cleanup** | Daily | Delete `completed` jobs older than 7 days |
| **Dead file detection** | Daily | Check `file_paths.last_seen_at` — flag files not seen in last scan |

### 9.5 Backup Strategy

| Component | Method | Schedule | Retention |
|-----------|--------|----------|-----------|
| **PostgreSQL** | `pg_dump` + WAL archiving | Daily full + continuous WAL | 30 days |
| **Meilisearch** | Snapshots to NAS backup volume | Daily | 7 days |
| **Config** | Git (Docker Compose, Caddyfile, Helm values) | On change | Unlimited |
| **NAS data** | User's existing Synology backup strategy | n/a | n/a |

---

## 10. Performance Targets

| Metric | Tier 1 | Tier 2 | Tier 3 |
|--------|--------|--------|--------|
| **Index capacity** | 500K-1M files | 5M files | 50M+ files |
| **Search latency (p95)** | < 50 ms | < 100 ms | < 200 ms |
| **Semantic search latency (p95)** | < 100 ms | < 150 ms | < 250 ms |
| **Ingestion (no LLMs)** | 200-500 files/min | 2K files/min | 20K files/min |
| **Ingestion (with LLMs)** | 50-100 files/min | 500 files/min | 5K files/min |
| **Concurrent clients** | 20 | 100 | 1K+ |
| **Search QPS** | 50 | 500 | 5K+ |
| **Upload throughput** | 100 MB/min | 1 GB/min | 5 GB/min |
| **Embedding throughput** | ~200 chunks/min | ~1K chunks/min | ~5K chunks/min |
| **Memory (total stack)** | < 2 GB | < 8 GB | < 64 GB |

---

## 11. Edge Cases

| Scenario | Handling |
|----------|----------|
| **Case-insensitive NAS (SMB)** | Normalize all paths to lowercase before storing in `file_paths`. Detect case conflicts and log warning. |
| **Unicode normalization** | Normalize filenames to NFC form before hashing path. Store original and normalized forms. |
| **Symlinks** | Follow symlinks by default. Detect cycles via inode tracking. Configurable: `follow_symlinks: true/false`. |
| **File modified during indexing** | Lock-free: hash file, index it. On completion, re-check mtime. If changed during processing, re-queue. |
| **NAS unreachable** | Search continues (local index). Downloads return 503. Ingestion pauses and retries on 60s interval. |
| **Oversized files (> max_file_size)** | Index metadata only (`status: 'metadata_only'`). No content parsing, no chunking, no embedding. Searchable by name, size, path, tags. |
| **Binary files misnamed as .json/.xml** | Content detection uses magic bytes, not extension. Binary content detected → index as metadata only. |
| **Empty files** | Index metadata. Set `status: 'indexed'`, `chunk_count: 0`. |
| **Deeply nested JSON/XML** | Limit parsing depth to 32 levels (configurable). Truncate extracted fields beyond limit. |

---

## 12. Implementation Roadmap

### Phase 0: Foundation (1 week)
- Cargo workspace: `siss-core`, `siss-api`, `siss-mcp`, `siss-ingest`
- Docker Compose with PostgreSQL + Meilisearch + Caddy
- Health check endpoints (`/healthz`, `/readyz`, `/metrics`)
- Structured logging with `tracing`

### Phase 1: Core Ingestion + Search (3 weeks)
- NAS file watcher (inotify + periodic scan)
- SHA-256 dedup pipeline with mtime fast-path
- Parsers: ASCII, JSON, XML (serde_json, quick-xml)
- Content chunking engine
- Schema inference and registry
- Meilisearch chunk indexing
- `GET /search?q=` and `GET /files/{id}`
- **Milestone: search your NAS from a browser**

### Phase 2: Full REST API + Structured Queries (2 weeks)
- Complete CRUD (upload, delete, update metadata)
- JSONPath query engine (`jsonpath-rust`)
- XPath query engine (`sxd-xpath`)
- Faceted search, cursor pagination
- Batch upload (async, 202 Accepted)
- OpenAPI spec (utoipa + swagger-ui)

### Phase 3: MCP Server (2 weeks)
- MCP implementation (`rmcp` crate, stdio + SSE)
- All 12 tools from Section 4.2
- Resources and prompts
- Integration testing with Claude Desktop and Claude Code
- **Milestone: AI agents can search your NAS**

### Phase 4: LLM Integration — Embeddings + Summarization (2 weeks)
- Embedding model deployment (nomic-embed-text-v1.5 on Stella)
- Embedding pipeline: chunk → embed → pgvector
- Semantic search endpoint
- Hybrid search with RRF re-ranking
- Summarization queue (Pegasus for analysis, Max for large docs)
- LLM health monitoring with retry/backoff
- **Milestone: semantic search works**

### Phase 5: LLM Intelligence — Entities, Relationships, Anomalies (3 weeks)
- Regex-based entity extraction (IPs, URLs, emails, hostnames) — runs on every file, no LLM needed
- LLM-based entity extraction via Stella (contextual entities, classifications)
- Entity search API (`/entities`, `/entities/{type}/{value}/files`)
- Cross-file relationship builder (entity co-occurrence, shared schema detection)
- Relationship API (`/files/{id}/related`, `/relationships`)
- Anomaly detection engine (schema outlier, credential exposure, value outlier)
- Anomaly API (`/anomalies`, `/files/{id}/anomalies`)
- MCP tools: `search_entities`, `find_related_files`, `get_anomalies`, `explore_entity_graph`
- **Milestone: "show me every file that references db-prod-01" works**

### Phase 6: Search Enhancement — Synonyms + Polish (2 weeks)
- Corpus-driven synonym generation via Pegasus
- Synonym API (`/synonyms`) with user overrides
- Push synonyms to Meilisearch configuration
- API key auth with RBAC
- Audit logging
- Prometheus metrics
- Caddy TLS + rate limiting
- CLI tool (`siss cli scan`, `siss cli stats`, `siss cli search`, `siss cli entities`)
- Backup procedures
- **Milestone: v1.0.0 release**

### Phase 7: Scale (as needed, 4-6 weeks)
- NATS JetStream for event bus + job queue
- Redis caching
- MinIO read-through cache
- K3s Helm charts
- Horizontal scaling
- Load testing with k6

**Total to MVP (searchable NAS): ~4 weeks.**
**Total to semantic search: ~8 weeks.**
**Total to v1.0.0 (full intelligence + auth): ~14 weeks.**
**Total to Tier 2 (scaled): ~18-20 weeks.**

---

## 13. Rust Dependencies

| Crate | Purpose |
|-------|---------|
| `axum` + `axum-extra` | HTTP framework, streaming responses |
| `rmcp` | MCP server (JSON-RPC 2.0, stdio + SSE) |
| `serde` + `serde_json` | JSON serialization |
| `quick-xml` | XML parsing (SAX-style streaming + serde) |
| `sqlx` | Async PostgreSQL with compile-time query checks |
| `pgvector` | pgvector column type for sqlx |
| `meilisearch-sdk` | Meilisearch client |
| `jsonpath-rust` | JSONPath evaluation |
| `sxd-xpath` + `sxd-document` | XPath evaluation |
| `notify` | Filesystem watcher (inotify) |
| `sha2` | SHA-256 hashing |
| `tokio` | Async runtime |
| `tower` + `tower-http` | Middleware (auth, rate limit, tracing, CORS) |
| `utoipa` + `utoipa-swagger-ui` | OpenAPI spec generation |
| `tracing` + `tracing-subscriber` | Structured logging |
| `tracing-opentelemetry` | OpenTelemetry integration (Tier 2+) |
| `reqwest` | HTTP client for LLM APIs |
| `metrics` + `metrics-exporter-prometheus` | Prometheus metrics |
| `regex` | Entity extraction patterns (IPs, URLs, emails, credentials) |
| `petgraph` | In-memory graph traversal for relationship exploration |
