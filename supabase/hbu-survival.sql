-- HBU Survival shared-world multiplayer and player saves.
-- Run this once in Supabase SQL Editor AFTER supabase/accounts-and-dms.sql.
-- The browser calls this only through the HBU2 Cloudflare gateway.

DO $$
BEGIN
  IF to_regprocedure('public.hbu_login(text,text)') IS NULL THEN
    RAISE EXCEPTION 'Install supabase/accounts-and-dms.sql before hbu-survival.sql; public.hbu_login(text,text) is missing.';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.hbu_survival_players (
  username text PRIMARY KEY,
  x double precision NOT NULL DEFAULT 1200,
  y double precision NOT NULL DEFAULT 900,
  yaw double precision NOT NULL DEFAULT 0,
  health numeric NOT NULL DEFAULT 100,
  hunger numeric NOT NULL DEFAULT 100,
  thirst numeric NOT NULL DEFAULT 100,
  inventory jsonb NOT NULL DEFAULT '{"wood":0,"stone":0,"berries":0,"fiber":0}'::jsonb,
  crafted jsonb NOT NULL DEFAULT '{"axe":0,"pickaxe":0,"torch":0,"hammer":0,"walls":0}'::jsonb,
  last_seen timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hbu_survival_players_inventory_object CHECK (jsonb_typeof(inventory) = 'object'),
  CONSTRAINT hbu_survival_players_crafted_object CHECK (jsonb_typeof(crafted) = 'object')
);

CREATE INDEX IF NOT EXISTS hbu_survival_players_last_seen_idx
  ON public.hbu_survival_players (last_seen DESC);

-- Separate existing first-time accounts that were previously stacked at the
-- shared default spawn. The coordinates are stable for each username.
WITH default_spawn_players AS (
  SELECT username, row_number() OVER (ORDER BY username) - 1 AS spawn_slot
  FROM public.hbu_survival_players
  WHERE x = 1200 AND y = 900
)
UPDATE public.hbu_survival_players AS player
SET
  x = 1200 + ((default_spawn_players.spawn_slot % 9) - 4) * 72,
  y = 900 + ((default_spawn_players.spawn_slot / 9) - 4) * 72,
  updated_at = now()
FROM default_spawn_players
WHERE player.username = default_spawn_players.username;

CREATE TABLE IF NOT EXISTS public.hbu_survival_world (
  world_id text PRIMARY KEY DEFAULT 'greenwild' CHECK (world_id = 'greenwild'),
  removed text[] NOT NULL DEFAULT '{}',
  camps jsonb NOT NULL DEFAULT '[]'::jsonb,
  walls jsonb NOT NULL DEFAULT '[]'::jsonb,
  world_minutes numeric NOT NULL DEFAULT 480,
  day integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hbu_survival_world_camps_array CHECK (jsonb_typeof(camps) = 'array'),
  CONSTRAINT hbu_survival_world_walls_array CHECK (jsonb_typeof(walls) = 'array')
);

INSERT INTO public.hbu_survival_world (world_id)
VALUES ('greenwild')
ON CONFLICT (world_id) DO NOTHING;

ALTER TABLE public.hbu_survival_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hbu_survival_world ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.hbu_survival_players FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.hbu_survival_world FROM PUBLIC, anon, authenticated;

-- Converts only small, non-negative integer strings and ignores unexpected values.
CREATE OR REPLACE FUNCTION public.hbu_survival_safe_count(p_data jsonb, p_key text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $$
  SELECT CASE
    WHEN COALESCE(p_data ->> p_key, '') ~ '^[0-9]{1,6}$'
      THEN LEAST(999999, (p_data ->> p_key)::integer)
    ELSE 0
  END;
$$;
REVOKE ALL ON FUNCTION public.hbu_survival_safe_count(jsonb, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.hbu_survival_sync(
  p_username text,
  p_password text,
  p_initialize boolean,
  p_leave boolean,
  p_x double precision,
  p_y double precision,
  p_yaw double precision,
  p_health numeric,
  p_hunger numeric,
  p_thirst numeric,
  p_inventory jsonb,
  p_crafted jsonb,
  p_removed text[],
  p_camps jsonb,
  p_walls jsonb,
  p_world_minutes numeric,
  p_day integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_username text;
  v_inventory jsonb;
  v_crafted jsonb;
  v_self public.hbu_survival_players%ROWTYPE;
  v_world public.hbu_survival_world%ROWTYPE;
  v_players jsonb;
  v_spawn_hash bigint;
  v_spawn_x double precision;
  v_spawn_y double precision;
BEGIN
  -- Authenticate every call against the existing HBU2 account table.
  SELECT public.hbu_login(p_username, p_password) INTO v_username;
  IF v_username IS NULL THEN
    RAISE EXCEPTION 'Wrong username or password';
  END IF;

  IF jsonb_typeof(COALESCE(p_inventory, '{}'::jsonb)) <> 'object'
     OR jsonb_typeof(COALESCE(p_crafted, '{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'Invalid survivor inventory data';
  END IF;
  IF jsonb_typeof(COALESCE(p_camps, '[]'::jsonb)) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Invalid campfire data';
  END IF;
  IF jsonb_array_length(COALESCE(p_camps, '[]'::jsonb)) > 500 THEN
    RAISE EXCEPTION 'Too many campfires';
  END IF;
  IF jsonb_typeof(COALESCE(p_walls, '[]'::jsonb)) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Invalid building data';
  END IF;
  IF jsonb_array_length(COALESCE(p_walls, '[]'::jsonb)) > 500 THEN
    RAISE EXCEPTION 'Too many walls';
  END IF;
  IF COALESCE(array_length(p_removed, 1), 0) > 5000 THEN
    RAISE EXCEPTION 'Too many removed resources';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_removed, '{}'::text[])) AS items(item)
    WHERE item !~ '^[A-Za-z0-9_-]{1,64}$'
  ) THEN
    RAISE EXCEPTION 'Invalid resource identifier';
  END IF;

  v_inventory := jsonb_build_object(
    'wood', public.hbu_survival_safe_count(p_inventory, 'wood'),
    'stone', public.hbu_survival_safe_count(p_inventory, 'stone'),
    'berries', public.hbu_survival_safe_count(p_inventory, 'berries'),
    'fiber', public.hbu_survival_safe_count(p_inventory, 'fiber')
  );
  v_crafted := jsonb_build_object(
    'axe', public.hbu_survival_safe_count(p_crafted, 'axe'),
    'pickaxe', public.hbu_survival_safe_count(p_crafted, 'pickaxe'),
    'torch', public.hbu_survival_safe_count(p_crafted, 'torch'),
    'hammer', public.hbu_survival_safe_count(p_crafted, 'hammer'),
    'walls', public.hbu_survival_safe_count(p_crafted, 'walls')
  );

  -- The first request for an account creates its save. Later initialization
  -- requests preserve the server save and only refresh online presence.
  IF COALESCE(p_initialize, false) THEN
    -- Allocate a nearby free grid cell so new accounts do not overlap.
    -- The transaction lock prevents two simultaneous first joins selecting
    -- the same cell.
    PERFORM pg_advisory_xact_lock(hashtext('hbu_survival_spawn'));
    v_spawn_hash := abs(hashtext(lower(v_username))::bigint);
    SELECT
      1200 + ((slots.slot % 9) - 4) * 72,
      900 + ((slots.slot / 9) - 4) * 72
    INTO v_spawn_x, v_spawn_y
    FROM generate_series(0, 80) AS slots(slot)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.hbu_survival_players AS existing
      WHERE abs(existing.x - (1200 + ((slots.slot % 9) - 4) * 72)) < 36
        AND abs(existing.y - (900 + ((slots.slot / 9) - 4) * 72)) < 36
    )
    ORDER BY mod(slots.slot + v_spawn_hash, 81)
    LIMIT 1;

    IF v_spawn_x IS NULL OR v_spawn_y IS NULL THEN
      RAISE EXCEPTION 'The shared world has no available survivor spawn positions';
    END IF;

    INSERT INTO public.hbu_survival_players (
      username, x, y, yaw, health, hunger, thirst, inventory, crafted, last_seen, updated_at
    ) VALUES (
      v_username,
      v_spawn_x,
      v_spawn_y,
      GREATEST(-100000, LEAST(100000, COALESCE(p_yaw, 0))),
      GREATEST(0, LEAST(100, COALESCE(p_health, 100))),
      GREATEST(0, LEAST(100, COALESCE(p_hunger, 100))),
      GREATEST(0, LEAST(100, COALESCE(p_thirst, 100))),
      v_inventory, v_crafted, now(), now()
    )
    ON CONFLICT (username) DO UPDATE SET last_seen = now();
  ELSE
    INSERT INTO public.hbu_survival_players (
      username, x, y, yaw, health, hunger, thirst, inventory, crafted, last_seen, updated_at
    ) VALUES (
      v_username,
      GREATEST(-100000, LEAST(100000, COALESCE(p_x, 1200))),
      GREATEST(-100000, LEAST(100000, COALESCE(p_y, 900))),
      GREATEST(-100000, LEAST(100000, COALESCE(p_yaw, 0))),
      GREATEST(0, LEAST(100, COALESCE(p_health, 100))),
      GREATEST(0, LEAST(100, COALESCE(p_hunger, 100))),
      GREATEST(0, LEAST(100, COALESCE(p_thirst, 100))),
      v_inventory, v_crafted,
      CASE WHEN COALESCE(p_leave, false) THEN now() - interval '1 hour' ELSE now() END,
      now()
    )
    ON CONFLICT (username) DO UPDATE SET
      x = EXCLUDED.x,
      y = EXCLUDED.y,
      yaw = EXCLUDED.yaw,
      health = EXCLUDED.health,
      hunger = EXCLUDED.hunger,
      thirst = EXCLUDED.thirst,
      inventory = EXCLUDED.inventory,
      crafted = EXCLUDED.crafted,
      last_seen = EXCLUDED.last_seen,
      updated_at = now();
  END IF;

  -- Shared-world changes are merged, never replaced by one browser's snapshot.
  INSERT INTO public.hbu_survival_world (
    world_id, removed, camps, walls, world_minutes, day, updated_at
  ) VALUES (
    'greenwild',
    COALESCE(p_removed, '{}'::text[]),
    COALESCE(p_camps, '[]'::jsonb),
    COALESCE(p_walls, '[]'::jsonb),
    GREATEST(0, LEAST(1439, COALESCE(p_world_minutes, 480))),
    GREATEST(1, LEAST(1000000, COALESCE(p_day, 1))),
    now()
  )
  ON CONFLICT (world_id) DO UPDATE SET
    removed = (
      SELECT COALESCE(array_agg(DISTINCT resource_id ORDER BY resource_id), '{}'::text[])
      FROM unnest(public.hbu_survival_world.removed || EXCLUDED.removed) AS merged_ids(resource_id)
    ),
    camps = (
      SELECT COALESCE(jsonb_agg(value), '[]'::jsonb)
      FROM (SELECT DISTINCT value FROM jsonb_array_elements(public.hbu_survival_world.camps || EXCLUDED.camps) AS entries(value)) merged
    ),
    walls = (
      SELECT COALESCE(jsonb_agg(value), '[]'::jsonb)
      FROM (SELECT DISTINCT value FROM jsonb_array_elements(public.hbu_survival_world.walls || EXCLUDED.walls) AS entries(value)) merged
    ),
    world_minutes = EXCLUDED.world_minutes,
    day = GREATEST(public.hbu_survival_world.day, EXCLUDED.day),
    updated_at = now();

  SELECT * INTO v_self
  FROM public.hbu_survival_players
  WHERE username = v_username;

  SELECT * INTO v_world
  FROM public.hbu_survival_world
  WHERE world_id = 'greenwild';

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'name', player.username,
        'x', player.x,
        'y', player.y,
        'yaw', player.yaw,
        'last_seen', player.last_seen
      ) ORDER BY player.username
    ),
    '[]'::jsonb
  ) INTO v_players
  FROM (
    SELECT username, x, y, yaw, last_seen
    FROM public.hbu_survival_players
    WHERE last_seen > now() - interval '90 seconds'
    ORDER BY last_seen DESC
    LIMIT 60
  ) AS player;

  RETURN jsonb_build_object(
    'self', jsonb_build_object(
      'x', v_self.x,
      'y', v_self.y,
      'yaw', v_self.yaw,
      'health', v_self.health,
      'hunger', v_self.hunger,
      'thirst', v_self.thirst,
      'inventory', v_self.inventory,
      'crafted', v_self.crafted
    ),
    'world', jsonb_build_object(
      'removed', to_jsonb(v_world.removed),
      'camps', v_world.camps,
      'walls', v_world.walls,
      'world_minutes', v_world.world_minutes,
      'day', v_world.day
    ),
    'players', v_players
  );
END;
$$;

REVOKE ALL ON FUNCTION public.hbu_survival_sync(
  text, text, boolean, boolean, double precision, double precision, double precision,
  numeric, numeric, numeric, jsonb, jsonb, text[], jsonb, jsonb, numeric, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hbu_survival_sync(
  text, text, boolean, boolean, double precision, double precision, double precision,
  numeric, numeric, numeric, jsonb, jsonb, text[], jsonb, jsonb, numeric, integer
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';