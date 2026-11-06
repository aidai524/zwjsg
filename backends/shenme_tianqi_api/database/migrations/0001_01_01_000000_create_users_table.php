<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('phone', 20)->nullable()->unique();
            $table->string('wechat_openid', 64)->nullable()->unique();
            $table->string('nickname', 32)->nullable();
            $table->string('timezone', 64)->default('Asia/Shanghai');
            // 毒舌档位：0 正经、1 损友（默认）、2 毒舌
            $table->unsignedTinyInteger('snark_level')->default(1);
            $table->boolean('morning_push_on')->default(true);
            $table->time('morning_push_weekday')->default('07:30:00');
            $table->time('morning_push_weekend')->default('09:00:00');
            $table->boolean('alert_push_on')->default(true);
            // 推送设备标识（统一推送或苹果推送），由 App 上报
            $table->string('push_token')->nullable();
            // 只存卡通形象；可从“再玩我是狗”一次性导入
            $table->string('avatar_path')->nullable();
            $table->timestamps();
        });

        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            $table->foreignId('user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('users');
        Schema::dropIfExists('sessions');
    }
};
