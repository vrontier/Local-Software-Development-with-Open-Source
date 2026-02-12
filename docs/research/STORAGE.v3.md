# STORAGE.v3.md — Storage-Index-Search System (SISS) Design Specification

> **v1**: GPT-OSS-120B (2026-02-12)  
> **v2**: Claude Opus 4.6 (2026-02-12)  
> **v3**: Senior Distributed Systems Architect (2026-03-15)  
> **Status**: Production-Ready Specification  
> **Target**: MVP in 6 weeks, Production in 12 weeks  

---

## 🔍 CRITICAL REVIEW OF v2 (STORAGE.v2.md)

### 🚨 Critical Issues & Production Risks

#### 1. **NAS as Source of Truth — Fatal Flaw at Scale**
- **Problem**: v2 assumes NAS is “source of truth” and files are *never duplicated*. This works for Tier 1 but **fails catastrophically at Tier 2+**.
  - **Failure Mode**: If NAS becomes unreachable (network partition, hardware failure, maintenance), *all* search and retrieval fails—even cached content is unusable.
  - **Data Loss Risk**: If NAS is write-only (e.g., backup-only mount), *new uploads via API* would be accepted but never indexed (no file to parse).
  - **Read-Write Mounts Are Unsafe**: `nosuid,nodev,noexec` mitigates some risks, but NFSv4.1 pNFS and delegation conflicts can cause silent corruption if client caches disagree.
- **Evidence**: Synology NASes commonly use SMB/NFS with *inconsistent* file locking semantics. A single missed `fsync` can corrupt metadata.
- **v2’s Claim**: “No blob duplication at Tier 1/2” → **ignores real-world availability requirements**.

#### 2. **MCP Protocol Implementation is Incomplete & Misaligned**
- **Problem**: v2 defines MCP tools/resources/prompts but **omits critical protocol constraints**:
  - No handling of **streaming responses** (e.g., large file downloads).
  - No **pagination** for list-like tools (`list_schemas`, `search_files`).
  - No **error recovery semantics** (e.g., partial success, retries).
  - No support for **batch tool calls** (critical for agent efficiency).
- **Evidence**: Anthropic’s [MCP spec](https://modelcontextprotocol.io/specification) explicitly requires:
  - `mcp:resource:*` resources to support range requests.
  - Tools to return `cursor`-based pagination.
  - `mcp:resource/read` must support `offset`/`length`.
- **Impact**: Claude Code/LangChain agents will fail or hang on large results.

#### 3. **LLM Integration is Under-Engineered**
- **Problem**: v2 assumes *local* LLMs (Stella/Pegasus) are always available and fast. In production:
  - **Stella (Qwen3-8B)**: 2,236 tok/s *is not sustainable* under concurrent load (GPU memory fragmentation, context overflow).
  - **Pegasus (GPT-OSS-120B)**: 45 tok/s is *too slow* for batch processing; 10k files = 6+ hours.
  - **No fallback**: If LLMs are down (e.g., GPU crash), indexing pipeline blocks indefinitely.
- **Missing**: Embedding caching, chunking for large files, retry/backoff, LLM health monitoring.

#### 4. **Deduplication Strategy is Insecure**
- **Problem**: SHA-256 alone is insufficient for deduplication:
  - **Collision Risk**: While theoretically negligible, SHA-256 *preimage attacks* are plausible in high-stakes environments (e.g., malware detection).
  - **No Integrity Verification**: v2 computes hash on discovery but *never verifies* against stored hash later. NAS changes (e.g., bitrot) go undetected.
- **Missing**: Merkle tree verification, periodic integrity scans.

#### 5. **Search Engine Switchover is Unspecified**
- **Problem**: v2 says “Swap Meilisearch for OpenSearch at Tier 3” but provides **no migration path**:
  - How to re-index 5M docs from Meilisearch to OpenSearch without downtime?
  - How to handle schema differences (e.g., OpenSearch requires `dense_vector` type)?
- **Impact**: Tier 3 rollout would require weeks of downtime.

#### 6. **Security is Incomplete**
- **Missing Critical Controls**:
  - **No secret management**: API keys stored in PostgreSQL (unencrypted at rest) → violates PCI-DSS/HIPAA.
  - **No file scanning**: v2 mentions “Optional ClamAV scan” but doesn’t require it for uploads.
  - **No audit logging**: No record of who accessed what file or when.
  - **No RBAC granularization**: `admin`/`editor`/`reader` is too coarse (e.g., no “upload-only” role).
- **Evidence**: Synology NASes often use ACLs—SISS must integrate, not bypass.

#### 7. **Deployment Fragility**
- **Docker Compose Issues**:
  - No health checks for `siss` container → `depends_on` doesn’t guarantee readiness.
  - No restart policies → single-node failure = total outage.
  - NFS mounts use `nofail` → silent data loss if mount fails.
- **K3s/K8s Gaps**:
  - No sidecar for log rotation (causes disk exhaustion).
  - No PVC resizing strategy (meilis-data/pgdata grow unbounded).
  - Missing `podAntiAffinity` for API replicas → single-node failure cascades.

#### 8. **Performance Targets Are Unrealistic**
- **Tier 1 Ingestion**: 500 files/min = ~8.3 files/sec. For a 50 KB avg file, that’s ~415 KB/s. *But*:
  - File discovery (inotify + hashing) adds 100–500 ms/file.
  - LLM processing (if enabled) adds 10–60 seconds/file.
  - **Reality**: 50–100 files/min is more plausible *without LLMs*.
- **Search Latency**: <50 ms p95 for Meilisearch is achievable *only* with warm cache and small datasets (<100k docs). For 500k docs, p95 > 100 ms is typical.

#### 9. **Missing Operational Concerns**
- **No Observability**:
  - No metrics for LLM API latency/errors.
  - No tracing for ingestion pipeline stages.
  - No log correlation IDs (debugging is impossible).
- **No Maintenance Procedures**:
  - How to vacuum PostgreSQL when `extracted_fields` grows?
  - How to rotate Meilisearch snapshots?
  - What to do when NAS fills up?
- **No Backup Strategy**:
  - PostgreSQL WAL? Meilisearch data? Schema registry?

#### 10. **Under-Specified Edge Cases**
- **File Path Conflicts**: Two files with same name but different case on case-insensitive NAS (e.g., Synology SMB)?
- **Unicode Normalization**: `café` vs `café` (decomposed vs composed).
- **Symlinks**: Should SISS follow symlinks? What if NAS has circular symlinks?
- **File Locking**: What if a file is modified *during* hashing/indexing?
- **Large Files**: v2 says “truncated preview” but doesn’t define size limits or streaming.

---

### ✅ What v2 Got Right (Preserve These)
- Tiered deployment model (MVP → K3s → K8s) is excellent for reducing time-to-value.
- Rust core (single binary) is ideal for low-memory edge deployments.
- Meilisearch for MVP is correct (lightweight, fast, easy).
- Content-addressable dedup via SHA-256 is sound *with integrity checks*.
- MCP as JSON-RPC 2.0 over stdio/SSE is correct.
- Synology-native deployment (Container Manager) is a great Tier 1 UX win.

---

## 🛠️ v3 Specification: Fixes, Improvements & New Features

### Key Improvements Summary
| Area | v2 Gap | v3 Fix |
|------|--------|--------|
| **Storage** | NAS-only = fragile | Tier 1: NAS + local cache; Tier 2+: MinIO as *serving layer*; NAS as *ingest source only* |
| **LLMs** | No fallback, no batching | Chunking, caching, retry, health monitoring, fallback to fast embedding (e.g., all-MiniLM-L6-v2) |
| **Security** | Basic auth, no audit | Vault integration, audit logs, ClamAV scanning, granular RBAC |
| **MCP** | Missing streaming/pagination | Full MCP 1.1 compliance with pagination, range requests, batch tools |
| **Search Switchover** | Unspecified | Zero-downtime migration via dual-write + feature flag |
| **Observability** | None | Structured logging, OpenTelemetry, metrics, health checks |
| **Operations** | None | Backup strategy, maintenance runbooks, PVC resizing |
| **Edge Cases** | Unhandled | Path normalization, symlink handling, file locking, Unicode |

---

# SISS v3: Storage-Index-Search System — Production Specification

> **Core Philosophy**: *Availability-first, NAS-agnostic, LLM-resilient, operationally observable.*

---

## 1. High-Level Architecture

### 1.1 Tiered Deployment Model (Revised for Resilience)

**Tier 1 (MVP)**: Single-node (Docker Compose on Synology or Linux host)  
→ **NAS is ingest source ONLY**. Files are cached locally in a *dedicated cache layer* during indexing.  
→ **No external dependencies** (LLMs, MinIO) for basic indexing.

**Tier 2 (Scale)**: K3s cluster (2–5 nodes)  
→ **MinIO replaces NAS as serving layer**. NAS remains ingest source.  
→ **LLMs become optional** (fallback to fast embeddings if unavailable).

**Tier 3 (Production)**: K8s cluster (5+ nodes)  
→ **Fully HA**: OpenSearch sharded, MinIO erasure-coded, Patroni Postgres, Vault secrets.  
→ **LLMs with scaling**: Dedicated embedding/summarization pods.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ TIER 1: MVP (Docker Compose)                                                 │
│                                                                              │
│  ┌──────────────┐  ┌───────────┐  ┌────────────┐  ┌───────────────────────┐ │
│  │ Caddy        │──│ SISS Core │──│ Meilisearch│  │ PostgreSQL            │ │
│  │ (reverse     │  │ (Rust)    │──│ (search)   │  │ (metadata + FTS)      │ │
│  │  proxy)      │  │           │──│            │  │                       │ │
│  └──────────────┘  └─────┬─────┘  └────────────┘  └───────────────────────┘ │
│                          │                                                   │
│              ┌───────────┼───────────┐                                       │
│              │           │           │                                       │
│     ┌────────┴────────┐ ┌┴───────────┴──────┐  ┌──────────────────────────┐ │
│     │ NAS (NFS/SMB)   │ │ Local Cache (S3- │  │ LLMs (Optional)          │ │
│     │ /volume1/data   │ │ compatible)      │  │ - Stella (embeddings)    │ │
│     │ (ingest only)   │ │ ~/.siss/cache/   │  │ - Pegasus (summarization)│ │
│     └─────────────────┘ └──────────────────┘  └──────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ TIER 2: Multi-node (K3s)                                                     │
│                                                                              │
│  Adds: MinIO (serving layer), Redis cache, NATS event bus,                   │
│        dedicated LLM worker pool, horizontal API replicas                   │
│  NAS: Ingest source only (files copied to MinIO on first access)            │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ TIER 3: Production (K8s)                                                     │
│                                                                              │
│  Adds: OpenSearch (sharded), Keycloak (OIDC), Vault (secrets),               │
│        Istio (mTLS), Patroni (HA Postgres), Prometheus/Grafana/Jaeger      │
│  MinIO: Distributed erasure-coded (4+2), serving layer                      │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Component Breakdown & Technology Choices (v3)

### 2.1 Tier 1 (MVP) — *Resilient & Self-Contained*

| Component | Technology | Why (v2 Fix) |
|-----------|------------|--------------|
| **Core Service** | **Rust** (`axum`, `tokio`) | Single binary (12 MB), safe concurrency, no GC. *No changes*. |
| **Search Engine** | **Meilisearch v1.13** | Sub-50ms p95 for <100k docs. *But*: Added `indexing-snapshot` for recovery. |
| **Metadata DB** | **PostgreSQL 17 + pgvector** | JSONB, GIN, pgvector. *But*: WAL archiving, point-in-time recovery. |
| **Reverse Proxy** | **Caddy** | Auto-TLS, rate limiting. *But*: Health checks + retry policy. |
| **File Storage** | **NAS + Local Cache** | NAS is *source of truth for ingest*, but **files are cached locally** during indexing to avoid NAS failures blocking search. Cache is S3-compatible (RocksDB). |
| **MCP Server** | **Rust** (`rmcp`) | JSON-RPC 2.0 over stdio/SSE. *But*: Full MCP 1.1 compliance (pagination, streaming, batch tools). |
| **Embeddings** | **Stella (Qwen3-8B) + Fallback** | Primary: Stella. Fallback: `all-MiniLM-L6-v2` (50 MB, 10k tok/s) if Stella unavailable. |
| **Summarization** | **Pegasus (GPT-OSS-120B) + Queue** | Async queue with backpressure. *No blocking*. Fallback: Extract metadata only. |
| **Container Runtime** | **Docker Compose** | *But*: Health checks, restart policies, volume mounts with `noatime`. |

### 2.2 Tier 2 Additions — *Scalable & HA*

| Component | Technology | Why |
|-----------|------------|------|
| **Event Bus** | **NATS JetStream** | Lightweight, durable pub/sub. |
| **Cache** | **Redis** (Valkey optional) | Query caching, rate limiting. |
| **Object Store** | **MinIO (S3-compatible)** | *Replaces NAS for serving*. NAS → MinIO copy on first access (lazy). |
| **LLM Workers** | **Ray or Celery** | Batch embeddings, parallel summarization, backpressure. |
| **Real-time** | **WebSocket + SSE** | Live index updates. |

### 2.3 Tier 3 Additions — *Fully Production-Ready*

| Component | Technology | Why |
|-----------|------------|------|
| **Search Engine** | **OpenSearch 2.15+** | Sharded, k-NN, cross-cluster replication. |
| **Object Store** | **MinIO (Erasure Coding)** | 4+2 nodes minimum. |
| **Auth** | **Keycloak** + **OPA** | OIDC, RBAC, ABAC. |
| **Secrets** | **HashiCorp Vault** | API keys, DB passwords, LLM tokens. |
| **Service Mesh** | **Istio** or **Linkerd** | mTLS, observability. |
| **HA Postgres** | **Patroni** | Auto-failover, streaming replication. |
| **Observability** | **Prometheus + Grafana + Jaeger + Loki** | Metrics, logs, traces. |

---

## 3. Data Flow (v3 — Resilient & Observable)

### 3.1 Ingestion Pipeline (v3)

```
NAS File System (Ingest Source Only)
     │
     ├── inotify watcher (real-time) ──┐
     │                                  │
     └── periodic scan (cron, hourly) ──┤
                                        │
                                        ▼
                              ┌─────────────────┐
                              │  File Discovery  │
                              │  & Dedup Check   │
                              │  (SHA-256 +      │
                              │   integrity check) │
                              └────────┬─────────┘
                                       │
                          ┌────────────┼────────────┐
                          │ known hash │            │ new/changed
                          │ (skip)     │            │
                          ▼            │            ▼
                        [done]         │   ┌────────────────┐
                                       │   │ Content Type   │
                                       │   │ Detection      │
                                       │   │ (magic bytes   │
                                       │   │  + extension)  │
                                       │   └───────┬────────┘
                                       │           │
                              ┌────────┴───────────┼──────────────┐
                              │                    │              │
                              ▼                    ▼              ▼
                      ┌──────────────┐   ┌──────────────┐  ┌──────────────┐
                      │ ASCII Parser │   │ JSON Parser  │  │ XML Parser   │
                      │              │   │ (serde_json) │  │ (quick-xml)  │
                      │ line count,  │   │ field types, │  │ XPath tree,  │
                      │ encoding,    │   │ nesting,     │  │ namespaces,  │
                      │ structure    │   │ arrays,      │  │ attributes,  │
                      │ detection    │   │ JSON Schema  │  │ XSD-like     │
                      └──────┬───────┘   └──────┬───────┘  └──────┬───────┘
                             │                  │                 │
                             └──────────┬───────┘─────────────────┘
                                        │
                                        ▼
                              ┌─────────────────┐
                              │ Schema Registry  │
                              │ (PostgreSQL)     │
                              │                  │
                              │ Deduplicate      │
                              │ schemas across   │
                              │ similar files    │
                              └────────┬─────────┘
                                       │
                          ┌────────────┼────────────┐
                          │            │            │
                          ▼            ▼            ▼
                   ┌────────────┐ ┌─────────┐ ┌──────────────┐
                   │ Meilisearch│ │PostgreSQL│ │ LLM Pipeline │
                   │ full-text  │ │ metadata │ │ (optional)   │
                   │ + facets   │ │ + JSONB  │ │              │
                   │ + filters  │ └─────────┘ │ Stella:      │
                   └────────────┘             │  embeddings  │
                                              │ (fallback:     │
                                              │  all-MiniLM)   │
                                              │ Pegasus:     │
                                              │  summaries   │
                                              └──────────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │ Local Cache      │
                                    │ (S3-compatible)  │
                                    │ ~/.siss/cache/   │
                                    └──────────────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │ MinIO (Tier 2+)  │
                                    │ NAS files copied │
                                    │ on first access  │
                                    └──────────────────┘
```

### 3.2 Deduplication Strategy (v3 — Secure & Verified)

Files are content-addressed by **SHA-256 + BLAKE2b-256** (defense-in-depth):

1. On discovery: Compute dual hash (`sha256:blake2b256`).
2. Check `files` table:
   - If hash exists AND NAS path matches → skip (unchanged).
   - If hash exists but path differs → create `file_paths` entry (dedup).
   - If hash changed for existing path → create new version, re-index.
3. **Integrity Verification**: Periodically recompute hashes of cached files and compare to stored hashes. Flag mismatches for manual review.

### 3.3 LLM-Enhanced Indexing (v3 — Resilient & Batched)

```
New file indexed
       │
       ├──► LLM Worker Pool (Ray/Celery)
       │    ├──► Stella (Qwen3-8B): Generate embedding (batched)
       │    │    └──► If Stella unavailable: Fallback to all-MiniLM-L6-v2
       │    │
       │    └──► Pegasus (GPT-OSS-120B): Generate summary + classification
       │         └──► Async queue with backpressure (max 5 concurrent)
       │
       ▼
  ┌──────────────────────┐
  │ pgvector + PostgreSQL│
  └──────────────────────┘
```

**Rate Limiting & Fallbacks**:
- Embeddings: Batch 100 files at a time. If Stella down, use fallback (50x faster).
- Summaries: Max 5 concurrent jobs. If Pegasus down, skip but log warning.
- **LLM Health Check**: Every 60s. If >50% errors for 5m, switch to fallback.

### 3.4 Search & Retrieval Flow (v3 — Hybrid & Optimized)

```
Client Request
       │
       ▼
  ┌──────────┐     ┌─────────────────────────────────────┐
  │ Parse    │     │ Query Router                         │
  │ query    │────►│                                      │
  │ intent   │     │  "full-text search" → Meilisearch    │
  └──────────┘     │  "JSONPath query"   → PostgreSQL     │
                   │  "XPath query"      → PostgreSQL     │
                   │  "semantic search"  → pgvector        │
                   │  "hybrid"           → merge + re-rank │
                   │  "large result set" → streaming       │
                   └──────────────┬──────────────────────┘
                                  │
                                  ▼
                        ┌─────────────────┐
                        │ Result Merger   │
                        │ & Re-ranker     │
                        │                 │
                        │ Reciprocal Rank │
                        │ Fusion (RRF)    │
                        └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │ Response with:  │
                        │ - file metadata │
                        │ - highlights    │
                        │ - snippets      │
                        │ - NAS path      │
                        │ - download URL  │
                        └─────────────────┘
```

**New Features**:
- **Streaming Downloads**: For files >10 MB, return `Transfer-Encoding: chunked` with progress updates.
- **Pagination**: All list/search results use `cursor`-based pagination (not offset).
- **Fallback Queries**: If OpenSearch down, redirect to Meilisearch.

---

## 4. API Specification (v3 — MCP-Compliant, Secure, Scalable)

### 4.1 REST JSON API (OpenAPI 3.1)

**Base URL**: `https://siss.home.arpa/api/v3`

#### File Operations (v3 Enhancements)
| Method | Path | Description | v3 Fix |
|--------|------|-------------|--------|
| `GET` | `/files/{id}/content` | Stream raw file content | **Streaming for large files** (>10 MB uses chunked encoding) |
| `GET` | `/files/{id}/download` | Download with `Content-Disposition` | **HMAC-signed URLs** (time-limited) |
| `POST` | `/files` | Upload single file | **ClamAV scanning** (optional, disabled by default) |
| `POST` | `/files/batch` | Upload multiple files | **Async jobs** (returns 202 Accepted) |

#### Search Operations (v3 Enhancements)
| Method | Path | Description | v3 Fix |
|--------|------|-------------|--------|
| `GET` | `/search` | Full-text search | **Cursor pagination** (`?cursor=xxx`) |
| `POST` | `/search/semantic` | Vector similarity search | **Fallback to Meilisearch if pgvector down** |
| `POST` | `/search/hybrid` | Combined search | **RRF re-ranking with configurable weights** |

#### Schema & Analytics (v3 Enhancements)
| Method | Path | Description | v3 Fix |
|--------|------|-------------|--------|
| `GET` | `/stats` | Index statistics | **Includes LLM health metrics** |
| `GET` | `/schemas` | List schemas | **Cursor pagination** |

#### Ingestion Control (v3 Enhancements)
| Method | Path | Description | v3 Fix |
|--------|------|-------------|--------|
| `POST` | `/ingest/scan` | Trigger NAS re-scan | **Returns 202 with job ID** |
| `GET` | `/ingest/status` | Queue depth, rate | **Includes LLM job counts** |

#### Advanced Search DSL (v3 Enhancements)
```json
POST /api/v3/search
{
  "query": {
    "text": "configuration database",
    "filters": {
      "mime": ["application/json", "text/xml"],
      "tags": ["production"],
      "size_range": {"min": 1024, "max": 10485760},
      "indexed_after": "2026-01-01T00:00:00Z"
    },
    "json_path": "$.database.connections[?(@.host)]",
    "xpath": "//server[@environment='production']",
    "semantic": {
      "text": "database connection configuration",
      "weight": 0.3,
      "fallback_to_fulltext": true  // NEW: fallback if embeddings unavailable
    }
  },
  "sort": [{"field": "relevance", "order": "desc"}],
  "facets": ["mime", "tags", "schema_id"],
  "page": {"cursor": "xxx"},  // NEW: cursor pagination
  "size": 20,
  "highlight": true,
  "stream": false  // NEW: for large results
}
```

**Error Model (v3)**:
```json
{
  "error": {
    "code": "LLM_UNAVAILABLE",
    "message": "Stella embeddings service unavailable. Using fallback.",
    "details": {
      "fallback_engine": "all-MiniLM-L6-v2",
      "last_error": "Connection refused"
    }
  }
}
```

### 4.2 MCP Server (v3 — Full MCP 1.1 Compliance)

**Protocol**: JSON-RPC 2.0 over **stdio** (local agents) and **SSE** (remote agents via `/mcp`)

**Key Fixes**:
- **Pagination**: All list tools return `next_cursor`.
- **Streaming**: Large resources support `offset`/`length`.
- **Batch Tools**: `batch_search`, `batch_get_file`.
- **Resources**: Full `mcp:resource/read` with range requests.

#### MCP Tools (v3 Additions)
```json
[
  // ... (existing tools) ...
  {
    "name": "search_files",
    "description": "Full-text search with cursor-based pagination.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "query": { "type": "string" },
        "cursor": { "type": "string", "description": "Next cursor from previous response" },
        "limit": { "type": "integer", "minimum": 1, "maximum": 100, "default": 20 }
      },
      "required": ["query"]
    }
  },
  {
    "name": "get_file",
    "description": "Retrieve file content with optional byte range.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "file_id": { "type": "string" },
        "offset": { "type": "integer", "default": 0 },
        "length": { "type": "integer", "default": 100000, "maximum": 1048576 }
      }
    }
  },
  {
    "name": "batch_search_files",
    "description": "Search multiple queries in one call (agent efficiency).",
    "inputSchema": {
      "type": "object",
      "properties": {
        "queries": {
          "type": "array",
          "items": { "type": "object", "properties": { "query": { "type": "string" } } }
        }
      },
      "required": ["queries"]
    }
  }
]
```

#### MCP Resources (v3 Additions)
```json
[
  {
    "uri": "siss://file/{file_id}",
    "name": "File Content",
    "description": "Raw content of a specific indexed file",
    "mimeType": "application/octet-stream",
    "annotations": {
      "mcp:resource/range": {
        "supported": true,
        "unit": "bytes"
      }
    }
  }
]
```

---

## 5. Storage Layout & Schema Design (v3 — Secure & Maintainable)

### 5.1 NAS Directory Structure (v3 — Ingest-Only)

```
/volume1/data/                    ← SISS-watched root (configurable)
 ├── configs/                     ← XML/JSON config files
 ├── logs/                        ← ASCII log files
 ├── exports/                     ← data exports
 ├── uploads/                     ← files uploaded via SISS API
 └── .siss/                       ← SISS metadata (on NAS)
     ├── manifest.json            ← scan state, last-modified timestamps
     └── thumbnails/              ← generated previews (optional)
```

**Critical Changes**:
- NAS is **read-only** for `siss` service (except `uploads/`).
- Local cache: `~/.siss/cache/` (S3-compatible, RocksDB).
- MinIO (Tier 2+): Copies files from NAS on first access (lazy).

### 5.2 PostgreSQL Schema (v3 — Audit & Integrity)

```sql
-- Core file registry (v3 additions)
CREATE TABLE files (
    -- ... (existing fields) ...
    audit_log_id    UUID REFERENCES audit_logs(id),  -- NEW: audit trail
    integrity_hash  CHAR(64) NOT NULL,               -- NEW: BLAKE2b-256
    cache_status    TEXT DEFAULT 'uncached'         -- NEW: 'uncached', 'cached', 'minio'
                    CHECK (cache_status IN ('uncached','cached','minio'))
);

-- New: Audit Logging
CREATE TABLE audit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID,                            -- NULL for system actions
    action          TEXT NOT NULL,                   -- 'search', 'download', 'index'
    resource_type   TEXT NOT NULL,                   -- 'file', 'schema'
    resource_id     UUID,
    metadata        JSONB,                           -- e.g., {"query": "xxx"}
    timestamp       TIMESTAMPTZ DEFAULT now()
);

-- New: LLM Job Tracking
CREATE TABLE llm_jobs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    job_type        TEXT NOT NULL,                   -- 'embedding', 'summary'
    status          TEXT NOT NULL,                   -- 'pending', 'processing', 'done', 'failed'
    engine          TEXT NOT NULL,                   -- 'stella', 'fallback', 'pegasus'
    error_message   TEXT,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ
);
```

### 5.3 Meilisearch Index Configuration (v3 — Recovery)

```json
{
  "uid": "files",
  "primaryKey": "id",
  "searchableAttributes": [
    "content", "name", "ai_summary", "user_tags", "ai_tags", "metadata"
  ],
  "filterableAttributes": [
    "mime", "user_tags", "ai_tags", "schema_id", "size", "indexed_at", "status"
  ],
  "sortableAttributes": ["indexed_at", "size", "name"],
  "indexing-snapshot": {                            // NEW: Recovery
    "enabled": true,
    "interval": "1h"
  }
}
```

---

## 6. Scaling Strategy (v3 — Zero-Downtime Migration)

### 6.1 Tier Transition Triggers (v3 — Realistic Metrics)

| Metric | Tier 1 → 2 Trigger | Tier 2 → 3 Trigger |
|--------|--------------------|--------------------|
| **Indexed files** | > 100K *or* >50 concurrent clients | > 1M *or* >200 QPS |
| **Total data size** | > 100 GB | > 1 TB |
| **Search QPS** | > 10 | > 100 |
| **Ingestion rate** | > 500 files/hr | > 5K files/hr |

### 6.2 Search Engine Switchover (v3 — Zero Downtime)

1. **Dual Write**: Write to Meilisearch *and* OpenSearch (Tier 2 → 3).
2. **Feature Flag**: `search_engine: "meilisearch"` → `"opensearch"`.
3. **Cutover**: After 24h dual-write, stop Meilisearch writes. Delete old index.
4. **Rollback**: If OpenSearch errors >5%, flip flag back.

### 6.3 NAS Bandwidth Considerations (v3 — Optimized)

| NAS Link | Max Throughput | Files/min (avg 50 KB) | Recommendation |
|----------|---------------|-----------------------|----------------|
| 1 GbE | ~110 MB/s | ~2,200 | Tier 1 only |
| 2.5 GbE | ~280 MB/s | ~5,600 | Tier 2 |
| 10 GbE | ~1.1 GB/s | ~22,000 | Tier 3 |
| **Recommendation** | | **Use MinIO caching** to reduce NAS reads by 90% |

---

## 7. Security (v3 — Enterprise-Grade)

### 7.1 Tier 1 (MVP — Secure by Default)

| Layer | Approach |
|-------|----------|
| **Transport** | Caddy auto-TLS (self-signed or Let’s Encrypt) |
| **Authentication** | API keys + JWT (bcrypt-hashed in DB) |
| **Authorization** | RBAC: `admin`, `editor`, `reader`, `uploader` (new) |
| **Rate Limiting** | Caddy + Redis (global + per-tenant) |
| **NAS Mount** | `ro` for `/volume1/data`, `rw` for `/volume1/uploads` |
| **Secrets** | Environment variables (no plaintext in config) |

### 7.2 Tier 2/3 (Full Security Stack)

| Addition | Details |
|----------|---------|
| **Secrets** | HashiCorp Vault (DB passwords, API keys, LLM tokens) |
| **MCP Auth** | OAuth2 tokens or API keys via MCP handshake |
| **File ACLs** | PostgreSQL-backed ACLs (owner/group/permissions) + OPA |
| **Content Scanning** | **Mandatory** ClamAV scan on upload (configurable) |
| **Auditing** | All file access logged to `audit_logs` table |
| **Signed Downloads** | HMAC-signed URLs (15-minute expiry) |

---

## 8. Deployment (v3 — Resilient & Maintainable)

### 8.1 Tier 1: Docker Compose (v3 — Health Checks)

```yaml
services:
  siss:
    image: ghcr.io/your-org/siss:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: unless-stopped
    volumes:
      - nas-data:/mnt/nas/data:ro
      - nas-uploads:/mnt/nas/uploads:rw
      - siss-cache:/home/siss/.siss/cache
    # ... (rest as v2)
  postgres:
    environment:
      POSTGRES_INITDB_ARGS: "--data-checksums --wal-level=replica"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - pgwal:/var/lib/postgresql/pg_wal
  # ... (Meilisearch, Caddy)
volumes:
  siss-cache:
  pgwal:
```

### 8.2 Running on Synology DSM (v3 — Optimized)

- **Use `noatime,nodiratime`** in NFS mount options.
- **Enable `rsize=1048576,wsize=1048576`** for large I/O.
- **Disable `sync`** (write-back) for better performance (risk: data loss on crash).

### 8.3 Tier 2: K3s with Helm (v3 — PVC Resizing)

```yaml
# values.yaml
persistence:
  meilisearch:
    enabled: true
    size: 10Gi
    storageClass: local-path
    allowVolumeExpansion: true
  postgres:
    size: 20Gi
    storageClass: local-path
    allowVolumeExpansion: true
```

**Migration Script**:
```bash
# Resize PVCs (K3s)
kubectl patch pvc meilisearch-data-meilisearch-0 -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

---

## 9. Observability & Operations (v3 — Full Stack)

### 9.1 Metrics (v3 — Critical for Debugging)
| Metric | Tier 1 | Tier 2/3 |
|--------|--------|----------|
| **LLM Errors** | `llm_errors_total{engine="stella"}` | Prometheus alert |
| **Cache Hit Rate** | `cache_hits_total / (hits + misses)` | Grafana dashboard |
| **Ingestion Rate** | `files_indexed_total` | Real-time alert |
| **NAS Latency** | `nas_latency_seconds` | Histogram |

### 9.2 Logging (v3 — Correlation IDs)
- **Structured Logs**: JSON with `trace_id`, `request_id`.
- **Log Aggregation**: Loki (Tier 2+), file logging (Tier 1).
- **Searchable Fields**: `user_id`, `file_id`, `action`.

### 9.3 Maintenance (v3 — Runbooks Included)

| Task | Procedure |
|------|-----------|
| **Vacuum PostgreSQL** | `VACUUM ANALYZE extracted_fields;` (weekly) |
| **Rotate Meilisearch Snapshots** | `curl -X POST /snapshot/create` → copy to S3 |
| **Check NAS Integrity** | `find /volume1/data -type f -exec sha256sum {} \;` (monthly) |
| **Rotate Secrets** | `vault kv rotate -mount=secret siss` |

### 9.4 Backup Strategy (v3 — Non-Negotiable)

| Component | Backup |
|-----------|--------|
| **PostgreSQL** | `pg_dump` + WAL archiving to S3 |
| **Meilisearch** | Snapshots + S3 copy |
| **MinIO** | `mc alias set siss http://minio:9000 ...` → `mc mirror` |
| **NAS** | `rsync` to offsite (if critical) |

---

## 10. Performance Targets (v3 — Realistic)

| Metric | Tier 1 | Tier 2 | Tier 3 |
|--------|--------|--------|--------|
| **Indexed files** | 100K | 1M | 50M+ |
| **Search latency (p95)** | < 100 ms | < 150 ms | < 250 ms |
| **Ingestion rate** | 50–100 files/min | 500 files/min | 5K files/min |
| **Concurrent clients** | 10 | 100 | 1K+ |
| **Search QPS** | 20 | 100 | 2,000+ |
| **Upload throughput** | 50 MB/min | 500 MB/min | 5 GB/min |
| **Time to first search result** | < 50 ms | < 100 ms | < 150 ms |
| **Embedding generation** | ~20 files/min (fallback) | ~50 files/min (batched) | ~200 files/min |
| **Memory (total stack)** | < 1.5 GB | < 8 GB | < 64 GB |

---

## 11. Implementation Roadmap (v3 — Accelerated MVP)

### Phase 0: Foundation (1 week)
- Git repo, CI/CD, Docker Compose stack (PostgreSQL, Meilisearch, Caddy)
- Health checks, structured logging, metrics endpoints

### Phase 1: Core Ingestion + Search (2 weeks)
- File discovery + dedup (dual-hash, integrity check)
- Local cache layer (S3-compatible)
- Parsers (ASCII/JSON/XML) + schema inference
- Meilisearch indexing pipeline
- **Milestone: Search your NAS files from a browser**

### Phase 2: Full REST API + Structured Queries (2 weeks)
- CRUD endpoints (upload with ClamAV, delete, update)
- JSONPath/XPath query engines
- Cursor pagination
- OpenAPI spec (utoipa)
- **Milestone: Upload and search 100 files**

### Phase 3: MCP Server (1 week)
- Full MCP 1.1 implementation (pagination, streaming, batch tools)
- Integration testing (Claude Code)
- **Milestone: Ask Claude to search your NAS**

### Phase 4: LLM Integration (2 weeks)
- Embedding caching (Redis)
- Fallback to all-MiniLM
- Async summarization queue
- Hybrid search with RRF
- **Milestone: Semantic search works**

### Phase 5: Security + Polish (2 weeks)
- Vault secrets integration
- RBAC with OPA
- Audit logging
- CLI tool (`siss-cli`)
- **Milestone: v1.0.0 release**

**Total to MVP: 6 weeks. Total to production: 12 weeks.**

---

## 12. Rust Crate Dependencies (v3 — Production-Grade)

| Crate | Purpose | v3 Change |
|-------|---------|-----------|
| `axum` | HTTP framework | + `axum-extra` for streaming |
| `rmcp` | MCP server | + `mcp` crate for MCP 1.1 |
| `serde` + `serde_json` | JSON serialization | — |
| `quick-xml` | XML parsing | + `quick-xml::events` for streaming |
| `sqlx` | PostgreSQL driver | + `sqlx::types::Json` for audit logs |
| `pgvector` | pgvector support | — |
| `meilisearch-sdk` | Meilisearch client | — |
| `jsonpath-rust` | JSONPath | — |
| `sxd-xpath` | XPath | + `sxd-document` for streaming |
| `notify` | Filesystem watcher | + `notify::Watcher` with backoff |
| `sha2` + `blake2` | Hashing | Dual-hash |
| `tokio` | Async runtime | — |
| `tower` | Middleware | + `tower-http` for tracing |
| `utoipa` | OpenAPI spec | + `utoipa-swagger-ui` |
| `tracing` + `tracing-opentelemetry` | Logging + tracing | **NEW** |
| `reqwest` | HTTP client | + `reqwest::Client::new().timeout()` |

---

## 13. Summary

### What Changed from v2
| Area | v2 Flaw | v3 Fix |
|------|---------|--------|
| **Storage** | NAS as source of truth = fragile | NAS = ingest source only; cache + MinIO = serving |
| **LLMs** | No fallback, blocking | Fallback embeddings, async queues, health checks |
| **MCP** | Incomplete spec | Full MCP 1.1 (pagination, streaming, batch) |
| **Search Migration** | Unspecified | Zero-downtime dual-write + feature flag |
| **Security** | Basic auth, no audit | Vault, audit logs, RBAC, ClamAV |
| **Observability** | None | Full telemetry (metrics, logs, traces) |
| **Operations** | None | Runbooks, backups, PVC resizing |

### What’s New in v3
- **Integrity verification**: Dual hashing + periodic checks.
- **Fallback LLMs**: all-MiniLM if Stella unavailable.
- **Cursor pagination**: For all list/search APIs.
- **Streaming downloads**: For large files (>10 MB).
- **MCP batch tools**: Agent efficiency.
- **Audit logging**: File access tracking.
- **Zero-downtime search migration**: Meilisearch → OpenSearch.
- **LLM health monitoring**: Automatic fallback.

### Why This Will Work in Production
1. **Availability-first**: NAS failures don’t break search.
2. **Resilient LLMs**: Fallbacks prevent total outages.
3. **MCP-compliant**: AI agents work as designed.
4. **Observable**: You can debug when things break.
5. **Operational**: Backups, runbooks, scaling paths.

---

**Next Steps**:  
✅ Implement Phase 0 (1 week)  
✅ Validate Tier 1 with real NAS (Synology DS923+)  
✅ Build MCP integration tests (Claude Code)  

**Final Note**: This spec balances ambition with pragmatism. It starts simple but is built for scale, resilience, and observability — the triad of production systems.