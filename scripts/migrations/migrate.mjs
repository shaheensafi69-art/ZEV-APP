#!/usr/bin/env node
/**
 * ZEV Reversible PostgreSQL Migration Runner
 * Usage:
 *   node migrate.mjs status
 *   node migrate.mjs up
 *   node migrate.mjs down <version_prefix_or_full_name>
 *   node migrate.mjs verify
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { Client } = require('/Users/Safi_Sahib/zev_admin/node_modules/pg');

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function loadDirectDbUrl() {
  if (process.env.DATABASE_DIRECT_URL) {
    return process.env.DATABASE_DIRECT_URL.trim();
  }
  for (const envPath of [
    '/Users/Safi_Sahib/zev_admin/.env',
    '/Users/Safi_Sahib/zev-app/.env',
  ]) {
    if (fs.existsSync(envPath)) {
      const content = fs.readFileSync(envPath, 'utf8');
      const m = content.match(/^DATABASE_DIRECT_URL=(.+)$/m);
      if (m) {
        return m[1].trim().replace(/^["']|["']$/g, '');
      }
    }
  }
  throw new Error('DATABASE_DIRECT_URL not found in environment or .env');
}

function sha256(text) {
  return crypto.createHash('sha256').update(text, 'utf8').digest('hex');
}

async function ensureMigrationsTable(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS public.schema_migrations (
      version text PRIMARY KEY,
      name text NOT NULL,
      checksum text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  await client.query(`ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;`);
  await client.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'schema_migrations'
          AND policyname = 'schema_migrations_admin_only'
      ) THEN
        CREATE POLICY schema_migrations_admin_only ON public.schema_migrations
          FOR SELECT TO authenticated USING (public.is_app_admin());
      END IF;
    END $$;
  `);
}

function listMigrations() {
  const files = fs.readdirSync(__dirname);
  const upFiles = files
    .filter((f) => f.endsWith('.up.sql'))
    .sort();
  return upFiles.map((f) => {
    const base = f.replace(/\.up\.sql$/, '');
    const downFile = `${base}.down.sql`;
    if (!fs.existsSync(path.join(__dirname, downFile))) {
      throw new Error(`Missing paired down migration for ${f}: expected ${downFile}`);
    }
    const version = base.split('_')[0];
    return {
      version,
      name: base,
      upPath: path.join(__dirname, f),
      downPath: path.join(__dirname, downFile),
    };
  });
}

async function getClient() {
  const url = loadDirectDbUrl();
  const client = new Client({
    connectionString: url,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  return client;
}

async function cmdStatus(client) {
  await ensureMigrationsTable(client);
  const res = await client.query('SELECT version, name, checksum, applied_at FROM public.schema_migrations ORDER BY version');
  const appliedMap = new Map(res.rows.map((r) => [r.version, r]));
  const migrations = listMigrations();
  console.table(
    migrations.map((m) => {
      const row = appliedMap.get(m.version);
      return {
        version: m.version,
        name: m.name,
        applied: Boolean(row),
        applied_at: row?.applied_at ?? null,
      };
    })
  );
}

async function cmdUp(client, targetVersion = null) {
  await ensureMigrationsTable(client);
  const appliedRes = await client.query('SELECT version, checksum FROM public.schema_migrations');
  const applied = new Map(appliedRes.rows.map((r) => [r.version, r.checksum]));
  const migrations = listMigrations();

  let count = 0;
  for (const m of migrations) {
    if (targetVersion && m.version !== targetVersion && m.name !== targetVersion) {
      continue;
    }
    const sql = fs.readFileSync(m.upPath, 'utf8');
    const sum = sha256(sql);
    if (applied.has(m.version)) {
      if (applied.get(m.version) !== sum) {
        console.warn(`[WARN] Migration ${m.name} already applied with different checksum.`);
      } else {
        console.log(`[SKIP] ${m.name} already applied.`);
      }
      continue;
    }

    console.log(`[APPLY UP] ${m.name} ...`);
    await client.query('BEGIN');
    try {
      await client.query(sql);
      await client.query(
        'INSERT INTO public.schema_migrations (version, name, checksum) VALUES ($1, $2, $3)',
        [m.version, m.name, sum]
      );
      await client.query('COMMIT');
      console.log(`[OK] Applied ${m.name}`);
      count++;
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`[FAIL] ${m.name}:`, err.message);
      throw err;
    }
  }
  console.log(`Done. Newly applied migrations: ${count}`);
}

async function cmdDown(client, target) {
  if (!target) {
    throw new Error('Specify a version or migration name to roll back, e.g. node migrate.mjs down 001');
  }
  await ensureMigrationsTable(client);
  const migrations = listMigrations();
  const match = migrations.find((m) => m.version === target || m.name === target);
  if (!match) {
    throw new Error(`Migration "${target}" not found.`);
  }
  const appliedRes = await client.query('SELECT version FROM public.schema_migrations WHERE version = $1', [match.version]);
  if (appliedRes.rows.length === 0) {
    console.log(`[SKIP] ${match.name} is not currently applied.`);
    return;
  }

  const downSql = fs.readFileSync(match.downPath, 'utf8');
  console.log(`[ROLLBACK DOWN] ${match.name} ...`);
  await client.query('BEGIN');
  try {
    await client.query(downSql);
    await client.query('DELETE FROM public.schema_migrations WHERE version = $1', [match.version]);
    await client.query('COMMIT');
    console.log(`[OK] Rolled back ${match.name}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(`[FAIL DOWN] ${match.name}:`, err.message);
    throw err;
  }
}

async function cmdVerify(client) {
  await ensureMigrationsTable(client);
  console.log('=== 1. RLS Tables With Zero Policies ===');
  const zeroPols = await client.query(`
    SELECT c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = true
      AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid)
    ORDER BY c.relname;
  `);
  console.log('Count:', zeroPols.rows.length, zeroPols.rows.map((r) => r.table_name));

  console.log('=== 2. Tables Without RLS Enabled ===');
  const noRls = await client.query(`
    SELECT c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = false
    ORDER BY c.relname;
  `);
  console.log('Count:', noRls.rows.length, noRls.rows.map((r) => r.table_name));

  console.log('=== 3. Active Auth Users Without Profile ===');
  const missingProf = await client.query(`
    SELECT count(*)::int AS cnt
    FROM auth.users u
    LEFT JOIN public.profiles p ON p.id = u.id
    WHERE u.deleted_at IS NULL AND p.id IS NULL;
  `);
  console.log('Count:', missingProf.rows[0].cnt);

  console.log('=== 4. Remaining zev_fmc / zev_fcm References ===');
  const fcmCols = await client.query(`
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name IN ('zev_fmc', 'zev_fcm');
  `);
  const fcmFuncs = await client.query(`
    SELECT p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind IN ('f','p')
      AND pg_get_functiondef(p.oid) ~* '(zev_fmc|zev_fcm)';
  `);
  const fcmViews = await client.query(`
    SELECT viewname
    FROM pg_views
    WHERE schemaname = 'public' AND definition ~* '(zev_fmc|zev_fcm)';
  `);
  console.log({
    columns: fcmCols.rows.length,
    functions: fcmFuncs.rows.length,
    views: fcmViews.rows.length,
  });

  console.log('=== 5. Orphan FK Checks ===');
  const orphanLikes = await client.query(`SELECT count(*)::int AS cnt FROM public.discussion_likes dl WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = dl.student_id);`);
  const orphanComments = await client.query(`SELECT count(*)::int AS cnt FROM public.discussion_comments dc WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = dc.student_id);`);
  const orphanNotifs = await client.query(`SELECT count(*)::int AS cnt FROM public.user_notifications un WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = un.user_id);`);
  console.log({
    orphan_likes: orphanLikes.rows[0].cnt,
    orphan_comments: orphanComments.rows[0].cnt,
    orphan_notifs: orphanNotifs.rows[0].cnt,
  });

  console.log('=== 6. Counter Consistency Check ===');
  const driftReels = await client.query(`
    SELECT count(*)::int AS cnt
    FROM public.reels r
    WHERE r.likes_count <> (SELECT count(*) FROM public.reel_likes rl WHERE rl.reel_id = r.id)
       OR r.comments_count <> (SELECT count(*) FROM public.reel_comments rc WHERE rc.reel_id = r.id AND rc.deleted_at IS NULL)
       OR r.views_count < (SELECT count(*) FROM public.reel_views rv WHERE rv.reel_id = r.id);
  `).catch(() => ({ rows: [{ cnt: -1 }] }));
  const driftPosts = await client.query(`
    SELECT count(*)::int AS cnt
    FROM public.discussion_posts dp
    WHERE dp.likes_count <> (SELECT count(*) FROM public.discussion_likes dl WHERE dl.post_id = dp.id)
       OR dp.comments_count <> (SELECT count(*) FROM public.discussion_comments dc WHERE dc.post_id = dp.id AND dc.deleted_at IS NULL);
  `).catch(() => ({ rows: [{ cnt: -1 }] }));
  console.log({
    drifted_reels: driftReels.rows[0].cnt,
    drifted_posts: driftPosts.rows[0].cnt,
  });

  const failed =
    zeroPols.rows.length > 0 ||
    noRls.rows.length > 0 ||
    missingProf.rows[0].cnt > 0 ||
    fcmCols.rows.length > 0 ||
    fcmFuncs.rows.length > 0 ||
    fcmViews.rows.length > 0 ||
    orphanLikes.rows[0].cnt > 0 ||
    orphanComments.rows[0].cnt > 0 ||
    orphanNotifs.rows[0].cnt > 0 ||
    driftReels.rows[0].cnt !== 0 ||
    driftPosts.rows[0].cnt !== 0;

  if (failed) {
    process.exitCode = 1;
  } else {
    console.log('ALL VERIFICATION CHECKS PASSED (0 anomalies).');
  }
}

async function main() {
  const [, , cmd = 'status', arg] = process.argv;
  const client = await getClient();
  try {
    if (cmd === 'status') await cmdStatus(client);
    else if (cmd === 'up') await cmdUp(client, arg || null);
    else if (cmd === 'down') await cmdDown(client, arg);
    else if (cmd === 'verify') await cmdVerify(client);
    else {
      console.error(`Unknown command: ${cmd}`);
      process.exitCode = 1;
    }
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

