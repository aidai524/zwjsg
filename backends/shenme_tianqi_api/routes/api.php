<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AvatarController;
use App\Http\Controllers\Api\CareGroupController;
use App\Http\Controllers\Api\CityController;
use App\Http\Controllers\Api\MeController;
use App\Http\Controllers\Api\MuteController;
use App\Http\Controllers\Api\ReminderController;
use App\Http\Controllers\Api\WeatherController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::post('auth/sms/send', [AuthController::class, 'sendSms'])->middleware('throttle:sms');
    Route::post('auth/sms/login', [AuthController::class, 'smsLogin'])->middleware('throttle:10,1');
    Route::post('auth/wechat/login', [AuthController::class, 'wechatLogin']);

    // 不登录也能看天气（先看再注册）
    Route::middleware('throttle:weather')->group(function () {
        Route::get('cities/search', [CityController::class, 'search']);
        Route::get('weather/{locationId}', [WeatherController::class, 'show']);
    });

    Route::middleware(['auth:sanctum', 'throttle:api'])->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);

        Route::get('me', [MeController::class, 'show']);
        Route::patch('me/settings', [MeController::class, 'updateSettings']);
        Route::delete('me', [MeController::class, 'destroy']);
        Route::post('me/avatar', [AvatarController::class, 'store']);

        Route::get('cities', [CityController::class, 'index']);
        Route::post('cities', [CityController::class, 'store']);
        Route::patch('cities/{city}', [CityController::class, 'update']);
        Route::delete('cities/{city}', [CityController::class, 'destroy']);

        Route::get('care-groups', [CareGroupController::class, 'index']);
        Route::post('care-groups', [CareGroupController::class, 'store']);
        Route::post('care-groups/join', [CareGroupController::class, 'join'])->middleware('throttle:20,1');
        Route::get('care-groups/{careGroup}', [CareGroupController::class, 'show']);
        Route::patch('care-groups/{careGroup}', [CareGroupController::class, 'update']);
        Route::post('care-groups/{careGroup}/leave', [CareGroupController::class, 'leave']);

        Route::post('reminders', [ReminderController::class, 'store']);
        Route::get('reminders/inbox', [ReminderController::class, 'inbox']);
        Route::post('reminders/{reminder}/ack', [ReminderController::class, 'ack']);

        Route::get('mutes', [MuteController::class, 'index']);
        Route::post('mutes', [MuteController::class, 'store']);
        Route::delete('mutes/{mute}', [MuteController::class, 'destroy']);
    });
});
