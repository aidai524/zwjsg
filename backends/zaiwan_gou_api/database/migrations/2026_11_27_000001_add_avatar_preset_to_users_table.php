<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * 预设形象（2026-11-27：不做捏脸，预设几张捏好的脸给用户挑）。
     * 记的是挑了哪一张（config/dog.php 的 avatar_presets）；为 null 时用拍照形象，没有拍照形象就是默认的那张
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('avatar_preset', 16)->nullable()->after('avatar_regen_left');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('avatar_preset');
        });
    }
};
