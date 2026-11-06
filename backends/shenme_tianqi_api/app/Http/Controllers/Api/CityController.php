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
    public const MAX_CITIES = 5;

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
        return CityResource::collection($request->user()->cities()->orderBy('sort')->get());
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'location_id' => ['required', 'string', 'alpha_num', 'max:32'],
            'name' => ['required', 'string', 'max:64'],
            'adm' => ['nullable', 'string', 'max:64'],
            'is_home' => ['sometimes', 'boolean'],
        ]);
        $user = $request->user();

        $existing = $user->cities()->where('location_id', $data['location_id'])->first();
        if (! $existing && $user->cities()->count() >= self::MAX_CITIES) {
            throw ValidationException::withMessages(['location_id' => '最多关注 '.self::MAX_CITIES.' 个城市']);
        }

        $city = DB::transaction(function () use ($user, $data, $existing) {
            $city = $existing ?? $user->cities()->create([
                'location_id' => $data['location_id'],
                'name' => $data['name'],
                'adm' => $data['adm'] ?? null,
                'sort' => (int) $user->cities()->max('sort') + 1,
            ]);

            // 第一个城市自动设为常驻城市
            if (($data['is_home'] ?? false) || ! $user->cities()->where('is_home', true)->exists()) {
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
        ]);

        DB::transaction(function () use ($request, $city, $data) {
            if (isset($data['sort'])) {
                $city->update(['sort' => $data['sort']]);
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
            // 删掉常驻城市时，把排在最前的设为常驻
            if ($wasHome && $next = $user->cities()->orderBy('sort')->first()) {
                $this->makeHome($user->id, $next);
            }
        });

        return response()->json(['deleted' => true]);
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
