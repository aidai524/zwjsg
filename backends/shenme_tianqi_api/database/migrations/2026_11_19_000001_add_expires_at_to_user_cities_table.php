<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 临时城市：出差、旅行时看几天，到点自动移除。空 = 长期关注；常驻城市不能是临时的
        Schema::table('user_cities', function (Blueprint $table) {
            $table->timestamp('expires_at')->nullable()->after('sort');
            $table->index('expires_at');
        });
    }

    public function down(): void
    {
        Schema::table('user_cities', function (Blueprint $table) {
            $table->dropIndex(['expires_at']);
            $table->dropColumn('expires_at');
        });
    }
};
