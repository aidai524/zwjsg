<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CareGroup;
use App\Models\Mute;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** 静音某人或整个群。静音是单向、无声的，对方不会知道。 */
class MuteController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        return response()->json(['data' => Mute::where('user_id', $request->user()->id)
            ->get(['id', 'muted_user_id', 'care_group_id'])]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'muted_user_id' => ['required_without:care_group_id', 'nullable', 'integer', 'exists:users,id'],
            'care_group_id' => ['required_without:muted_user_id', 'nullable', 'integer', 'exists:care_groups,id'],
        ]);
        $me = $request->user();

        if ($groupId = $data['care_group_id'] ?? null) {
            abort_unless(CareGroup::findOrFail($groupId)->hasMember($me), 404);
        }
        abort_if(($data['muted_user_id'] ?? null) === $me->id, 422, '不能静音自己');

        $mute = Mute::firstOrCreate([
            'user_id' => $me->id,
            'muted_user_id' => $data['muted_user_id'] ?? null,
            'care_group_id' => $data['care_group_id'] ?? null,
        ]);

        return response()->json(['data' => $mute->only(['id', 'muted_user_id', 'care_group_id'])], 201);
    }

    public function destroy(Request $request, Mute $mute): JsonResponse
    {
        abort_unless($mute->user_id === $request->user()->id, 404);
        $mute->delete();

        return response()->json(['deleted' => true]);
    }
}
