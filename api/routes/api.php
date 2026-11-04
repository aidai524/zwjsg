<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AvatarController;
use App\Http\Controllers\Api\BreedController;
use App\Http\Controllers\Api\DailyRecordController;
use App\Http\Controllers\Api\MeController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::post('auth/sms/send', [AuthController::class, 'sendSms'])->middleware('throttle:sms');
    Route::post('auth/sms/login', [AuthController::class, 'smsLogin'])->middleware('throttle:10,1');
    Route::post('auth/wechat/login', [AuthController::class, 'wechatLogin']);

    Route::middleware(['auth:sanctum', 'throttle:api'])->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);

        Route::get('me', [MeController::class, 'show']);
        Route::patch('me/settings', [MeController::class, 'updateSettings']);
        Route::delete('me', [MeController::class, 'destroy']);
        Route::post('me/avatar', [AvatarController::class, 'store']);

        Route::get('daily-records', [DailyRecordController::class, 'index']);
        Route::put('daily-records/{date}', [DailyRecordController::class, 'upsert']);

        Route::get('breeds', [BreedController::class, 'index']);
    });
});
