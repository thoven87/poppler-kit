# Docker and Cloud Run

Deploy PopplerKit on Linux containers, GCP Cloud Run, and other serverless runtimes.

## Choosing your system dependencies

PopplerKit requires **poppler ≥ 26.05.0**, which must be compiled from source
(Ubuntu 24.04 is the minimum build host). The Dockerfiles below incorporate
the source build as a dedicated stage that can be cached between runs.

| Product | Build-time | Runtime |
|---|---|---|
| `PopplerKit` (C++ binding) | poppler 26.05.0 built from source | `libpoppler-cpp.so` (installed via cmake) |
| `PopplerUtils` (subprocesses) | *(nothing extra)* | CLI tools from the same build (`ENABLE_UTILS=ON`) |
| Both products | poppler 26.05.0 from source | same runtime |

The poppler build step is identical across all three variants; only the
Swift build and the set of enabled cmake features differ.

## Dockerfile: PopplerKit + PopplerUtils (recommended)

A three-stage build: compile poppler from source, compile the Swift app, assemble the
runtime image.  The poppler stage can be cached independently across app rebuilds.

```dockerfile
# ── Stage 1: build poppler 26.05.0 from source ───────────────────────────────────────
FROM swift:6.3 AS poppler-builder

RUN apt-get update -q && apt-get install -y --no-install-recommends \
      build-essential cmake wget pkg-config \
      libfreetype-dev libfontconfig-dev libjpeg-dev libpng-dev libtiff-dev \
      libopenjp2-7-dev zlib1g-dev liblcms2-dev libnss3-dev libcairo2-dev \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
    && wget -q https://poppler.freedesktop.org/poppler-26.05.0.tar.xz \
    && tar -xJf poppler-26.05.0.tar.xz \
    && cmake -S poppler-26.05.0 -B poppler-build \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_INSTALL_PREFIX=/usr \
         -DENABLE_BOOST=OFF -DENABLE_QT5=OFF -DENABLE_QT6=OFF \
         -DENABLE_GLIB=OFF -DENABLE_LIBCURL=OFF \
         -DENABLE_CPP=ON -DENABLE_UTILS=ON \
         -DENABLE_LIBOPENJPEG=openjpeg2 \
         -DBUILD_GTK_TESTS=OFF -DBUILD_CPP_TESTS=OFF -DBUILD_MANUAL_TESTS=OFF \
    && cmake --build poppler-build --parallel "$(nproc)" \
    && cmake --install poppler-build

# ── Stage 2: build the Swift app ───────────────────────────────────────────────────────
FROM poppler-builder AS app-builder

WORKDIR /build
COPY . .
RUN swift build -c release --product YourApp

# ── Stage 3: minimal runtime ─────────────────────────────────────────────────────────────
FROM swift:6.3-slim

# Copy the runtime libs installed by poppler's cmake --install
COPY --from=poppler-builder /usr/lib/libpoppler*.so* /usr/lib/
COPY --from=poppler-builder /usr/bin/pdf*            /usr/bin/

RUN ldconfig

COPY --from=app-builder /build/.build/release/YourApp /usr/local/bin/app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
```

> The runtime stage only copies the `.so` files and CLI tools — not headers,
> pkg-config files, or the cmake build tree — keeping the final image small.

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
