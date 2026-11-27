<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 群组（原“狗群”）：2–10 人的熟人小群。群里只共享每天的狗度、阶段和犬种，不共享任何 App 明细。
        // 表名带 dog_ 前缀：MySQL 8 里 GROUPS 是保留字
        Schema::create('dog_groups', function (Blueprint $table) {
            $table->id();
            $table->string('name', 32);
            $table->string('invite_code', 12)->unique();
            $table->foreignId('owner_id')->constrained('users')->cascadeOnDelete();
            // 一起做人最长连续了几天：到过 7 天就有“狼群”称号
            $table->unsignedSmallInteger('best_streak')->default(0);
            $table->timestamps();
        });

        Schema::create('dog_group_members', function (Blueprint $table) {
            $table->id();
            $table->foreignId('dog_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            // 隐藏自己的狗度：群里只看得到名字和形象，也不参加评狗王
            $table->boolean('hide_status')->default(false);
            // 关掉“汪一下”：别人照样能汪，你收不到，对方也不知道
            $table->boolean('mute_nudges')->default(false);
            $table->timestamps();

            $table->unique(['dog_group_id', 'user_id']);
        });

        // 汪一下：叫群里的狗友放下手机。30 天后删除（nudges:prune）
        Schema::create('nudges', function (Blueprint $table) {
            $table->id();
            $table->foreignId('dog_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sender_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('recipient_id')->constrained('users')->cascadeOnDelete();
            // 对方关掉了汪一下：照样记下（发的人看不出区别），但不给对方看
            $table->boolean('suppressed')->default(false);
            $table->timestamp('seen_at')->nullable();
            $table->timestamps();

            $table->index(['recipient_id', 'seen_at']);
            $table->index(['sender_id', 'recipient_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('nudges');
        Schema::dropIfExists('dog_group_members');
        Schema::dropIfExists('dog_groups');
    }
};
