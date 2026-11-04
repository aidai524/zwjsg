<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 每个用户每天一条。只存分数和结果，不存任何 app 明细。
        Schema::create('daily_records', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->date('date'); // 用户本地日期
            $table->unsignedSmallInteger('dog_percent');
            $table->unsignedTinyInteger('stage');
            $table->unsignedSmallInteger('minutes_used');
            $table->string('breed_key', 32)->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'date']);
        });

        Schema::create('user_breeds', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('breed_key', 32);
            $table->date('first_unlocked_on');
            $table->timestamps();

            $table->unique(['user_id', 'breed_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_breeds');
        Schema::dropIfExists('daily_records');
    }
};
