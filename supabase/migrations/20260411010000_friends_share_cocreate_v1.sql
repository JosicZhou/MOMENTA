-- Friends + Share + Cocreate V1
-- Extends the earlier profile/share schema with:
-- - profiles display_name / friend_code
-- - friendships request lifecycle
-- - cocreate_sessions
-- - music_generations continuation metadata
-- - RPCs used by FriendService / CocreateService

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text,
  avatar_url text,
  friend_code text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS avatar_url text,
  ADD COLUMN IF NOT EXISTS friend_code text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_friend_code ON profiles(friend_code);

CREATE TABLE IF NOT EXISTS friendships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending',
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (user_id <> friend_id),
  CHECK (status IN ('pending', 'accepted'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_pair
  ON friendships (LEAST(user_id, friend_id), GREATEST(user_id, friend_id));

ALTER TABLE music_generations
  ADD COLUMN IF NOT EXISTS continue_at_sec double precision,
  ADD COLUMN IF NOT EXISTS parent_audio_id text,
  ADD COLUMN IF NOT EXISTS cocreate_session_id uuid,
  ADD COLUMN IF NOT EXISTS duration double precision;

CREATE TABLE IF NOT EXISTS cocreate_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invitee_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'half_ready',
  source_task_id text NOT NULL,
  source_title text,
  source_image_url text,
  suno_audio_id text,
  continue_at_sec double precision NOT NULL,
  model text NOT NULL DEFAULT 'V5',
  profile_a jsonb NOT NULL DEFAULT '{}'::jsonb,
  extend_task_id text,
  profile_b jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  CHECK (status IN ('half_ready', 'invited', 'extending', 'completed', 'expired'))
);

CREATE INDEX IF NOT EXISTS idx_cocreate_creator_id ON cocreate_sessions(creator_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cocreate_invitee_id ON cocreate_sessions(invitee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cocreate_source_task_id ON cocreate_sessions(source_task_id);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE cocreate_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read profiles" ON profiles;
CREATE POLICY "Users can read profiles"
  ON profiles FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile"
  ON profiles FOR ALL
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can read related friendships" ON friendships;
CREATE POLICY "Users can read related friendships"
  ON friendships FOR SELECT
  USING (auth.uid() = user_id OR auth.uid() = friend_id);

DROP POLICY IF EXISTS "Users can insert own friendships" ON friendships;
CREATE POLICY "Users can insert own friendships"
  ON friendships FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update related friendships" ON friendships;
CREATE POLICY "Users can update related friendships"
  ON friendships FOR UPDATE
  USING (auth.uid() = user_id OR auth.uid() = friend_id)
  WITH CHECK (auth.uid() = user_id OR auth.uid() = friend_id);

DROP POLICY IF EXISTS "Users can delete related friendships" ON friendships;
CREATE POLICY "Users can delete related friendships"
  ON friendships FOR DELETE
  USING (auth.uid() = user_id OR auth.uid() = friend_id);

DROP POLICY IF EXISTS "Users can read related cocreate sessions" ON cocreate_sessions;
CREATE POLICY "Users can read related cocreate sessions"
  ON cocreate_sessions FOR SELECT
  USING (auth.uid() = creator_id OR auth.uid() = invitee_id);

DROP POLICY IF EXISTS "Creators can insert cocreate sessions" ON cocreate_sessions;
CREATE POLICY "Creators can insert cocreate sessions"
  ON cocreate_sessions FOR INSERT
  WITH CHECK (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Related users can update cocreate sessions" ON cocreate_sessions;
CREATE POLICY "Related users can update cocreate sessions"
  ON cocreate_sessions FOR UPDATE
  USING (auth.uid() = creator_id OR auth.uid() = invitee_id)
  WITH CHECK (auth.uid() = creator_id OR auth.uid() = invitee_id);

CREATE OR REPLACE FUNCTION upsert_profile(p_user_id uuid, p_display_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  generated_code text;
BEGIN
  generated_code := upper(left(regexp_replace(coalesce(p_display_name, 'MOMENTA'), '[^A-Za-z0-9]', '', 'g') || 'MOM', 3))
    || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));

  INSERT INTO profiles (id, display_name, friend_code, created_at, updated_at)
  VALUES (p_user_id, nullif(trim(p_display_name), ''), generated_code, now(), now())
  ON CONFLICT (id) DO UPDATE
    SET display_name = COALESCE(nullif(trim(EXCLUDED.display_name), ''), profiles.display_name),
        friend_code = COALESCE(profiles.friend_code, EXCLUDED.friend_code),
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION find_user_by_friend_code(p_code text)
RETURNS TABLE (
  id uuid,
  display_name text,
  avatar_url text,
  friend_code text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.display_name, p.avatar_url, p.friend_code
  FROM profiles p
  WHERE upper(p.friend_code) = upper(trim(p_code))
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION send_friend_request(p_from_user_id uuid, p_to_user_id uuid, p_note text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_row friendships%ROWTYPE;
BEGIN
  IF p_from_user_id = p_to_user_id THEN
    RETURN 'cannot_add_self';
  END IF;

  SELECT *
  INTO existing_row
  FROM friendships
  WHERE LEAST(user_id, friend_id) = LEAST(p_from_user_id, p_to_user_id)
    AND GREATEST(user_id, friend_id) = GREATEST(p_from_user_id, p_to_user_id)
  LIMIT 1;

  IF existing_row.id IS NOT NULL THEN
    IF existing_row.status = 'accepted' THEN
      RETURN 'already_friends';
    END IF;
    RETURN 'already_pending';
  END IF;

  INSERT INTO friendships (user_id, friend_id, status, note, created_at, updated_at)
  VALUES (p_from_user_id, p_to_user_id, 'pending', p_note, now(), now());

  RETURN 'sent';
END;
$$;

CREATE OR REPLACE FUNCTION get_sent_requests(p_user_id uuid)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  friend_id uuid,
  status text,
  note text,
  created_at timestamptz,
  display_name text,
  avatar_url text,
  friend_code text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    f.id,
    f.user_id,
    f.friend_id,
    f.status,
    f.note,
    f.created_at,
    p.display_name,
    p.avatar_url,
    p.friend_code
  FROM friendships f
  LEFT JOIN profiles p ON p.id = f.friend_id
  WHERE f.user_id = p_user_id
    AND f.status = 'pending'
  ORDER BY f.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION get_shared_songs_for_user(p_to_user_id uuid)
RETURNS SETOF music_generations
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT mg.*
  FROM music_generations mg
  INNER JOIN music_shared ms
    ON ms.music_id = mg.task_id
   AND ms.from_user_id = mg.user_id
  WHERE ms.to_user_id = p_to_user_id
  ORDER BY ms.created_at DESC;
$$;
