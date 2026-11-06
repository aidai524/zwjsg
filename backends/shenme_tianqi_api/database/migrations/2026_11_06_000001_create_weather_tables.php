<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 用户关注的城市，最多 5 个；只到城市/区县级别，不存定位轨迹
        Schema::create('user_cities', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('location_id', 32); // 和风天气的 LocationID
            $table->string('name', 64);
            $table->string('adm', 64)->nullable(); // 省级行政区，用于判断回南天等地区梗
            $table->boolean('is_home')->default(false);
            $table->unsignedTinyInteger('sort')->default(0);
            $table->timestamps();

            $table->unique(['user_id', 'location_id']);
        });

        // 关心群
        Schema::create('care_groups', function (Blueprint $table) {
            $table->id();
            $table->string('name', 32);
            $table->string('invite_code', 12)->unique();
            $table->foreignId('owner_id')->constrained('users')->cascadeOnDelete();
            $table->timestamps();
        });

        Schema::create('care_group_members', function (Blueprint $table) {
            $table->id();
            $table->foreignId('care_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->timestamps();

            $table->unique(['care_group_id', 'user_id']);
        });

        // 提醒记录：只用于限次、合并、回执，30 天后删除
        Schema::create('reminders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('care_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sender_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('recipient_id')->constrained('users')->cascadeOnDelete();
            $table->string('topic', 24);      // rain / cold / hot / snow / wind / smog / alert ...
            $table->string('phrase_key', 32);
            $table->string('text', 64);       // 发送时的关心话原文
            $table->string('recipient_date', 10); // 被提醒者本地日期，用于每天限次
            $table->timestamp('deliver_at');
            $table->timestamp('delivered_at')->nullable();
            $table->timestamp('acked_at')->nullable();
            $table->foreignId('merged_into_id')->nullable()->constrained('reminders')->nullOnDelete();
            $table->boolean('suppressed')->default(false); // 被静音：照常记录、不推送、发送者无感知
            $table->timestamps();

            $table->index(['sender_id', 'recipient_id', 'recipient_date']);
            $table->index(['delivered_at', 'deliver_at']);
        });

        Schema::create('mutes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete(); // 谁静音
            $table->foreignId('muted_user_id')->nullable()->constrained('users')->cascadeOnDelete();
            $table->foreignId('care_group_id')->nullable()->constrained()->cascadeOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mutes');
        Schema::dropIfExists('reminders');
        Schema::dropIfExists('care_group_members');
        Schema::dropIfExists('care_groups');
        Schema::dropIfExists('user_cities');
    }
};
