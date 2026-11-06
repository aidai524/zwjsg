<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class BreedController extends Controller
{
    /** 图鉴：全部犬种配置，加上当前用户的解锁情况 */
    public function index(Request $request): JsonResponse
    {
        $owned = $request->user()->breeds()->pluck('first_unlocked_on', 'breed_key');

        $breeds = collect(config('dog.breeds'))->map(fn ($b, $key) => [
            'key' => $key,
            'name' => $b['name'],
            'rarity' => $b['rarity'],
            'quip' => $b['quip'],
            'rule' => $b['rule'],
            'unlocked' => $owned->has($key),
            'unlocked_on' => $owned->has($key) ? Carbon::parse($owned[$key])->toDateString() : null,
        ])->values();

        return response()->json([
            'owned' => $owned->count(),
            'total' => $breeds->count(),
            'breeds' => $breeds,
        ]);
    }
}
