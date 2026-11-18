<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\CareService;
use App\Services\QuipPicker;
use App\Services\WeatherInterpreter;
use App\Services\WeatherService;
use App\Support\TempUnit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;

/**
 * 首页天气：官方数据原样给出 + 玩法结论（形象状态、决策卡、吐槽）。
 * 不登录也能看（游客用 query 里的 level / adm），登录后按用户设置。
 * 温度数字一律是摄氏度，App 按用户选的单位换算显示；unit 只影响句子里的温度。
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
            'unit' => ['sometimes', Rule::in(TempUnit::ALL)],
        ]);

        $level = $user?->snark_level ?? (int) ($q['level'] ?? 1);
        // 单位以这次请求为准（App 每次都带），没带再看用户设置：刚切换单位时，设置可能还没传到服务端
        $unit = $q['unit'] ?? $user?->temp_unit ?? TempUnit::CELSIUS;
        $adm = $user?->cities()->where('location_id', $locationId)->value('adm') ?? ($q['adm'] ?? null);

        try {
            $snap = $weather->snapshot($locationId);
        } catch (\RuntimeException) {
            abort(503, '天气数据暂时拿不到，稍后再试');
        }

        $view = $interpreter->interpret($snap, $adm, $unit);
        $view['quip'] = $quips->pick($view['quip_trigger'], $level, $user ? 'u'.$user->id : 'ip'.$request->ip());
        $view['level'] = $level;

        return response()->json([
            'data' => [
                ...$snap,
                'view' => $view,
            ],
        ]);
    }

    /** 桌面小组件上决策卡的短名字，顺序就是显示顺序；和 App 天气卡的 WeatherCard.shortTitles 一致 */
    public const WIDGET_TITLES = ['umbrella' => '伞', 'long_johns' => '秋裤', 'car_wash' => '洗车', 'laundry' => '晾衣'];

    /** 和风要求：显示了它的数据的地方都要写明 */
    public const CREDIT = '天气服务由和风天气驱动';

    /**
     * 桌面小组件：一个城市的精简天气，小组件大约每 30 分钟自己来取一次（不登录，App 把城市和单位告诉小组件）。
     * 温度和句子都按 unit 写好，iOS、安卓的小组件原样显示，不用各自换算。
     * 不带吐槽（需求是“形象 + 温度 + 一句话结论”），也就不占用户 7 天不重复的吐槽。
     * 严肃模式给第一条预警的标题原文、发布单位和时间，完整原文在 App 里看。
     */
    public function widget(
        Request $request,
        string $locationId,
        WeatherService $weather,
        WeatherInterpreter $interpreter,
    ): JsonResponse {
        abort_unless(preg_match('/^[A-Za-z0-9]{1,32}$/', $locationId) === 1, 404);

        $q = $request->validate([
            'adm' => ['sometimes', 'nullable', 'string', 'max:64'],
            'unit' => ['sometimes', Rule::in(TempUnit::ALL)],
        ]);
        $unit = $q['unit'] ?? TempUnit::CELSIUS;

        try {
            $snap = $weather->snapshot($locationId);
        } catch (\RuntimeException) {
            abort(503, '天气数据暂时拿不到，稍后再试');
        }

        $view = $interpreter->interpret($snap, $q['adm'] ?? null, $unit);
        $today = array_values($snap['daily'])[0] ?? null;
        $warning = $view['serious_warnings'][0] ?? null;

        return response()->json([
            'data' => [
                'location_id' => $locationId,
                'unit' => $unit,
                'temp' => TempUnit::deg($snap['now']['temp'], $unit),
                'text' => $snap['now']['text'],
                'range' => $today ? TempUnit::deg($today['temp_min'], $unit).'～'.TempUnit::deg($today['temp_max'], $unit) : null,
                // 小组件按这两个挑 App 预先画好的形象图
                'cond' => $view['cond'],
                'outfit' => $view['outfit']['key'],
                'serious' => $view['serious'],
                // 一句话结论：和关心群里的“一句事实”同一套规则；严肃模式看预警
                'line' => $view['serious'] ? null : self::fact($view),
                'decisions' => array_map(fn (string $key) => [
                    'key' => $key,
                    'title' => self::WIDGET_TITLES[$key],
                    'label' => $view['decisions'][$key]['label'],
                    // 要行动的（带伞、穿秋裤、洗车、晾衣）标黄，和 App 的 Decision.isAction 一致
                    'action' => in_array($view['decisions'][$key]['verdict'], ['take', 'sun', 'yes'], true),
                ], array_keys(self::WIDGET_TITLES)),
                // 预警原文照登：标题、发布单位、发布时间都不改写
                'warning' => $warning === null ? null : [
                    'title' => $warning['title'],
                    'sender' => $warning['sender'],
                    'pub_time' => $warning['pub_time'],
                    'color' => $warning['color'],
                ],
                'warnings_count' => count($view['serious_warnings']),
                'obs_time' => $snap['now']['obs_time'] ?? null,
                'credit' => self::CREDIT,
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
            default => '体感 '.TempUnit::deg($view['outfit']['feels_like'], $view['unit'] ?? TempUnit::CELSIUS).'，'.$view['outfit']['label'],
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
            'attributions' => $snap['attributions'],
        ];
    }
}
