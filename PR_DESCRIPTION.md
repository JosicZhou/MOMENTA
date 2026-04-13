# PR 描述

## 1. 总览与 Share Guide

这次改动不是单点修复，而是一次跨 `Light / Memories / Profile / Share / Player / Widget / Dynamic Island / Lock Screen` 的整合版本。

当前版本的产品结构被明确整理为：

- `Profile` 负责关系层：好友、个人歌曲时间线、收藏入口、个人 identity card。
- `Share` 负责协作层：接收歌曲、发送歌曲、发起共创、继续共创。
- `Light / Memories` 负责创作层：继续承担歌曲生成，不直接变成社交页。
- 系统表面负责延展层：Widget、Live Activity、Dynamic Island、Lock Screen、App Intents。

### Share Guide

`Share` 现在不是占位页，而是明确的协作中心。

根结构分为两个一级入口：

- `Invitations`
- `Start to Co-create`

#### Invitations

`Invitations` 分成两种不同的收件状态：

- `Co-create Requests`
  - 别人邀请你继续创作的歌曲。
  - 点击后进入共创详情页，可继续创作或拒绝。
- `Shared with You`
  - 别人纯分享给你的歌曲。
  - 点击后进入歌曲详情，可播放、保存，或再次发起共创。

这两类内容不会混成一个 feed，因为“纯分享”和“邀请协作”在交互语义上不同。

#### Start to Co-create

`Start to Co-create` 是发送和发起协作的主入口，包含：

- `Create New Song`
- `Your Songs`
- `Sent / Active`

用户可以：

- 直接从自己已有歌曲中选择一首发送给朋友
- 在 Share 内新建一首歌，再进入发送流程

#### 发送规则

当前版本的发送规则如下：

- 一次只支持发送给 `1` 个好友
- 支持两种发送模式：
  - `Share Only`
  - `Invite to Co-create`

对应行为：

- `Share Only`
  - 写入 `music_shared`
  - 接收方在 `Shared with You` 中看到
- `Invite to Co-create`
  - 创建 `cocreate_sessions`
  - 接收方在 `Co-create Requests` 中看到
  - 接收方可以继续补图、补 prompt、补 pipeline 信息并提交 extend

#### 好友系统规则

好友系统通过 `Profile` 右上角 `+` 打开 `Friends Sheet` 统一管理，包含：

- `My Code`
- `Add Friend`
- `Incoming Requests`
- `Sent Requests`
- `Friends`

好友关系不散落在多个页面中，统一由 `Profile` 管理，`Share` 仅消费好友关系用于发送和协作。

## 2. 已知 Bug 与仍需修改的内容

当前版本功能已经成型，但还存在一批需要继续精修的问题：

### 系统表面

- `Dynamic Island`、`Lock Screen`、`Live Activity`、`桌面 Widget` 虽然都已经有实现，但还没有达到完全稳定和完全原生一致的状态。
- widget 与灵动岛的内容切换、封面回退、节奏动画、信息层级还需要继续打磨。
- 系统表面现在更接近“功能已接上”，还不是“细节完全收口”。

### 播放器与歌词

- 全屏播放器已经统一到 Apple Music 风格，但仍有一些 spacing、节奏和手势细节需要继续校准。
- 歌词同步已经改善，但 fallback 纯文本歌词天生只能做到近似同步，无法达到真时间轴歌词的精度。
- 播放器内部某些底部动作现在仍偏壳层化，真实行为和交互一致性还要补。

### Share / Friends / Co-create

- `Shared with You` 的发件人元数据还不够完整，后端返回形状仍需增强。
- `Share` 内部仍保留本地 fallback 与 `ShareLocalStore`，会掩盖部分真实后端失败。
- 远端 Supabase 是否完全应用了本地 migration，仍需要逐项核验。

### 数据与临时策略

- `Profile` 时间线当前存在临时展示规则，例如时间过滤和封面过滤，这类策略后续需要回到更产品化的配置方式。
- `ShareView.swift` 当前体量已经很大，功能虽然可用，但维护成本偏高，后续应进一步拆分。

## 3. 我所做的改动

这一部分是当前 PR 的核心。

### Light

- 重做 `Light` 首页的视觉层和输入层：
  - `WelcomeCard`
  - `PresetCard`
  - `WhiteGlassInputBar`
- 优化输入、推荐语和整体层级，使 `Light` 更像独立的创作入口。
- 保持 `Light` 只负责“生成”，不把社交逻辑直接塞进主页面。
- 生成链路继续由 `Photo2MusicManager` 驱动，并加入了更明确的 timing 输出和完成等待路径。

### Memories

- 重做 `Memories` 主界面为 `Collection + Timeline` 结构。
- 增加 section 折叠、收藏动作、widget 入口和歌曲播放联动。
- 调整 `MemoryComposerSheet` 行为：
  - 生成时允许退回
  - 生成任务继续在后台完成
  - 全局 loading bar 接管生成反馈
- 整理 `MemoryViewModel` 与 `Memory2MusicManager`，让生成、回流、展示状态更一致。

### Profile

- 重做 profile identity card 的内部构图。
- 重做 profile 时间线，支持：
  - list 模式
  - square/grid 模式
- 增加 section collapse、filter、timeline header、自定义布局切换。
- 增加 timeline 内的：
  - 收藏
  - 删除
  - 分享
  - widget action
  - 播放器联动
- 将 `Friends Sheet` 接入 `Profile` 右上角 `+` 入口。

### Share / Friends / Co-create

- 将 `Share` 从占位页升级为完整协作中心。
- 新增并接通：
  - `Invitations`
  - `Start to Co-create`
  - `ShareSendSheet`
  - `ShareComposerSheet`
  - `FriendsSheet`
  - activity / detail / placeholder surfaces
- 引入两种发送模式：
  - `Share Only`
  - `Invite to Co-create`
- 补齐朋友关系与协作模型：
  - `friend_code`
  - `friendships`
  - `cocreate_sessions`
  - `music_shared`
- 让 Share 能同时承担：
  - 接收
  - 发送
  - 继续创作
  - 查看活动状态

### 后端与数据结构

- 新增 migration：
  - [20260411010000_friends_share_cocreate_v1.sql](/Users/developer/Desktop/M/Momenta/supabase/migrations/20260411010000_friends_share_cocreate_v1.sql)
- 扩展 `GeneratedMusic` 与共创相关模型。
- 在 `MusicDatabaseService` 中加入 `CocreateService` 能力。
- 在 `ProfileService` 中加入：
  - 好友码查询
  - 请求发送
  - 好友列表
  - 已发送请求
  - 收藏/取消收藏
  - 分享歌曲

### 系统集成

- 增加 `SongEntity` 和 App Intents 接口。
- 增加 `SystemSongSnapshot` / `SystemSongSnapshotStore` / `SystemSongLibrarySync`。
- 增加 widget extension：
  - `SongWidget`
  - `PlaybackLiveActivityWidget`
- 增加 Live Activity / Dynamic Island / Lock Screen 的 now-playing surface。
- 增加 App Group 与 entitlement 配置，支持 widget 与主 app 共享歌曲快照。

### 播放器

- 重做 mini player / full-screen player / lyrics view 的视觉和交互层。
- 引入更统一的 artwork background treatment。
- 改善歌词高亮、滚动、同步定位和控件显隐逻辑。
- 让播放器支持：
  - 收藏
  - widget pin
  - 锁屏/系统播放信息更新

## 4. 视觉层面的优化：方式与方法

这一轮视觉层并不是单纯“换样式”，而是统一成更接近 Apple 的系统语义。

### 统一原则

- 优先使用标准 SF 字体层级，不做无必要的夸张 display。
- 把玻璃材质控制在“表层增强”，而不是全屏到处都是玻璃。
- 强化内容层级，而不是依赖大量装饰性卡片。
- 控件退后，内容前置，尤其是在播放器和 Share 页面。

### 具体优化方法

#### Light

- 用更稳定的浅底系统色作为页面基底。
- 输入层改为更克制的 glass composer，而不是大块重玻璃。
- welcome / prompt / composer / preset 之间的节奏重新拉开。

#### Memories / Profile

- `Memories` 和 `Profile` 的歌曲展示重新统一为更像 Apple Music / Photos 的节奏。
- 列表视图和 grid 视图都强调留白、时间分组和层级，不再堆砌独立卡片。
- 收藏、菜单、时间、管线标识等信息被压回更合理的位置。

#### Share

- `Share` 采用 destination card + grouped content 的结构。
- 朋友系统与协作系统使用一致的 page rhythm 和 placeholder language。
- 空状态不做 generic gradient，而是用素材和系统材质去做更像 onboarding 的表面。

#### Player

- 全屏播放器从“浮动 glass 面板叠加”改为“内容沉入 artwork 背景”的方向。
- 歌词页头、底部控制、进度层、toolbar 层级被统一，不再像多个独立卡片拼接。
- 播放器的尺寸、留白、按钮尺度都收紧了一档，往 Apple Music 的密度靠拢。

#### 系统表面

- Widget / Live Activity / Dynamic Island 不再只显示机械状态，而是使用 artwork、标题、波形、进度来建立系统级一致性。
- 方向是“更像系统播放器”，而不是把应用页面缩略塞进系统 surface。

## 5. 功能上的详细说明

### Light 生成流程

- 用户在 `Light` 中输入 prompt、选择图片/声音选项。
- 进入歌词生成阶段。
- 再进入 Suno 生成阶段。
- 完成后写入歌曲记录并同步到系统歌曲快照。
- 生成中的反馈通过全局 loading bar 横跨四个 Tab 显示。

### Memories 生成流程

- `Memories` 根据时间、环境、图片、健康/上下文信息生成更重的 prompt。
- 通过独立的 `Memory2MusicManager` 走歌词生成与歌曲生成链路。
- 用户可在 sheet 退回后继续等待结果，全局 loading 保持可见。

### Profile 时间线规则

- `Profile` 时间线会对歌曲进行合并、过滤、排序。
- 目前包含：
  - mine
  - cocreate
  - shared
- 支持按 section 分组显示，例如：
  - Today
  - This week
  - This month
  - This year
- 支持 list / grid 双模式切换。

### Favorites / Collection

- `Memories` 与 `Profile` 都已支持收藏切换。
- 播放器内的星标也接入了收藏逻辑。
- 收藏会影响：
  - Collection
  - Favorites
  - 时间线视图中的标识

### Share / Co-create 详细行为

- `Friends Sheet` 用于管理好友关系。
- `Share` 处理歌曲流转。
- 发起时用户先选歌曲，再选好友，再选发送模式。
- 继续共创时，用户在 `Co-create Request` 中进入详情，再进入 composer 完成下一段生成。
- `Sent / Active` 会保留发送后的状态线索。

### Widget / Dynamic Island / Lock Screen

- 本地歌曲现在可以通过菜单动作设为桌面 widget 的目标歌曲。
- widget 通过 `SongEntity` 和 `SystemSongSnapshot` 驱动。
- 正在播放的歌曲会同步到：
  - Lock Screen
  - Live Activity
  - Dynamic Island
- 当前这部分已可展示，但仍处于需要继续精修的阶段。

### 深链与系统入口

- Deep link 已扩展到：
  - Share root
  - invitation detail
  - shared song detail
  - activity detail
  - widget / App Intent 打开歌曲
- 这为后续 widget、shortcut、通知入口保留了结构基础。

## 结论

这次版本的本质不是单一 feature，而是把 `创作层`、`关系层`、`协作层`、`播放器层` 与 `系统表面层` 初步接成了一个完整产品结构。

当前版本已经具备完整方向：

- `Light / Memories` 负责创作
- `Profile` 负责关系与个人歌曲层
- `Share` 负责发送、接收、共创
- `Player / Widget / Dynamic Island / Lock Screen` 负责系统级延展

但这还不是结束版本，后续仍然需要继续做：

- 系统表面的精修
- 播放器与歌词同步的细节收口
- Share 后端闭环与 sender metadata 完整化
- 组件拆分与维护性优化
