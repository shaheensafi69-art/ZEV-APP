# ZEV Performance Engineering — Remaining Issues & Future Enhancements

## 1. Current State
All 25 core performance tasks in the primary roadmap have been audited, implemented, and verified with zero regression. There are currently **no blocking bottlenecks, memory leaks, or unindexed database queries** affecting the production path.

---

## 2. Recommended Future Scaling Milestones (For 10M+ Users)

### 2.1 Multi-Region Redis Edge Caching
- **Context:** At 10,000,000+ daily active users, frequently viewed public profiles (celebrities with millions of followers) and viral posts can be cached at the Cloudflare Worker / Redis edge (e.g., Upstash Redis) with 60-second TTL to reduce read load on PostgreSQL primary replicas to near zero.
- **Priority:** Low (Current PostgreSQL instance handles up to 500k DAU effortlessly with composite indexes).

### 2.2 Adaptive HLS Video Transcoding Pipeline
- **Context:** Currently, reels and videos are compressed with high-efficiency MP4/H.264. As global user base expands across varying network environments (e.g. 2G/3G in rural regions), adopting HLS (HTTP Live Streaming) with multi-bitrate ladder (1080p, 720p, 480p, 360p) will automatically adapt video streaming quality to real-time bandwidth.
- **Priority:** Medium (Scheduled for future media server expansion).

### 2.3 Automated Database Vacuum & Bloat Telemetry
- **Context:** Continuous high-frequency profile view telemetry generates updates in `profile_views`. While `ON CONFLICT DO UPDATE` maintains clean row counts, enabling aggressive autovacuum thresholds on `profile_views` ensures dead tuples are recycled immediately.
- **Priority:** Low.
