<?php

return [
    // 狗度阈值（%），达到即进入对应阶段 1–5；与 App 端保持一致
    'stage_thresholds' => [30, 60, 90, 120, 150],

    // 狗度低于这个值算“做回人”
    'human_below' => 30,

    // 连续多少天做人解锁传说犬种
    'legend_streak_days' => 7,

    // 每日目标只有三档（分钟）：正常使用 3 小时、重度使用 5 小时、无可自拔 8 小时。
    // 和 App 端 lib/core/dog_meter.dart 的 GoalTier 一致，改动时两边一起改
    'goal_tiers' => [180, 300, 480],

    'avatar_regen_default' => 3,

    // 预设形象（2026-11-27：不做捏脸，预设几张捏好的脸给用户挑），App 只能传这几个名字。
    // 和 packages/avatar_engine 的 AvatarPreset 一致（Flutter 测试会读这里对一遍），加减、改名时两边一起改
    'avatar_presets' => ['ahoge', 'bun', 'long', 'curly', 'buzz', 'bob', 'parted'],

    // 群组（原“狗群”，2026-11-20 改名）。群里只共享每天的狗度、阶段和犬种
    'groups' => [
        'max_members' => 10,
        'max_groups_per_user' => 5,
        // 汪一下：同一个人每天最多汪同一个人几次
        'nudges_per_pair_per_day' => 2,
        // 一起做人：全群连续多少天都是人，拿“狼群”称号
        'team_streak_goal' => 7,
        // 一起做人最多往回数多少天
        'team_streak_lookback' => 60,
        // 最近多少天上报过记录才算“共享狗度的成员”（用 iPhone 的不上报，不算进一起做人）
        'sharer_window_days' => 30,
    ],

    // 犬种配置。App 端判定当天的犬种后上报 key；传说犬种只由服务端判定。
    // 和 App 端 lib/core/breeds.dart 的 kBreeds 一致（Flutter 测试会读这里对一遍），改动时两边一起改
    'breeds' => [
        'corgi' => ['name' => '柯基', 'rarity' => 'common', 'quip' => '腿短，停不下来', 'rule' => '短视频类使用最多'],
        'husky' => ['name' => '哈士奇', 'rarity' => 'common', 'quip' => '半夜不睡的拆家狗', 'rule' => '23 点后使用占比最高'],
        'chihuahua' => ['name' => '吉娃娃', 'rarity' => 'common', 'quip' => '焦虑到发抖', 'rule' => '拿起手机次数极高'],
        'shiba' => ['name' => '社畜柴犬', 'rarity' => 'common', 'quip' => '下班还在回消息', 'rule' => '办公、通讯类使用最多'],
        'collie' => ['name' => '边牧', 'rarity' => 'common', 'quip' => '太聪明了，全用在游戏上', 'rule' => '游戏类使用最多'],
        // 两种稀有犬种（2026-11-26 定）：串串靠罕见的刷法组合，金毛寻回犬靠自律（看前 4 天，App 端判定）
        'mutt' => ['name' => '串串', 'rarity' => 'rare', 'quip' => '血统不纯，爱好很杂', 'rule' => '同一天里短视频、游戏、聊天办公三样各占两成以上'],
        'retriever' => ['name' => '金毛寻回犬', 'rarity' => 'rare', 'quip' => '每天叼回一点自己', 'rule' => '连续 4 天一天比一天刷得少（算到昨天），今天还没做回人'],
        'wolf' => ['name' => '狼', 'rarity' => 'legend', 'quip' => '自由的野狼，不认主人', 'rule' => '连续 7 天做人', 'server_only' => true],
        // 节日限定（2026-11-27 定）：节日那几天变狗就是它，每年这几天才有；哪几天见下面的 festival_breeds
        'flag' => ['name' => '立flag犬', 'rarity' => 'limited', 'quip' => '新年第一天，flag 就倒了', 'rule' => '元旦（1 月 1 日）变狗'],
        'wangcai' => ['name' => '旺财', 'rarity' => 'limited', 'quip' => '过年守着手机看家，名副其实的旺财', 'rule' => '春节（除夕到正月初六）变狗'],
        'single' => ['name' => '单身狗', 'rarity' => 'limited', 'quip' => '七夕还在刷手机，懂的都懂', 'rule' => '七夕（农历七月初七）变狗'],
        'tiangou' => ['name' => '天狗', 'rarity' => 'limited', 'quip' => '中秋不看月亮看手机，月亮都被你吃了', 'rule' => '中秋（农历八月十五）变狗'],
    ],

    // 节日限定犬种在哪几天（含首尾，用户本地日期）。App 只在这几天、变狗时才会报；别的日子报上来的不收（那天不记犬种）。
    // 农历节日按年写死（2027–2030），过了 2030 年要往后补；和 App 端 lib/core/festivals.dart 一致（Flutter 测试会读这里对一遍）
    'festival_breeds' => [
        'flag' => ['every_year' => '01-01'],
        'wangcai' => ['windows' => [
            ['2027-02-05', '2027-02-11'], ['2028-01-25', '2028-01-31'], ['2029-02-12', '2029-02-18'], ['2030-02-02', '2030-02-08'],
        ]],
        'single' => ['windows' => [
            ['2027-08-08', '2027-08-08'], ['2028-08-26', '2028-08-26'], ['2029-08-16', '2029-08-16'], ['2030-08-05', '2030-08-05'],
        ]],
        'tiangou' => ['windows' => [
            ['2027-09-15', '2027-09-15'], ['2028-10-03', '2028-10-03'], ['2029-09-22', '2029-09-22'], ['2030-09-12', '2030-09-12'],
        ]],
    ],
];
