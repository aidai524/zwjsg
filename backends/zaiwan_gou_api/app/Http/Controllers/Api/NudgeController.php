<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DogGroup;
use App\Models\Nudge;
use App\Models\User;
use App\Services\GroupService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * 汪一下：叫群里的狗友放下手机。同一个人每天最多汪同一个人 2 次。
 * 推送通道还没接，对方下次打开 App 时看到；对方关掉了汪一下的，照样记下但不给对方看，发的人看不出区别。
 */
class NudgeController extends Controller
{
    public function __construct(private GroupService $groups) {}

    public function store(Request $request, DogGroup $dogGroup): JsonResponse
    {
        $sender = $request->user();
        abort_unless($dogGroup->hasMember($sender), 404);
        $data = $request->validate(['recipient_id' => ['required', 'integer']]);

        /** @var User|null $recipient */
        $recipient = $dogGroup->members()->whereKey($data['recipient_id'])->first();
        if (! $recipient) {
            throw ValidationException::withMessages(['recipient_id' => 'TA 不在这个群里']);
        }
        if ($recipient->is($sender)) {
            throw ValidationException::withMessages(['recipient_id' => '不能汪自己']);
        }
        $per = config('dog.groups.nudges_per_pair_per_day');
        if ($this->groups->nudgesLeft($sender, $recipient) <= 0) {
            return response()->json(['message' => "今天已经汪过 TA {$per} 次了，明天再说"], 429);
        }

        Nudge::create([
            'dog_group_id' => $dogGroup->id,
            'sender_id' => $sender->id,
            'recipient_id' => $recipient->id,
            'suppressed' => (bool) $recipient->pivot->mute_nudges,
        ]);

        return response()->json(['nudges_left' => $this->groups->nudgesLeft($sender, $recipient)], 201);
    }

    /** 我还没看过的汪一下（最近 7 天） */
    public function inbox(Request $request): JsonResponse
    {
        $nudges = Nudge::with(['sender', 'group'])
            ->where('recipient_id', $request->user()->id)
            ->where('suppressed', false)
            ->whereNull('seen_at')
            ->where('created_at', '>=', now()->subDays(7))
            ->latest('id')
            ->limit(50)
            ->get()
            ->map(fn (Nudge $n) => [
                'id' => $n->id,
                'sender_id' => $n->sender_id,
                'sender_nickname' => $n->sender->displayName(),
                'group_id' => $n->dog_group_id,
                'group_name' => $n->group->name,
                'created_at' => $n->created_at->toIso8601String(),
            ]);

        return response()->json(['data' => $nudges]);
    }

    public function seen(Request $request): JsonResponse
    {
        $data = $request->validate(['ids' => ['required', 'array', 'max:100'], 'ids.*' => ['integer']]);
        $n = Nudge::where('recipient_id', $request->user()->id)
            ->whereIn('id', $data['ids'])
            ->whereNull('seen_at')
            ->update(['seen_at' => now()]);

        return response()->json(['seen' => $n]);
    }
}
