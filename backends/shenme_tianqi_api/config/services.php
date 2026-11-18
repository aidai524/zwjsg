<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    // 和风天气：每个账号有自己的 API Host，鉴权用 X-QW-Api-Key 请求头
    'qweather' => [
        'host' => env('QWEATHER_HOST', 'devapi.qweather.com'),
        'key' => env('QWEATHER_KEY'),
        'timeout' => 5,
    ],

    // 从“再玩我是狗”一次性导入形象：狗后端的接口地址（写到 /api/v1）和系列密钥（两个后端配成一样的值）
    'gou' => [
        'api_base' => env('GOU_API_BASE'),
        'timeout' => 10,
    ],
    'series' => [
        'export_key' => env('SERIES_EXPORT_KEY'),
    ],

    'push' => [
        // log：只写日志；上线前接统一推送联盟 / 厂商通道 / APNs
        'driver' => env('PUSH_DRIVER', 'log'),
    ],

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
