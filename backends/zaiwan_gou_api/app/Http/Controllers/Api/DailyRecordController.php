<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DailyRecordResource;
use App\Services\DailyRecordService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class DailyRecordController extends Controller
{
    /** 最多允许补报几天前的记录（手机离线时） */
    private const BACKFILL_DAYS = 2;

    private const MAX_RANGE_DAYS = 62;

    public function __construct(private DailyRecordService $service) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $data = $request->validate([
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);

        $from = CarbonImmutable::parse($data['from']);
        $to = CarbonImmutable::parse($data['to']);
        if ($from->diffInDays($to) > self::MAX_RANGE_DAYS) {
            throw ValidationException::withMessages(['to' => '一次最多查询 '.self::MAX_RANGE_DAYS.' 天']);
        }

        $records = $request->user()->dailyRecords()
            ->whereBetween('date', [$data['from'], $data['to']])
            ->orderBy('date')
            ->get();

        return DailyRecordResource::collection($records);
    }

    /**
     * 上报某天的结果。只接受分数类字段，任何其他字段（例如 app 明细）都会被忽略。
     */
    public function upsert(Request $request, string $date): JsonResponse
    {
        $user = $request->user();

        $validator = validator(['date' => $date], ['date' => ['date_format:Y-m-d']]);
        if ($validator->fails()) {
            throw ValidationException::withMessages(['date' => '日期格式应为 YYYY-MM-DD']);
        }

        $today = CarbonImmutable::parse($user->localToday());
        $day = CarbonImmutable::parse($date);
        if ($day->greaterThan($today) || $day->lessThan($today->subDays(self::BACKFILL_DAYS))) {
            throw ValidationException::withMessages(['date' => '只能上报今天和最近 '.self::BACKFILL_DAYS.' 天的记录']);
        }

        $reportable = collect(config('dog.breeds'))
            ->reject(fn ($b) => $b['server_only'] ?? false)
            ->keys()
            ->all();

        $data = $request->validate([
            'dog_percent' => ['required', 'integer', 'min:0', 'max:1000'],
            'minutes_used' => ['required', 'integer', 'min:0', 'max:1440'],
            'breed_key' => ['nullable', 'string', Rule::in($reportable)],
        ]);

        [$record, $unlocked] = $this->service->upsert($user, $day->toDateString(), $data);

        return response()->json([
            'record' => new DailyRecordResource($record),
            'newly_unlocked' => $unlocked,
        ]);
    }
}
