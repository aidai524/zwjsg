<?php

use App\Models\Nudge;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// 汪一下的记录只留 30 天
Artisan::command('nudges:prune', function () {
    $n = Nudge::where('created_at', '<', now()->subDays(30))->delete();
    $this->info("删掉了 {$n} 条 30 天前的汪一下");
})->purpose('删掉 30 天前的“汪一下”记录');

Schedule::command('nudges:prune')->daily();
