# Docker and Cloud Run

Deploy PopplerKit on Linux containers, GCP Cloud Run, and other serverless runtimes.

## Choosing your system dependencies

| Product | Build-time | Runtime |
|---|---|---|
| `PopplerKit` (C++ binding) | `libpoppler-cpp-dev`, `pkg-config` | `libpoppler-cpp0v5` |
| `PopplerUtils` (subprocesses) | *(nothing extra)* | `poppler-utils` |
| Both products | `libpoppler-cpp-dev`, `pkg-config` | `libpoppler-cpp0v5`, `poppler-utils` |

## Dockerfile: PopplerKit only

Use this when you only need in-process text extraction and rendering (`import PopplerKit`).

```dockerfile
# ── Build stage ──────────────────────────────────────────────────────────────
FROM swift:6.0-jammy AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpoppler-cpp-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .
RUN swift build -c release --product YourApp

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM swift:6.0-jammy-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpoppler-cpp0v5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/.build/release/YourApp /usr/local/bin/app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
```

## Dockerfile: PopplerUtils only

Use this when you only need CLI-backed operations (split, merge, SVG, signing) and `libpoppler-cpp`
is not required.

```dockerfile
# ── Build stage ──────────────────────────────────────────────────────────────
FROM swift:6.0-jammy AS builder

WORKDIR /build
COPY . .
RUN swift build -c release --product YourApp

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM swift:6.0-jammy-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        poppler-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/.build/release/YourApp /usr/local/bin/app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
```

## Dockerfile: both PopplerKit and PopplerUtils

The most common deployment — full feature set.

```dockerfile
# ── Build stage ──────────────────────────────────────────────────────────────
FROM swift:6.0-jammy AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpoppler-cpp-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .
RUN swift build -c release --product YourApp

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM swift:6.0-jammy-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpoppler-cpp0v5 \
        poppler-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/.build/release/YourApp /usr/local/bin/app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
```

## Cloud Run configuration

```yaml
# cloudbuild.yaml (or equivalent)
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/$PROJECT_ID/pdf-service', '.']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/$PROJECT_ID/pdf-service']
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    args:
      - 'run'
      - 'deploy'
      - 'pdf-service'
      - '--image=gcr.io/$PROJECT_ID/pdf-service'
      - '--memory=1Gi'       # Minimum recommended for PDF rendering
      - '--cpu=2'            # More CPUs reduce per-page render time
      - '--concurrency=4'    # Keep low for rendering workloads; higher for text-only
      - '--timeout=300'      # 5 min: allow for large document batches
      - '--max-instances=10'
      - '--region=us-central1'
```

### Memory sizing

| Workload | Memory |
|---|---|
| Text extraction only | 256 MB |
| Rendering (150 DPI) | 512 MB |
| Rendering (300 DPI) | 1 GB |
| Large documents (100+ pages) | 2 GB |

### Concurrency

Set `--concurrency=1` for rendering-heavy workloads to avoid memory contention between simultaneous
page renders.  For text-only workflows, `--concurrency=10` or higher is safe.

## Ubuntu version compatibility

All Swift official images use Ubuntu.  The `libpoppler-cpp` package name and the bundled poppler
version vary:

| Image base | poppler version | Notes |
|---|---|---|
| `swift:6.0-focal` (20.04) | 0.86 | Missing `non_raw_non_physical_layout` — use `.physical` |
| `swift:6.0-jammy` (22.04) | 22.02 | Recommended — full API coverage |
| `swift:6.0-noble` (24.04) | 24.02 | Latest poppler, fully supported |

> **Recommendation**: use `swift:6.0-jammy` for maximum compatibility with both the Swift 6
> toolchain and poppler 22+.

## docker-compose for local development

```yaml
version: '3.9'
services:
  pdf-service:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./test-pdfs:/data/pdfs:ro   # mount local PDFs for testing
    environment:
      - PDF_INPUT_DIR=/data/pdfs
```

## Health check

Since PopplerKit is an in-process library, a minimal health check is sufficient:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

In your Swift handler:

```swift
// GET /health
func health(_ req: Request, ctx: Context) throws -> HTTPStatus {
    // Optionally: try a trivial parse to confirm poppler is linked
    return .ok
}
```
