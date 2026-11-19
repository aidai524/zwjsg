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

    // 系列 App 之间一次性导出形象：“什么鬼天气”的后端凭导出码来取图时带的密钥，两边配成一样的值。
    // 没配时导出码照样能生成，但谁都取不到图
    'series' => [
        'export_key' => env('SERIES_EXPORT_KEY'),
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

    // 登录验证码短信。log：开发用，验证码只写进 storage/logs/laravel.log（生产环境会拒绝发码）；
    // aliyun：阿里云短信，要自己开通、申请签名和验证码模板，见 README 的“接真实短信（阿里云）”
    'sms' => [
        'driver' => env('SMS_DRIVER', 'log'),
        'aliyun' => [
            'access_key_id' => env('ALIYUN_SMS_ACCESS_KEY_ID'),
            'access_key_secret' => env('ALIYUN_SMS_ACCESS_KEY_SECRET'),
            'sign_name' => env('ALIYUN_SMS_SIGN_NAME'),
            'template_code' => env('ALIYUN_SMS_TEMPLATE_CODE'),
            // 模板里验证码变量的名字，比如模板是“您的验证码是${code}”就填 code
            'template_param' => env('ALIYUN_SMS_TEMPLATE_PARAM', 'code'),
            'endpoint' => env('ALIYUN_SMS_ENDPOINT', 'dysmsapi.aliyuncs.com'),
        ],
    ],

];
