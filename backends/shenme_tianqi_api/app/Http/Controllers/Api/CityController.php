<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CityResource;
use App\Models\UserCity;
use App\Services\WeatherService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CityController extends Controller
{
    /** 不限制用户关注几个城市（2026-11-19 去掉了 5 个的上限），只留一个防刷的上限 */
    public const MAX_CITIES = 50;

    /** 临时城市最多看几天；App 按本地日期算到第几天 0 点，所以多留一天余量 */
    public const MAX_TEMP_DAYS = 7;

    /** 城市搜索：不需要登录，首次打开时选城市用 */
    public function search(Request $request, WeatherService $weather): JsonResponse
    {
        $data = $request->validate(['q' => ['required', 'string', 'min:1', 'max:32']]);

        try {
            return response()->json(['data' => $weather->searchCities($data['q'])]);
        } catch (\RuntimeException) {
            abort(503, '城市搜索暂时不可用');
        }
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        return CityResource::collection($request->user()->cities()->active()->orderBy('sort')->get());
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'location_id' => ['required', 'string', 'alpha_num', 'max:32'],
            'name' => ['required', 'string', 'max:64'],
            'adm' => ['nullable', 'string', 'max:64'],
            'is_home' => ['sometimes', 'boolean'],
            // 临时城市：到这个时间自动移除
            'expires_at' => ['sometimes', 'nullable', ...$this->expiryRules()],
        ]);
        $user = $request->user();
        $temporary = ! empty($data['expires_at']);
        if ($temporary && ($data['is_home'] ?? false)) {
            throw ValidationException::withMessages(['is_home' => '临时城市不能设为常驻']);
        }

        $existing = $user->cities()->where('location_id', $data['location_id'])->first();
        if (! $existing && $user->cities()->active()->count() >= self::MAX_CITIES) {
            throw ValidationException::withMessages(['location_id' => '关注的城市太多了，先删几个吧']);
        }

        $city = DB::transaction(function () use ($user, $data, $existing, $temporary) {
            if ($existing) {
                // 再加一次：按这次的选择改成长期或临时（常驻城市一直是长期的）
                if (array_key_exists('expires_at', $data) && ! $existing->is_home) {
                    $existing->update(['expires_at' => $data['expires_at']]);
                }
                $city = $existing;
            } else {
                $city = $user->cities()->create([
                    'location_id' => $data['location_id'],
                    'name' => $data['name'],
                    'adm' => $data['adm'] ?? null,
                    'sort' => min(255, (int) $user->cities()->max('sort') + 1),
                    'expires_at' => $data['expires_at'] ?? null,
                ]);
            }

            // 第一个长期关注的城市自动设为常驻城市；临时城市不当常驻
            if (! $temporary && (($data['is_home'] ?? false) || ! $user->cities()->where('is_home', true)->exists())) {
                $this->makeHome($user->id, $city);
            }

            return $city->fresh();
        });

        // fresh() 得到的新实例没有 wasRecentlyCreated，这里显式给 201
        return (new CityResource($city))->response()->setStatusCode($existing ? 200 : 201);
    }

    public function update(Request $request, UserCity $city): CityResource
    {
        $this->authorizeCity($request, $city);
        $data = $request->validate([
            'is_home' => ['sometimes', 'accepted'],
            'sort' => ['sometimes', 'integer', 'min:0', 'max:255'],
            // null = 改成长期关注；给时间 = 改成临时
            'expires_at' => ['sometimes', 'nullable', ...$this->expiryRules()],
        ]);
        $temporary = array_key_exists('expires_at', $data) ? $data['expires_at'] !== null : $city->expires_at !== null;
        if (($data['is_home'] ?? false) && $temporary) {
            throw ValidationException::withMessages(['is_home' => '临时城市不能设为常驻，先改成长期关注']);
        }
        if ($city->is_home && ($data['expires_at'] ?? null) !== null) {
            throw ValidationException::withMessages(['expires_at' => '常驻城市不能改成临时的']);
        }

        DB::transaction(function () use ($request, $city, $data) {
            if (isset($data['sort'])) {
                $city->update(['sort' => $data['sort']]);
            }
            if (array_key_exists('expires_at', $data)) {
                $city->update(['expires_at' => $data['expires_at']]);
            }
            if ($data['is_home'] ?? false) {
                $this->makeHome($request->user()->id, $city);
            }
        });

        return new CityResource($city->fresh());
    }

    public function destroy(Request $request, UserCity $city): JsonResponse
    {
        $this->authorizeCity($request, $city);
        $user = $request->user();

        DB::transaction(function () use ($user, $city) {
            $wasHome = $city->is_home;
            $city->delete();
            // 删掉常驻城市时，把排在最前的长期关注城市设为常驻
            if ($wasHome && $next = $user->cities()->whereNull('expires_at')->orderBy('sort')->first()) {
                $this->makeHome($user->id, $next);
            }
        });

        return response()->json(['deleted' => true]);
    }

    /** 临时城市的到期时间：要在未来，最多 MAX_TEMP_DAYS 天（按本地日期算到 0 点，多给一天余量） */
    private function expiryRules(): array
    {
        return ['date', 'after:now', 'before_or_equal:'.now()->addDays(self::MAX_TEMP_DAYS + 1)->toIso8601String()];
    }

    private function makeHome(int $userId, UserCity $city): void
    {
        UserCity::where('user_id', $userId)->whereKeyNot($city->id)->update(['is_home' => false]);
        $city->update(['is_home' => true]);
    }

    private function authorizeCity(Request $request, UserCity $city): void
    {
        abort_unless($city->user_id === $request->user()->id, 404);
    }
}
