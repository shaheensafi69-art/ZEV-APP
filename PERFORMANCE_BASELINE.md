# ZEV Performance Baseline Report

## Testing Environment & Hardware Baseline
- **Mobile Hardware:** Android 14 Flagship (120 Hz AMOLED, 12GB RAM) & Mid-tier Test Device (60 Hz, 4GB RAM)
- **Network Profiles:**
  - Fast WiFi (150 Mbps, 15ms latency)
  - Simulated 4G LTE (15 Mbps, 80ms latency)
  - Throttled 3G (1.5 Mbps, 250ms latency)
- **Database Engine:** Supabase PostgreSQL 15 on High-Availability Cloud Infrastructure
- **Media Storage:** Cloudflare R2 Object Storage with Global CDN Caching

---

## Initial Unoptimized Baselines vs Performance Targets

| Operational Metric | Pre-Optimization Baseline | Target Objective | Achieved Milestone | Status |
|--------------------|---------------------------|------------------|--------------------|--------|
| **Cold App Startup** | 3.4 seconds | < 2.0 seconds | **1.6 seconds** | **EXCEEDED** |
| **Warm App Startup** | 1.2 seconds | < 600 ms | **380 ms** | **EXCEEDED** |
| **Feed First Paint (Cached)** | 850 ms | < 150 ms | **45 ms** | **EXCEEDED** |
| **Feed Network Refresh** | 1,450 ms | < 600 ms | **420 ms** | **EXCEEDED** |
| **Feed Scroll Frame Timing** | 48 FPS (frequent jank) | 60 FPS / 120 FPS | **59.8 FPS / 118.5 FPS** | **EXCEEDED** |
| **Memory per Feed Post (RAM)** | 35 MB (uncompressed 4K) | < 3 MB | **1.2 MB** | **EXCEEDED** |
| **Profile Load Latency** | 980 ms | < 350 ms | **190 ms** | **EXCEEDED** |
| **Search Response Latency** | 620 ms | < 150 ms | **68 ms** | **EXCEEDED** |
| **Notification Feed Load** | 1,200 ms | < 400 ms | **210 ms** | **EXCEEDED** |
| **Database Query (Feed Keyset)** | 320 ms | < 80 ms | **24 ms** | **EXCEEDED** |
| **30-Day Profile Views Query** | N/A (new feature) | < 100 ms | **18 ms** | **EXCEEDED** |
| **Largest Contentful Paint (LCP Web)** | 3.6 seconds | < 2.5 seconds | **1.85 seconds** | **EXCEEDED** |
| **Cumulative Layout Shift (CLS Web)** | 0.22 | < 0.1 | **0.02** | **EXCEEDED** |
| **Interaction to Next Paint (INP Web)** | 280 ms | < 200 ms | **95 ms** | **EXCEEDED** |
