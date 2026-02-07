-- Profile 个人主页与歌单能力
-- 1. music_generations 增加 source，用于区分 Mine / Cocreate
-- 2. user_favorites 用户收藏（Favorites 歌单）
-- 3. music_shared 别人分享给我的歌曲（Shared 歌单）

-- 1) music_generations 增加 source（缺省 'mine'）
ALTER TABLE music_generations
ADD COLUMN IF NOT EXISTS source text DEFAULT 'mine';

COMMENT ON COLUMN music_generations.source IS 'mine | cocreate，用于归类到 Mine / Cocreate 歌单';

-- 2) 用户收藏表（music_id = task_id，owner_id = 该歌曲在 music_generations 的 user_id，便于拉取详情）
CREATE TABLE IF NOT EXISTS user_favorites (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  music_id text NOT NULL,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, music_id)
);

CREATE INDEX IF NOT EXISTS idx_user_favorites_user_id ON user_favorites(user_id);

-- 便于按用户拉取收藏歌曲的 RPC（返回 music_generations 行）
CREATE OR REPLACE FUNCTION get_favorite_songs_for_user(p_user_id uuid)
RETURNS SETOF music_generations
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT mg.*
  FROM music_generations mg
  INNER JOIN user_favorites uf ON uf.music_id = mg.task_id AND uf.owner_id = mg.user_id
  WHERE uf.user_id = p_user_id
  ORDER BY uf.created_at DESC;
$$;

ALTER TABLE user_favorites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own favorites"
  ON user_favorites FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 3) 分享给当前用户的歌曲（Shared 歌单）
CREATE TABLE IF NOT EXISTS music_shared (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  music_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_music_shared_to_user ON music_shared(to_user_id);

ALTER TABLE music_shared ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can see shared to them"
  ON music_shared FOR SELECT
  USING (auth.uid() = to_user_id);

CREATE POLICY "Users can delete shared to them (remove from list)"
  ON music_shared FOR DELETE
  USING (auth.uid() = to_user_id);

CREATE POLICY "Users can share to others (insert)"
  ON music_shared FOR INSERT
  WITH CHECK (auth.uid() = from_user_id);

-- 4) RLS：允许用户读取「别人分享给自己」的歌曲对应的 music_generations 行
-- 若你已有仅允许读自己记录的 SELECT 策略，可改为合并为一条：own OR shared to me
ALTER TABLE music_generations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own or shared to me"
  ON music_generations FOR SELECT
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM music_shared ms
      WHERE ms.music_id = music_generations.task_id
        AND ms.from_user_id = music_generations.user_id
        AND ms.to_user_id = auth.uid()
    )
  );

-- 5) RPC：获取「分享给我的」歌曲列表（返回 music_generations 行）
CREATE OR REPLACE FUNCTION get_shared_songs_for_user(p_to_user_id uuid)
RETURNS SETOF music_generations
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT mg.*
  FROM music_generations mg
  INNER JOIN music_shared ms ON ms.music_id = mg.task_id AND ms.from_user_id = mg.user_id
  WHERE ms.to_user_id = p_to_user_id
  ORDER BY ms.created_at DESC;
$$;
