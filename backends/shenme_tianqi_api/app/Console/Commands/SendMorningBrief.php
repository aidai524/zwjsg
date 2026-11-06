<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\Push\PushGateway;
use App\Services\QuipPicker;
use App\Services\WeatherInterpreter;
use App\Services\WeatherService;
use Illuminate\Console\Command;

/**
 * 早安播报：每分钟跑一次，找出本地时间刚好到点的用户，推一条
 * “今天带伞 · 穿秋裤 · + 一句吐槽”。严肃模式只推预警标题，不吐槽。
 */
class SendMorningBrief extends Command
{
    protected $signature = 'weather:morning';

    protected $description = '给到点的用户推送早安天气';

    public function handle(WeatherService $weather, WeatherInterpreter $interpreter, QuipPicker $quips, PushGateway $push): int
    {
        $sent = 0;

        User::where('morning_push_on', true)
            ->whereNotNull('push_token')
            ->whereHas('homeCity')
            ->with('homeCity')
            ->chunkById(500, function ($users) use (&$sent, $weather, $interpreter, $quips, $push) {
                foreach ($users as $user) {
                    $local = now($user->timezone);
                    $at = substr((string) ($local->isWeekend() ? $user->morning_push_weekend : $user->morning_push_weekday), 0, 5);
                    if ($local->format('H:i') !== $at) {
                        continue;
                    }

                    try {
                        $snap = $weather->snapshot($user->homeCity->location_id);
                    } catch (\RuntimeException) {
                        continue;
                    }
                    $view = $interpreter->interpret($snap, $user->homeCity->adm);

                    if ($view['serious']) {
                        $w = $view['serious_warnings'][0];
                        $push->send($user, $w['title'], "{$w['sender']} 发布，点开看原文", ['type' => 'morning']);
                    } else {
                        $d = $view['decisions'];
                        $title = "{$user->homeCity->name} {$snap['now']['temp']}° · 伞：{$d['umbrella']['label']} · 秋裤：{$d['long_johns']['label']}";
                        $body = $quips->pick($view['quip_trigger'], $user->snark_level, 'u'.$user->id) ?? $view['outfit']['label'];
                        $push->send($user, $title, $body, ['type' => 'morning']);
                    }
                    $sent++;
                }
            });

        $this->info("sent {$sent}");

        return self::SUCCESS;
    }
}
