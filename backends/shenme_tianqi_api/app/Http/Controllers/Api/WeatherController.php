<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\CareService;
use App\Services\QuipPicker;
use App\Services\WeatherInterpreter;
use App\Services\WeatherService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

/**
 * 首页天气：官方数据原样给出 + 玩法结论（形象状态、决策卡、吐槽）。
 * 不登录也能看（游客用 query 里的 level / adm），登录后按用户设置。
 */
class WeatherController extends Controller
{
    public function show(
        Request $request,
        string $locationId,
        WeatherService $weather,
        WeatherInterpreter $interpreter,
        QuipPicker $quips,
    ): JsonResponse {
        abort_unless(preg_match('/^[A-Za-z0-9]{1,32}$/', $locationId) === 1, 404);

        $user = Auth::guard('sanctum')->user();
        $q = $request->validate([
            'level' => ['sometimes', 'integer', 'in:0,1,2'],
            'adm' => ['sometimes', 'nullable', 'string', 'max:64'],
        ]);

        $level = $user?->snark_level ?? (int) ($q['level'] ?? 1);
        $adm = $user?->cities()->where('location_id', $locationId)->value('adm') ?? ($q['adm'] ?? null);

        try {
            $snap = $weather->snapshot($locationId);
        } catch (\RuntimeException) {
            abort(503, '天气数据暂时拿不到，稍后再试');
        }

        $view = $interpreter->interpret($snap, $adm);
        $view['quip'] = $quips->pick($view['quip_trigger'], $level, $user ? 'u'.$user->id : 'ip'.$request->ip());
        $view['level'] = $level;

        return response()->json([
            'data' => [
                ...$snap,
                'view' => $view,
            ],
        ]);
    }

    public static function fact(array $view): string
    {
        $d = $view['decisions'];

        return match (true) {
            $view['serious'] => $view['serious_warnings'][0]['type_name'].'预警中',
            in_array($d['umbrella']['verdict'], ['take', 'maybe'], true) => $d['umbrella']['reason'],
            $d['long_johns']['verdict'] === 'yes' => $d['long_johns']['reason'],
            default => '体感 '.$view['outfit']['feels_like'].'°，'.$view['outfit']['label'],
        };
    }

    /** 给关心群用的精简版 */
    public static function summary(array $snap, array $view): array
    {
        return [
            'temp' => $snap['now']['temp'],
            'text' => $snap['now']['text'],
            'icon' => $snap['now']['icon'],
            'cond' => $view['cond'],
            'outfit' => $view['outfit']['key'],
            'serious' => $view['serious'],
            'umbrella' => $view['decisions']['umbrella']['verdict'],
            'care_topic' => $view['care_topic'],
            // 一句事实（不是吐槽），给发提醒的人参考
            'fact' => self::fact($view),
            'alert' => $view['serious_warnings'][0]['title'] ?? null,
            'phrases' => CareService::phrasesFor($view['care_topic']),
        ];
    }
}
