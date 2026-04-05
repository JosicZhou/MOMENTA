-- =============================================================
-- MOMENTA — Complete Database Schema
-- 版本: 2025-04 (cocreate + friends + playlists + RLS)
--
-- 此文件是唯一权威的数据库定义，完全幂等（可重复执行）。
-- 在 Supabase Dashboard → SQL Editor 中整个粘贴运行。
--
-- 执行顺序（依赖关系保证）：
--   1. profiles 表变更
--   2. friendships 表
--   3. music_generations 列扩展
--   4. user_favorites / music_shared 表
--   5. cocreate_sessions 表
--   6. RLS 策略（所有表）
--   7. RPC 函数
--   8. Realtime Publication
-- =============================================================


-- ============================================================
-- 1. profiles 表（已存在，只补缺失列）
-- 原有字段: id, username, avatar_url, updated_at
-- ============================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS display_name TEXT,
  ADD COLUMN IF NOT EXISTS friend_code  TEXT UNIQUE DEFAULT substr(md5(random()::text), 1, 8),
  ADD COLUMN IF NOT EXISTS created_at   TIMESTAMPTZ DEFAULT now();

-- 把现有 username 同步到 display_name（一次性，display_name 为空时才覆盖）
UPDATE profiles
  SET display_name = username
  WHERE display_name IS NULL AND username IS NOT NULL;

-- 为历史行补 friend_code（默认值只对新插入行生效）
UPDATE profiles
  SET friend_code = substr(md5(random()::text || id::text), 1, 8)
  WHERE friend_code IS NULL;

-- 非空约束
ALTER TABLE profiles ALTER COLUMN friend_code SET NOT NULL;

-- RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "Anyone can read profiles"         ON profiles FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Users can insert own profile"     ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Users can update own profile"     ON profiles FOR UPDATE USING (auth.uid() = id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================
-- 2. friendships 表
-- ============================================================

CREATE TABLE IF NOT EXISTS friendships (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  friend_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status     TEXT        NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','accepted','declined','blocked')),
  note       TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, friend_id)
);

-- 兼容旧表：补 note 字段（若表已存在但缺列）
ALTER TABLE friendships ADD COLUMN IF NOT EXISTS note TEXT;

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "Users see own friendships"              ON friendships FOR SELECT USING (auth.uid() = user_id OR auth.uid() = friend_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Users can send friend requests"         ON friendships FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Target user can update friendship"      ON friendships FOR UPDATE USING (auth.uid() = friend_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Either party can delete friendship"     ON friendships FOR DELETE USING (auth.uid() = user_id OR auth.uid() = friend_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================
-- 3. music_generations 列扩展
-- 原有字段由 Supabase 初始表决定，此处只加业务字段
-- ============================================================

ALTER TABLE music_generations
  ADD COLUMN IF NOT EXISTS source              TEXT         DEFAULT 'mine',
  ADD COLUMN IF NOT EXISTS continue_at_sec     DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS parent_audio_id     TEXT,
  ADD COLUMN IF NOT EXISTS duration            DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS cocreate_session_id UUID;  -- FK 在 cocreate_sessions 创建后再加

COMMENT ON COLUMN music_generations.source IS 'mine | memory | cocreate';


-- ============================================================
-- 4. user_favorites 表（收藏歌单）
-- ============================================================

CREATE TABLE IF NOT EXISTS user_favorites (
  user_id    UUID        NOT NULL REFERENCES auth.users(id)  ON DELETE CASCADE,
  music_id   TEXT        NOT NULL,
  owner_id   UUID        NOT NULL REFERENCES auth.users(id)  ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, music_id)
);
CREATE INDEX IF NOT EXISTS idx_user_favorites_user_id ON user_favorites (user_id);

ALTER TABLE user_favorites ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "Users can manage own favorites"
    ON user_favorites FOR ALL
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================
-- 5. music_shared 表（别人分享给我的歌曲）
-- ============================================================

CREATE TABLE IF NOT EXISTS music_shared (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  music_id     TEXT        NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_music_shared_to_user ON music_shared (to_user_id);

ALTER TABLE music_shared ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "Users can see shared to them"             ON music_shared FOR SELECT  USING (auth.uid() = to_user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Users can share to others"                ON music_shared FOR INSERT  WITH CHECK (auth.uid() = from_user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Users can remove shared to them"          ON music_shared FOR DELETE  USING (auth.uid() = to_user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================
-- 6. cocreate_sessions 表
-- ============================================================

CREATE TABLE IF NOT EXISTS cocreate_sessions (
  id              UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id      UUID             NOT NULL REFERENCES auth.users(id),
  invitee_id      UUID             REFERENCES auth.users(id),
  status          TEXT             NOT NULL DEFAULT 'half_ready'
                    CHECK (status IN ('half_ready','invited','extending','completed','expired')),
  source_task_id  TEXT             NOT NULL,
  suno_audio_id   TEXT,
  continue_at_sec DOUBLE PRECISION NOT NULL,
  model           TEXT             NOT NULL DEFAULT 'V5',
  profile_a       JSONB            DEFAULT '{}',
  extend_task_id  TEXT,
  profile_b       JSONB            DEFAULT '{}',
  created_at      TIMESTAMPTZ      DEFAULT now(),
  expires_at      TIMESTAMPTZ      DEFAULT (now() + INTERVAL '13 days')
);

-- cocreate_session_id FK（在表创建后才能加）
DO $$ BEGIN
  ALTER TABLE music_generations
    ADD CONSTRAINT music_generations_cocreate_session_id_fkey
    FOREIGN KEY (cocreate_session_id) REFERENCES cocreate_sessions(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE cocreate_sessions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "Creator and invitee can read sessions"
    ON cocreate_sessions FOR SELECT
    USING (auth.uid() = creator_id OR auth.uid() = invitee_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Creator can insert sessions"
    ON cocreate_sessions FOR INSERT
    WITH CHECK (auth.uid() = creator_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY "Participants can update sessions"
    ON cocreate_sessions FOR UPDATE
    USING (auth.uid() = creator_id OR auth.uid() = invitee_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================
-- 7. music_generations RLS（依赖 music_shared，放在此处）
-- ============================================================

ALTER TABLE music_generations ENABLE ROW LEVEL SECURITY;

-- SELECT：自己的 + 别人分享给我的
DO $$ BEGIN
  CREATE POLICY "Users can read own or shared to me"
    ON music_generations FOR SELECT
    USING (
      user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM music_shared ms
        WHERE ms.music_id       = music_generations.task_id
          AND ms.from_user_id   = music_generations.user_id
          AND ms.to_user_id     = auth.uid()
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- SELECT：共创发起人（A）可以读取对方（B）续写生成的歌曲
DO $$ BEGIN
  CREATE POLICY "Cocreate creator can read partner extend music"
    ON music_generations FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM cocreate_sessions cs
        WHERE cs.extend_task_id = music_generations.task_id
          AND cs.creator_id     = auth.uid()
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- INSERT
DO $$ BEGIN
  CREATE POLICY "Users can insert own music"
    ON music_generations FOR INSERT
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- UPDATE
DO $$ BEGIN
  CREATE POLICY "Users can update own music"
    ON music_generations FOR UPDATE
    USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- DELETE
DO $$ BEGIN
  CREATE POLICY "Users can delete own music"
    ON music_generations FOR DELETE
    USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================
-- 8. RPC 函数
-- ============================================================

-- 8-1. upsert_profile：登录后自动创建/更新 profile
CREATE OR REPLACE FUNCTION upsert_profile(
  p_user_id      UUID,
  p_display_name TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (p_user_id, COALESCE(p_display_name, 'User'))
  ON CONFLICT (id) DO UPDATE
    SET updated_at   = now(),
        display_name = COALESCE(NULLIF(p_display_name, ''), profiles.display_name);
END;
$$;

-- 8-2. find_user_by_friend_code：通过 8 位好友码查人
CREATE OR REPLACE FUNCTION find_user_by_friend_code(p_code TEXT)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  avatar_url   TEXT,
  friend_code  TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
    SELECT p.id, p.display_name, p.avatar_url, p.friend_code
    FROM   profiles p
    WHERE  p.friend_code = p_code
    LIMIT  1;
END;
$$;

-- 8-3. send_friend_request：幂等发送好友申请
CREATE OR REPLACE FUNCTION send_friend_request(
  p_from_user_id UUID,
  p_to_user_id   UUID,
  p_note         TEXT DEFAULT NULL
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  existing_status TEXT;
BEGIN
  IF auth.uid() != p_from_user_id THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_from_user_id = p_to_user_id THEN
    RETURN 'cannot_add_self';
  END IF;

  SELECT status INTO existing_status
  FROM   friendships
  WHERE  (user_id = p_from_user_id AND friend_id = p_to_user_id)
     OR  (user_id = p_to_user_id   AND friend_id = p_from_user_id);

  IF existing_status = 'accepted' THEN RETURN 'already_friends'; END IF;
  IF existing_status = 'pending'  THEN RETURN 'already_pending';  END IF;

  INSERT INTO friendships (user_id, friend_id, status, note)
  VALUES (p_from_user_id, p_to_user_id, 'pending', p_note);
  RETURN 'sent';
END;
$$;

-- 8-4. get_sent_requests：我发出的、仍为 pending 的申请（含对方 profile）
CREATE OR REPLACE FUNCTION get_sent_requests(p_user_id UUID)
RETURNS TABLE (
  id           UUID,
  user_id      UUID,
  friend_id    UUID,
  status       TEXT,
  note         TEXT,
  created_at   TIMESTAMPTZ,
  display_name TEXT,
  avatar_url   TEXT,
  friend_code  TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT f.id, f.user_id, f.friend_id, f.status, f.note, f.created_at,
         p.display_name, p.avatar_url, p.friend_code
  FROM   friendships f
  JOIN   profiles    p ON p.id = f.friend_id
  WHERE  f.user_id = p_user_id AND f.status = 'pending';
END;
$$;

-- 8-5. get_favorite_songs_for_user：收藏歌单
CREATE OR REPLACE FUNCTION get_favorite_songs_for_user(p_user_id UUID)
RETURNS SETOF music_generations
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT mg.*
  FROM   music_generations mg
  JOIN   user_favorites    uf ON uf.music_id = mg.task_id AND uf.owner_id = mg.user_id
  WHERE  uf.user_id = p_user_id
  ORDER  BY uf.created_at DESC;
$$;

-- 8-6. get_shared_songs_for_user：别人分享给我的歌曲
CREATE OR REPLACE FUNCTION get_shared_songs_for_user(p_to_user_id UUID)
RETURNS SETOF music_generations
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT mg.*
  FROM   music_generations mg
  JOIN   music_shared      ms ON ms.music_id = mg.task_id AND ms.from_user_id = mg.user_id
  WHERE  ms.to_user_id = p_to_user_id
  ORDER  BY ms.created_at DESC;
$$;


-- ============================================================
-- 9. Realtime Publication
-- 两张表需要客户端实时订阅：music_generations（生成完成通知）
--                          cocreate_sessions（共创邀请通知）
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'music_generations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE music_generations;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'cocreate_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE cocreate_sessions;
  END IF;
END $$;


-- ============================================================
-- 10. 验证（可选，运行后取消注释查看）
-- ============================================================

-- SELECT tablename, policyname, cmd, qual
-- FROM   pg_policies
-- WHERE  tablename IN (
--          'profiles','friendships','music_generations',
--          'user_favorites','music_shared','cocreate_sessions'
--        )
-- ORDER  BY tablename, cmd;
