<?php

use App\Console\Commands\SendMorningBrief;
use App\Services\CareService;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

// 把到点（包括夜间延迟到 07:00）的关心提醒推出去
Artisan::command('care:deliver', function (CareService $care) {
    $this->info('delivered '.$care->deliverDue());
})->purpose('推送到点的关心提醒');

// 提醒记录只留 30 天
Artisan::command('care:prune', function (CareService $care) {
    $this->info('pruned '.$care->prune());
})->purpose('删除 30 天前的提醒记录');

Schedule::command('care:deliver')->everyMinute()->withoutOverlapping();
Schedule::command(SendMorningBrief::class)->everyMinute()->withoutOverlapping();
Schedule::command('care:prune')->dailyAt('04:10');

// TODO 预警推送：每 5 分钟拉一次用户常驻城市的预警，新出现的黄色及以上预警推给 alert_push_on 的用户
