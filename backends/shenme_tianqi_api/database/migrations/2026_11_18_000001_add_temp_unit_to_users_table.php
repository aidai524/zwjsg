<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 温度单位：c 摄氏度、f 华氏度。只影响显示和推送里的句子，规则一律按摄氏度判断
        Schema::table('users', function (Blueprint $table) {
            $table->char('temp_unit', 1)->default('c')->after('snark_level');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('temp_unit');
        });
    }
};
