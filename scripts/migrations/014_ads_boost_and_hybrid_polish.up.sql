-- 014_ads_boost_and_hybrid_polish.up.sql
-- Adds Boost/Promote Previous Post support (`source_post_id`),
-- prepaid wallet balance guard & multi-slot campaign rotation (`p_exclude_campaign_ids`)
-- in `serve_eligible_ad`, and dashboard telemetry parity.

ALTER TABLE public.ad_campaigns
  ADD COLUMN IF NOT EXISTS source_post_id uuid REFERENCES public.discussion_posts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ad_campaigns_source_post
  ON public.ad_campaigns (source_post_id)
  WHERE source_post_id IS NOT NULL;

DROP FUNCTION IF EXISTS public.create_ad_campaign_with_creative(
  text, text, text, text, numeric, numeric, numeric, text, text, text, text, text, text,
  text[], text[], text[], integer, integer, text, timestamptz, timestamptz, integer, integer
);

DROP FUNCTION IF EXISTS public.serve_eligible_ad(
  text, uuid, text, text
);

CREATE OR REPLACE FUNCTION public.create_ad_campaign_with_creative(
  p_name text,
  p_objective text DEFAULT 'awareness',
  p_placement text DEFAULT 'feed',
  p_pricing_model text DEFAULT 'CPM',
  p_bid_amount numeric DEFAULT 2.50,
  p_daily_budget numeric DEFAULT 10.00,
  p_total_budget numeric DEFAULT 50.00,
  p_title text DEFAULT '',
  p_body text DEFAULT '',
  p_media_url text DEFAULT NULL,
  p_media_type text DEFAULT 'image',
  p_cta_label text DEFAULT 'Learn More',
  p_destination_url text DEFAULT 'https://www.zevapp.com',
  p_countries text[] DEFAULT '{}',
  p_languages text[] DEFAULT '{}',
  p_interests text[] DEFAULT '{}',
  p_min_age integer DEFAULT 13,
  p_max_age integer DEFAULT 99,
  p_gender text DEFAULT 'all',
  p_starts_at timestamptz DEFAULT now(),
  p_ends_at timestamptz DEFAULT NULL,
  p_daily_frequency_cap integer DEFAULT 3,
  p_min_cooldown_seconds integer DEFAULT 300,
  p_source_post_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adv public.advertisers%ROWTYPE;
  v_campaign_id uuid;
  v_creative_id uuid;
  v_placement text := lower(trim(COALESCE(p_placement, 'feed')));
  v_pricing text := upper(trim(COALESCE(p_pricing_model, 'CPM')));
  v_media_type text := lower(trim(COALESCE(p_media_type, 'image')));
  v_dest text := trim(COALESCE(p_destination_url, ''));
  v_post_owner uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_adv FROM public.advertisers WHERE user_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Please register your advertiser profile first' USING ERRCODE = 'P0001';
  END IF;

  IF v_adv.status = 'suspended' THEN
    RAISE EXCEPTION 'Advertiser account is suspended' USING ERRCODE = '42501';
  END IF;

  IF p_source_post_id IS NOT NULL THEN
    SELECT student_id INTO v_post_owner
    FROM public.discussion_posts
    WHERE id = p_source_post_id AND deleted_at IS NULL;

    IF v_post_owner IS NULL THEN
      RAISE EXCEPTION 'Source post was not found or has been deleted' USING ERRCODE = 'P0001';
    END IF;

    IF v_post_owner IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'You can only advertise your own posts' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF v_placement NOT IN ('feed', 'story', 'reel', 'explore', 'all') THEN
    RAISE EXCEPTION 'Invalid placement: %', p_placement USING ERRCODE = '22023';
  END IF;

  IF v_pricing NOT IN ('CPM', 'CPC', 'CPA') THEN
    RAISE EXCEPTION 'Invalid pricing model: %', p_pricing_model USING ERRCODE = '22023';
  END IF;

  IF v_media_type NOT IN ('image', 'video') THEN
    v_media_type := 'image';
  END IF;

  IF COALESCE(p_bid_amount, 0) <= 0 OR COALESCE(p_daily_budget, 0) < 1 OR COALESCE(p_total_budget, 0) < p_daily_budget THEN
    RAISE EXCEPTION 'Invalid budget or bid amount (daily >= 1, total >= daily, bid > 0)' USING ERRCODE = '22023';
  END IF;

  IF length(trim(COALESCE(p_name, ''))) < 2 OR length(trim(COALESCE(p_title, ''))) < 2 OR length(trim(COALESCE(p_body, ''))) < 2 THEN
    RAISE EXCEPTION 'Campaign name, creative headline, and body are required' USING ERRCODE = '22023';
  END IF;

  IF v_dest !~* '^https?://' THEN
    RAISE EXCEPTION 'Destination URL must begin with http:// or https://' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.ad_campaigns (
    advertiser_id, source_post_id, name, objective, placement, status, pricing_model,
    bid_amount, daily_budget, total_budget, spent_amount, spent_today, spent_today_date,
    starts_at, ends_at, daily_frequency_cap, min_cooldown_seconds, created_at, updated_at
  ) VALUES (
    v_adv.id,
    p_source_post_id,
    left(trim(p_name), 120),
    COALESCE(NULLIF(trim(p_objective), ''), 'awareness'),
    v_placement,
    'pending_review',
    v_pricing,
    ROUND(p_bid_amount, 4),
    ROUND(p_daily_budget, 2),
    ROUND(p_total_budget, 2),
    0.000000,
    0.000000,
    CURRENT_DATE,
    COALESCE(p_starts_at, now()),
    p_ends_at,
    LEAST(50, GREATEST(1, COALESCE(p_daily_frequency_cap, 3))),
    LEAST(86400, GREATEST(0, COALESCE(p_min_cooldown_seconds, 300))),
    now(),
    now()
  )
  RETURNING id INTO v_campaign_id;

  INSERT INTO public.ad_creatives (
    campaign_id, title, body, media_url, media_type, cta_label, destination_url, status, created_at, updated_at
  ) VALUES (
    v_campaign_id,
    left(trim(p_title), 140),
    left(trim(p_body), 500),
    NULLIF(trim(COALESCE(p_media_url, '')), ''),
    v_media_type,
    left(COALESCE(NULLIF(trim(p_cta_label), ''), 'Learn More'), 40),
    v_dest,
    'pending_review',
    now(),
    now()
  )
  RETURNING id INTO v_creative_id;

  INSERT INTO public.ad_targeting (
    campaign_id, countries, languages, interests, min_age, max_age, gender, created_at, updated_at
  ) VALUES (
    v_campaign_id,
    COALESCE(p_countries, '{}'),
    COALESCE(p_languages, '{}'),
    COALESCE(p_interests, '{}'),
    GREATEST(13, COALESCE(p_min_age, 13)),
    LEAST(99, GREATEST(GREATEST(13, COALESCE(p_min_age, 13)), COALESCE(p_max_age, 99))),
    COALESCE(NULLIF(trim(p_gender), ''), 'all'),
    now(),
    now()
  );

  RETURN jsonb_build_object(
    'ok', true,
    'campaign_id', v_campaign_id,
    'creative_id', v_creative_id,
    'source_post_id', p_source_post_id,
    'status', 'pending_review'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.serve_eligible_ad(
  p_placement text DEFAULT 'feed',
  p_user_id uuid DEFAULT NULL,
  p_country text DEFAULT NULL,
  p_interest text DEFAULT NULL,
  p_exclude_campaign_ids uuid[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_placement text := lower(trim(COALESCE(p_placement, 'feed')));
  v_uid uuid;
  v_country text := NULLIF(trim(COALESCE(p_country, '')), '');
  v_interest text := NULLIF(trim(COALESCE(p_interest, '')), '');
  v_rec record;
BEGIN
  IF v_placement NOT IN ('feed', 'story', 'reel', 'explore') THEN
    v_placement := 'feed';
  END IF;

  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role' THEN
    v_uid := COALESCE(p_user_id, auth.uid());
  ELSE
    v_uid := auth.uid();
  END IF;

  IF v_uid IS NOT NULL AND v_country IS NULL THEN
    SELECT NULLIF(trim(country), '') INTO v_country
    FROM public.profiles
    WHERE id = v_uid;
  END IF;

  SELECT
    c.id AS campaign_id,
    c.source_post_id,
    c.name AS campaign_name,
    c.objective,
    c.placement AS campaign_placement,
    c.pricing_model,
    c.bid_amount,
    c.daily_frequency_cap,
    c.min_cooldown_seconds,
    cr.id AS creative_id,
    cr.title,
    cr.body,
    cr.media_url,
    cr.media_type,
    cr.cta_label,
    cr.destination_url,
    adv.id AS advertiser_id,
    adv.business_name
  INTO v_rec
  FROM public.ad_campaigns c
  JOIN public.advertisers adv ON adv.id = c.advertiser_id
  JOIN public.ad_creatives cr ON cr.campaign_id = c.id
  LEFT JOIN public.ad_targeting t ON t.campaign_id = c.id
  WHERE adv.status = 'approved'
    AND adv.balance > 0
    AND c.status = 'active'
    AND c.approved_at IS NOT NULL
    AND cr.status = 'approved'
    AND (c.placement = v_placement OR c.placement = 'all')
    AND c.starts_at <= now()
    AND (c.ends_at IS NULL OR c.ends_at > now())
    AND c.spent_amount < c.total_budget
    AND (
      CASE WHEN c.spent_today_date = CURRENT_DATE THEN c.spent_today ELSE 0 END
    ) < c.daily_budget
    AND (
      p_exclude_campaign_ids IS NULL
      OR cardinality(p_exclude_campaign_ids) = 0
      OR NOT (c.id = ANY (p_exclude_campaign_ids))
    )
    AND (
      t.id IS NULL
      OR cardinality(t.countries) = 0
      OR (v_country IS NOT NULL AND lower(v_country) = ANY (SELECT lower(x) FROM unnest(t.countries) AS x))
    )
    AND (
      t.id IS NULL
      OR cardinality(t.interests) = 0
      OR (v_interest IS NOT NULL AND lower(v_interest) = ANY (SELECT lower(x) FROM unnest(t.interests) AS x))
    )
    AND (
      v_uid IS NULL
      OR NOT EXISTS (
        SELECT 1 FROM public.ad_frequency_caps fc
        WHERE fc.campaign_id = c.id
          AND fc.user_id = v_uid
          AND fc.window_date = CURRENT_DATE
          AND (
            fc.impressions_today >= c.daily_frequency_cap
            OR (
              c.min_cooldown_seconds > 0
              AND fc.last_shown_at > now() - make_interval(secs => c.min_cooldown_seconds)
            )
          )
      )
    )
  ORDER BY
    (adv.user_id = v_uid) ASC NULLS LAST,
    (c.spent_amount / GREATEST(c.total_budget, 1)) ASC,
    random()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'ad', NULL);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'ad', jsonb_build_object(
      'campaign_id', v_rec.campaign_id,
      'creative_id', v_rec.creative_id,
      'source_post_id', v_rec.source_post_id,
      'advertiser_id', v_rec.advertiser_id,
      'business_name', v_rec.business_name,
      'campaign_name', v_rec.campaign_name,
      'objective', v_rec.objective,
      'placement', v_placement,
      'pricing_model', v_rec.pricing_model,
      'title', v_rec.title,
      'body', v_rec.body,
      'media_url', v_rec.media_url,
      'media_type', v_rec.media_type,
      'cta_label', v_rec.cta_label,
      'destination_url', v_rec.destination_url
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_advertiser_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adv public.advertisers%ROWTYPE;
  v_campaigns jsonb := '[]'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_totals jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_adv FROM public.advertisers WHERE user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'advertiser', NULL,
      'campaigns', '[]'::jsonb,
      'invoices', '[]'::jsonb,
      'totals', jsonb_build_object(
        'impressions', 0, 'clicks', 0, 'conversions', 0, 'spent', 0, 'ctr', 0
      )
    );
  END IF;

  SELECT COALESCE(jsonb_agg(row_json ORDER BY created_at DESC), '[]'::jsonb)
  INTO v_campaigns
  FROM (
    SELECT
      c.created_at,
      jsonb_build_object(
        'id', c.id,
        'source_post_id', c.source_post_id,
        'name', c.name,
        'objective', c.objective,
        'placement', c.placement,
        'status', c.status,
        'pricing_model', c.pricing_model,
        'bid_amount', c.bid_amount,
        'daily_budget', c.daily_budget,
        'total_budget', c.total_budget,
        'spent_amount', c.spent_amount,
        'spent_today', CASE WHEN c.spent_today_date = CURRENT_DATE THEN c.spent_today ELSE 0 END,
        'impressions_count', c.impressions_count,
        'clicks_count', c.clicks_count,
        'conversions_count', c.conversions_count,
        'ctr', CASE WHEN c.impressions_count > 0 THEN ROUND((c.clicks_count::numeric / c.impressions_count::numeric) * 100.0, 2) ELSE 0 END,
        'daily_frequency_cap', c.daily_frequency_cap,
        'min_cooldown_seconds', c.min_cooldown_seconds,
        'starts_at', c.starts_at,
        'ends_at', c.ends_at,
        'approved_at', c.approved_at,
        'rejection_reason', c.rejection_reason,
        'created_at', c.created_at,
        'creative', (
          SELECT jsonb_build_object(
            'id', cr.id, 'title', cr.title, 'body', cr.body,
            'media_url', cr.media_url, 'media_type', cr.media_type,
            'cta_label', cr.cta_label, 'destination_url', cr.destination_url,
            'status', cr.status
          )
          FROM public.ad_creatives cr
          WHERE cr.campaign_id = c.id
          ORDER BY cr.created_at DESC
          LIMIT 1
        ),
        'targeting', (
          SELECT jsonb_build_object(
            'countries', t.countries, 'languages', t.languages,
            'interests', t.interests, 'min_age', t.min_age,
            'max_age', t.max_age, 'gender', t.gender
          )
          FROM public.ad_targeting t
          WHERE t.campaign_id = c.id
          LIMIT 1
        )
      ) AS row_json
    FROM public.ad_campaigns c
    WHERE c.advertiser_id = v_adv.id
  ) sub;

  SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.created_at DESC), '[]'::jsonb)
  INTO v_invoices
  FROM public.ad_invoices i
  WHERE i.advertiser_id = v_adv.id;

  SELECT jsonb_build_object(
    'impressions', COALESCE(SUM(impressions_count), 0),
    'clicks', COALESCE(SUM(clicks_count), 0),
    'conversions', COALESCE(SUM(conversions_count), 0),
    'spent', ROUND(COALESCE(SUM(spent_amount), 0), 2),
    'ctr', CASE WHEN COALESCE(SUM(impressions_count), 0) > 0
      THEN ROUND((COALESCE(SUM(clicks_count), 0)::numeric / SUM(impressions_count)::numeric) * 100.0, 2)
      ELSE 0 END
  )
  INTO v_totals
  FROM public.ad_campaigns
  WHERE advertiser_id = v_adv.id;

  RETURN jsonb_build_object(
    'ok', true,
    'advertiser', to_jsonb(v_adv),
    'campaigns', v_campaigns,
    'invoices', v_invoices,
    'totals', v_totals
  );
END;
$$;
