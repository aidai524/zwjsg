<?php

/*
 * “什么鬼天气”的玩法规则。App 端 apps/shenme_tianqi 只做展示（判断依据的说明文字在 lib/core/scene.dart），
 * 结论一律以服务端为准。改了这里，同步更新需求文档。
 *
 * 合规：天气数据和预警只来自和风天气转发的气象部门官方数据；预警原文照登，
 * 注明发布单位和时间；吐槽文案是人工写好的，不用 AI 生成，也不改写预报结论。
 */

return [

    'cache_ttl' => [ // 秒
        'now' => 600,
        'hourly' => 3600,
        'daily' => 3600,
        'warning' => 300,
        'air' => 1800,
        'geo' => 86400 * 7,
    ],

    // 衣服档位：按体感温度，从高到低匹配第一个满足 >= min 的
    'outfit_bands' => [
        ['key' => 'hot', 'min' => 35, 'label' => '短袖+防晒'],
        ['key' => 'warm', 'min' => 28, 'label' => '短袖'],
        ['key' => 'mild', 'min' => 18, 'label' => '长袖/薄外套'],
        ['key' => 'cool', 'min' => 10, 'label' => '外套/卫衣'],
        ['key' => 'cold', 'min' => 0, 'label' => '厚外套/毛衣'],
        ['key' => 'freezing', 'min' => -999, 'label' => '羽绒服+帽子围巾'],
    ],

    // 四张决策卡
    'decisions' => [
        'umbrella' => [
            'hours' => [7, 22],      // 只看白天到晚上这段
            'take_pop' => 50,        // 任一小时降水概率 >= 50% → 带
            'maybe_pop' => 30,       // 30–50% → 随便
            'sun_uv' => 7,           // 紫外线 >= 7 → 带伞防晒
        ],
        'long_johns' => [
            'feels_below' => 10,     // 今天最低体感 < 10° → 穿
        ],
        'car_wash' => [
            'dry_days' => 3,         // 未来 3 天无雨无沙尘 → 洗
        ],
        'laundry' => [
            'hours' => [8, 18],
            'max_humidity' => 70,
            'max_wind_scale' => 5,   // 风力 >= 5 级不晾，免得被吹跑
        ],
    ],

    // 严重天气：黄/橙/红预警进入严肃模式（不吐槽，原文照登）；蓝色只显示横幅
    'serious_colors' => ['Yellow', 'Orange', 'Red', 'Black'],
    'banner_colors' => ['White', 'Blue', 'Green'],

    // 和风天气图标代码 → 形象状态。顺序重要：先匹配先生效
    'icon_cond' => [
        ['codes' => [302, 303, 304], 'cond' => 'thunder'],
        ['codes' => [301, 307, 308, 310, 311, 312, 316, 317, 318], 'cond' => 'heavy_rain'],
        ['range' => [300, 399], 'cond' => 'light_rain'],
        ['range' => [400, 499], 'cond' => 'snow'],
        ['codes' => [503, 504, 507, 508], 'cond' => 'dust'],
        ['range' => [500, 515], 'cond' => 'smog'],
        ['codes' => [100, 150], 'cond' => 'sunny'],
        ['range' => [101, 199], 'cond' => 'cloudy'],
    ],
    'wind_scale_cond' => 6,      // 风力 >= 6 级，形象被吹歪
    'rain_icons' => [300, 399],  // 用于洗车、晾衣判断“有没有雨”
    'dust_icons' => [503, 504, 507, 508],

    // 回南天：华南几个省，2–4 月，湿度 >= 90%
    'humid' => [
        'adm' => ['广东省', '广西壮族自治区', '福建省', '海南省', '广东', '广西', '福建', '海南'],
        'months' => [2, 3, 4],
        'min_humidity' => 90,
    ],

    'quip_no_repeat_days' => 7,

    // 关心群
    'care' => [
        'min_members' => 2,
        'max_members' => 8,
        'max_groups_per_user' => 5,
        'daily_cap_per_pair' => 2,      // 同一人每天最多提醒同一人 2 次
        'merge_minutes' => 30,          // 30 分钟内同话题的提醒合并成一条
        'quiet_start' => 22,            // 22:00–07:00（被提醒者本地时间）延迟到 07:00
        'quiet_end' => 7,
        'retention_days' => 30,
        // 每个话题 1–3 句温和的固定话，发送者只能选，不能自己打字
        'phrases' => [
            'rain' => [
                'rain_umbrella' => '要下雨了，记得带伞 ☂',
                'rain_early' => '下雨路滑，早点回家',
            ],
            'heavy_rain' => [
                'heavy_stay' => '雨挺大的，能不出门就别出门',
                'heavy_umbrella' => '大雨，带把结实的伞',
            ],
            'thunder' => [
                'thunder_indoor' => '有雷雨，待在室内安全点',
            ],
            'snow' => [
                'snow_warm' => '下雪了，穿暖和点',
                'snow_slip' => '路上可能结冰，慢点走',
            ],
            'cold' => [
                'cold_coat' => '降温了，多穿一件',
                'cold_warm' => '天冷，喝点热的',
            ],
            'hot' => [
                'hot_water' => '很热，记得多喝水',
                'hot_sun' => '太阳毒，注意防晒',
            ],
            'wind' => [
                'wind_coat' => '风大，外套扣好',
            ],
            'smog' => [
                'smog_mask' => '空气不太好，出门戴口罩',
            ],
            'dust' => [
                'dust_mask' => '有沙尘，出门戴口罩',
            ],
            'alert' => [
                'alert_safe' => '那边有天气预警，注意安全',
                'alert_home' => '预警了，早点回家',
            ],
            'nice' => [
                'nice_walk' => '那边天气不错，出去走走',
            ],
        ],
    ],
];
