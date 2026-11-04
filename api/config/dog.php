<?php

return [
    // 狗度阈值（%），达到即进入对应阶段 1–5；与 App 端保持一致
    'stage_thresholds' => [30, 60, 90, 120, 150],

    // 狗度低于这个值算“做回人”
    'human_below' => 30,

    // 连续多少天做人解锁传说犬种
    'legend_streak_days' => 7,

    'goal_minutes' => ['min' => 60, 'max' => 480],

    'avatar_regen_default' => 3,

    // 犬种配置。App 端判定当天的犬种后上报 key；传说犬种只由服务端判定。
    'breeds' => [
        'corgi' => ['name' => '柯基', 'rarity' => 'common', 'quip' => '腿短，停不下来', 'rule' => '短视频类使用最多'],
        'husky' => ['name' => '哈士奇', 'rarity' => 'common', 'quip' => '半夜不睡的拆家狗', 'rule' => '23 点后使用占比最高'],
        'chihuahua' => ['name' => '吉娃娃', 'rarity' => 'common', 'quip' => '焦虑到发抖', 'rule' => '拿起手机次数极高'],
        'shiba' => ['name' => '社畜柴犬', 'rarity' => 'common', 'quip' => '下班还在回消息', 'rule' => '办公、通讯类使用最多'],
        'collie' => ['name' => '边牧', 'rarity' => 'common', 'quip' => '太聪明了，全用在游戏上', 'rule' => '游戏类使用最多'],
        'rare_a' => ['name' => '[稀有 A]', 'rarity' => 'rare', 'quip' => '[待定]', 'rule' => '两种以上模式罕见叠加'],
        'rare_b' => ['name' => '[稀有 B]', 'rarity' => 'rare', 'quip' => '[待定]', 'rule' => '两种以上模式罕见叠加'],
        'wolf' => ['name' => '狼', 'rarity' => 'legend', 'quip' => '自由的野狼，不认主人', 'rule' => '连续 7 天做人', 'server_only' => true],
    ],
];
