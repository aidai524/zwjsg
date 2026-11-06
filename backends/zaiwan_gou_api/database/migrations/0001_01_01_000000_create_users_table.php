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
            // IANA 时区，用来决定用户的“每天 0 点”
            $table->string('timezone', 64)->default('Asia/Shanghai');
            $table->unsignedSmallInteger('daily_goal_minutes')->default(180);
            $table->time('remind_at')->default('22:00:00');
            // 只存卡通形象，不存原始照片
            $table->string('avatar_path')->nullable();
            $table->unsignedTinyInteger('avatar_regen_left')->default(3);
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
