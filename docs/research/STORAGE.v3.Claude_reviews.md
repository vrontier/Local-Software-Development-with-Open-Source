# Review of STORAGE.v3 (Qwen3-Coder-Next 80B)

> Reviewed by Claude Opus 4.6 — 2026-02-12
>
> Qwen3-Coder-Next produced a thorough critique of v2 and a substantial v3 revision.
> The review below evaluates what v3 got right, what it got wrong, and what remains
> missing across all three versions. Each issue is classified by severity.

---

## Performance Context

| | Pegasus (v1) | Claude (v2) | Qwen3-Coder-Next (v3) |
|-|-------------|-------------|------------------------|
| **Model** | GPT-OSS-120B (117B MoE) | Claude Opus 4.6 (API) | Qwen3-Coder-Next (80B dense) |
| **Prompt tokens** | 480 | n/a | 12,187 |
| **Completion tokens** | 6,618 | n/a | 10,356 |
| **Generation speed** | 45.3 tok/s | n/a | 27.5 tok/s |
| **Wall clock** | 146.8 s | manual | 434.4 s |

---

## What v3 Got Right

### Genuinely Good Additions

1. **Observability section** (Section 9) — v2 had none. Metrics, structured logging with
   correlation IDs, and maintenance runbooks are necessary for any production system. This
   was the most important gap in v2.

2. **Backup strategy** (Section 9.4) — PostgreSQL WAL archiving, Meilisearch snapshots,
   and MinIO mirroring. Non-negotiable for production and completely missing from v2.

3. **LLM health checking with automatic fallback** — The principle is sound: if your
   embedding service goes down, indexing shouldn't stop. The implementation details are
   wrong (see below), but the concept is correct.

4. **Audit logging table** — Tracking who accessed what and when is necessary for any
   multi-user system.

5. **LLM job tracking table** — `llm_jobs` with status, engine, and error tracking gives
   visibility into the async pipeline. Good schema addition.

6. **Docker Compose health checks and restart policies** — Valid criticism of v2. The
   `healthcheck` and `restart: unless-stopped` additions are correct.

7. **Search engine migration via dual-write + feature flag** — This is the right approach
   for zero-downtime Meilisearch-to-OpenSearch migration. v2 left this unspecified.

8. **Cursor-based pagination** — Correct for large result sets. Offset-based pagination
   breaks beyond ~10K results. Should be applied consistently.

9. **Async batch uploads returning 202 Accepted** — Correct HTTP semantics for long-running
   operations.

10. **Edge case identification** (Section critique #10) — File path case sensitivity, Unicode
    normalization, symlinks, and file locking during indexing are real issues that v2 ignored.

---

## What v3 Got Wrong

### CRITICAL: Factual Errors

#### 1. "MCP 1.1 Compliance" Does Not Exist
**Severity: High** — Undermines credibility of the entire MCP section.

v3 repeatedly references "Full MCP 1.1 compliance" and claims Anthropic's MCP spec
"explicitly requires" specific features:

> "Tools to return cursor-based pagination"
> "`mcp:resource/read` must support `offset`/`length`"
> "`mcp:resource:*` resources to support range requests"

**None of these are in the MCP specification.** There is no "MCP 1.1." The MCP spec does
not mandate cursor pagination on tools, does not require range requests on resources, and
has no `mcp:resource/range` annotation. The `annotations` block in v3's resource definition
is fabricated:

```json
"annotations": {
  "mcp:resource/range": {     // <-- This does not exist in MCP
    "supported": true,
    "unit": "bytes"
  }
}
```

Cursor pagination and byte-range access are **good engineering practices**, but attributing
them to "MCP 1.1 compliance" is technically incorrect and misleading. v2's MCP section,
while not perfect, was grounded in the actual spec.

**v4 fix**: Remove all "MCP 1.1" references. Add pagination and range support as
engineering best practices, not spec requirements.

#### 2. SHA-256 "Preimage Attacks Are Plausible" is False
**Severity: Medium** — Leads to unnecessary dual-hash complexity.

v3 claims:
> "SHA-256 *preimage attacks* are plausible in high-stakes environments"

This is factually wrong. There are **no known preimage attacks on SHA-256**. The best
known attack reduces the preimage resistance from 2^256 to approximately 2^245, which is
still computationally infeasible. For file deduplication on a private NAS, SHA-256 is
vastly more than sufficient. SHA-1 has known *collision* attacks (not preimage attacks),
and even SHA-1 collisions required Google's dedicated compute cluster.

Adding BLAKE2b-256 as "defense-in-depth" doubles hashing CPU time and adds storage
overhead for zero practical benefit in this threat model.

**v4 fix**: SHA-256 alone for dedup. Add periodic integrity re-hashing (v3's good idea)
using the same SHA-256 hash — no dual-hash needed.

#### 3. "S3-Compatible (RocksDB)" is a Contradiction
**Severity: Medium** — Confuses two unrelated technologies.

v3 describes the local cache as "S3-compatible (RocksDB)". RocksDB is an embedded
key-value store. It is not S3-compatible. These are fundamentally different things.

For a local file cache at Tier 1, a simple filesystem directory with LRU eviction
(delete oldest cached files when cache exceeds size limit) is far simpler and equally
effective. If S3 API compatibility is needed, that's what MinIO provides at Tier 2.

**v4 fix**: Filesystem-based cache with configurable size limit and LRU eviction.

### SIGNIFICANT: Architecture Errors

#### 4. Ray/Celery for LLM Workers Breaks the Rust Ecosystem
**Severity: High** — Introduces Python runtime dependency into a Rust-native system.

The entire SISS core is a single Rust binary chosen specifically for its minimal footprint
(~12 MB, no runtime dependencies, no GC). Adding Ray or Celery requires:
- Python 3.x runtime
- pip/virtualenv
- Python process management
- Inter-process communication between Rust and Python

This defeats the purpose of the single-binary design. The correct approach:
- **Tier 1**: Tokio async tasks with bounded channels (zero additional dependencies,
  built into the existing binary)
- **Tier 2+**: NATS JetStream work queues (already proposed by v3 for the event bus,
  so using it for LLM job dispatch is free)

**v4 fix**: Remove Ray/Celery. Use tokio tasks (Tier 1) and NATS JetStream (Tier 2+).

#### 5. Embedding Fallback Has a Dimension Mismatch Problem
**Severity: High** — Renders semantic search broken during fallback.

v3 proposes `all-MiniLM-L6-v2` (384 dimensions) as fallback for Stella/Qwen3-8B
(unknown dimensions, likely 896 or 2048 for Qwen3). You **cannot**:
- Store both in the same pgvector column (dimension must be fixed at table creation)
- Compare 384-dim vectors with 896-dim vectors (mathematically undefined)
- Mix results from different embedding spaces (the similarity scores are meaningless)

A fallback embedding model **must produce the same dimension vector**, or you need
separate pgvector columns and cannot do cross-model similarity search.

**v4 fix**: Use a single dedicated embedding model for all embeddings (see
"Fundamental Gap" section below).

#### 6. NAS Critique Missed the Point — Over-Correction
**Severity: Medium** — Adds unnecessary complexity at Tier 1.

v3 claims NAS-as-source-of-truth is a "fatal flaw" and demotes NAS to "ingest source
only," copying everything to a local cache. But the user's requirement is to **index
files that live on a Synology NAS**. The NAS IS the data. The user doesn't want copies.

The correct resilience model for Tier 1:
- **Search always works** — search indexes (Meilisearch, PostgreSQL) are local, not on NAS
- **File downloads degrade gracefully** — if NAS is unreachable, return 503 with
  `Retry-After` header and a clear message, not a hang or crash
- **No file duplication** — the index points to NAS paths, files are streamed through
  the Rust API on download
- **NAS outage = partial outage** (search works, downloads don't) rather than
  total outage

At Tier 2+, adding MinIO as a caching/serving layer for HA makes perfect sense, but
as a **read-through cache**, not as a replacement for the NAS.

**v4 fix**: NAS remains source of truth at Tier 1 with graceful degradation. MinIO
as read-through cache at Tier 2+.

#### 7. `audit_log_id` Foreign Key on `files` Table is Backwards
**Severity: Low** — Schema error.

The v3 schema adds `audit_log_id UUID REFERENCES audit_logs(id)` to the `files` table.
This implies each file has exactly one audit log entry. In reality, one file has **many**
audit events (indexed, searched, downloaded, metadata updated, etc.). The relationship
is one-to-many from files to audit_logs, which v3 already models correctly via
`audit_logs.resource_id` → files.id. The FK on `files` should be removed.

**v4 fix**: Remove `audit_log_id` from `files` table.

### MODERATE: Over-Engineering

#### 8. HashiCorp Vault at Tier 2 is Premature
**Severity: Low** — Adds operational burden without proportional benefit.

Vault requires its own HA cluster, unsealing procedures on restart, certificate
management, and operational expertise. For a 2-5 node K3s cluster, this is excessive.

Better alternatives for Tier 2:
- **Bitnami Sealed Secrets**: encrypt secrets in Git, decrypt in cluster
- **SOPS + age**: encrypt secret files, commit to repo
- **K3s built-in secrets**: adequate for small clusters with proper RBAC

Vault is appropriate at Tier 3 where you have the operational capacity to run it.

**v4 fix**: Tier 1: env vars. Tier 2: Sealed Secrets or SOPS. Tier 3: Vault.

#### 9. ClamAV as "Mandatory" for Self-Hosted Private Network
**Severity: Low** — Adds latency and complexity for minimal benefit.

For a system indexing your own files on your own NAS on your own network, mandatory
virus scanning on every upload is security theater. The files already exist on the NAS.
If they contained malware, scanning them on upload to the same NAS doesn't help.

ClamAV should remain **optional** (as v2 specified), enabled only when SISS accepts
uploads from untrusted sources.

**v4 fix**: ClamAV remains optional, disabled by default, documented as recommended
for public-facing deployments.

#### 10. Performance Targets Were Over-Corrected
**Severity: Medium** — Under-sells Meilisearch's actual capabilities.

v3 lowered Tier 1 from 500K to 100K indexed files. But Meilisearch can handle
**millions** of documents on a single node with 16 GB RAM. The confusion stems from
conflating two different metrics:
- **Index capacity** (how many files can be stored and searched): limited by RAM/disk
- **Ingestion throughput** (how fast new files enter the pipeline): limited by
  parsing + LLM processing

These should be listed separately. The ingestion rate correction (considering LLM
overhead) is reasonable, but capacity shouldn't be artificially lowered.

**v4 fix**: Separate capacity from throughput. Tier 1 capacity: 500K-1M files.
Tier 1 ingestion: 200-500 files/min (no LLMs) or 50-100 files/min (with LLMs).

### CONTENT: v3 Dropped Significant v2 Material

v3 truncated or omitted:
- Complete REST API endpoint table (v2 had all 10 endpoints with request/response shapes)
- Full MCP tool definitions (v2 had all 11 tools with complete JSON Schema, v3 shows only 3)
- Docker Compose NFS volume configuration with driver_opts
- Caddyfile example
- Complete PostgreSQL schema (v3 shows only additions with `-- ... existing fields ...`)
- Response examples with full JSON bodies
- API query parameter documentation
- Meilisearch typo tolerance configuration
- OpenSearch mapping for Tier 3

A specification should be **complete and standalone**. Referencing "existing tools"
without listing them makes v3 incomplete as a document.

---

## What ALL Versions Missed

### FUNDAMENTAL GAP 1: No Embedding Model Strategy

This is the most critical omission across v1, v2, and v3.

**The problem**: None of the versions address what model actually generates embeddings.

- **Qwen3-8B** is a chat/completion model. Its `/v1/embeddings` endpoint (if enabled in
  llama.cpp with `--embeddings`) produces embeddings from a decoder-only model fine-tuned
  for dialogue. These are **poor quality** for semantic search compared to purpose-built
  embedding models.
- **GPT-OSS-120B** is a reasoning model. Not suitable for embeddings at all.
- **all-MiniLM-L6-v2** (v3's proposed fallback) is a proper embedding model but at 384
  dimensions it's an older/smaller architecture.

**The solution**: Run a dedicated embedding model on llama.cpp alongside the chat models.
Recommended options (all available as GGUF):
- `nomic-embed-text-v1.5` (768-dim, 137M params, ~270 MB GGUF) — best quality/size ratio
- `bge-large-en-v1.5` (1024-dim, 326M params, ~650 MB GGUF) — slightly better quality
- `snowflake-arctic-embed-m` (768-dim, 109M params, ~220 MB GGUF) — fast and compact

These are small enough to run on Stella alongside Qwen3-8B, or as a separate llama-server
instance on a minimal port. They produce consistent, high-quality embeddings designed
for retrieval.

### FUNDAMENTAL GAP 2: No Content Chunking Strategy

Large files need chunking for:
- **Search quality**: A 50 MB XML file indexed as a single document produces poor search
  results. Meilisearch can store it, but relevance ranking suffers.
- **Embedding quality**: Embedding models have context limits (typically 512-8192 tokens).
  A full file exceeds this.
- **Highlight quality**: Showing relevant snippets requires knowing where chunks begin/end.

**Needed strategy**:
- **ASCII files**: Chunk by paragraph or every N lines (e.g., 100 lines per chunk) with
  configurable overlap
- **JSON files**: Chunk by top-level array elements or configurable JSONPath boundaries
- **XML files**: Chunk by configurable XPath node boundaries (e.g., each `<record>`,
  each `<entry>`)
- Each chunk gets its own Meilisearch document and embedding, linked to the parent file
  via `file_id` + `chunk_index`
- Search returns chunk-level results, grouped by file

### FUNDAMENTAL GAP 3: No File Size Limits or Handling

What happens when someone puts a 10 GB log file on the NAS? Or a 500 MB XML dump?

- Maximum indexable file size should be configurable (default: 100 MB?)
- Files exceeding the limit: index metadata only (name, size, hash, path) but skip
  content parsing and embedding
- For files between "normal" and "max": use streaming parsers (v3 mentions this but
  doesn't specify the threshold)

### MODERATE GAP: Qwen3-Coder-Next on Max Not Integrated

The user has three LLM hosts now: Pegasus (120B MoE), Stella (8B dense), and Max
(Qwen3-Coder-Next 80B dense). The spec should consider Max as a resource:
- 80B dense model with 256K context — excellent for summarizing large documents
- Could replace Pegasus for summarization tasks where 120B reasoning is overkill
- Could run an embedding model alongside Qwen3-Coder-Next

---

## Verdict

**v3 is a meaningful improvement over v2 in operational concerns** (observability, backups,
maintenance, audit logging). These sections should be incorporated into v4.

**v3 introduces several technical errors** that v2 did not have (fabricated MCP spec
requirements, BLAKE2b security theater, Python task queue in a Rust system, dimension
mismatch in embedding fallback). These must be corrected.

**v3 is incomplete as a standalone document** — it references v2 content without
reproducing it, making it unusable without reading v2 alongside it.

**v4 should be**: v2's architecture and completeness + v3's operational additions +
corrections to both + the three fundamental gaps (embedding model, chunking, file size
limits).

| Category | Count |
|----------|-------|
| Good additions to keep | 10 |
| Factual errors to fix | 3 |
| Architecture errors to fix | 4 |
| Over-engineering to simplify | 3 |
| Content dropped to restore | 10+ sections |
| Fundamental gaps (all versions) | 3 |
