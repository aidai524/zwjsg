<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CareGroup;
use App\Models\Reminder;
use App\Models\User;
use App\Services\CareService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ReminderController extends Controller
{
    public function store(Request $request, CareService $care): JsonResponse
    {
        $data = $request->validate([
            'care_group_id' => ['required', 'integer'],
            'recipient_id' => ['required', 'integer'],
            'phrase_key' => ['required', 'string', 'max:32'],
        ]);

        $group = CareGroup::findOrFail($data['care_group_id']);
        $recipient = User::findOrFail($data['recipient_id']);
        $sender = $request->user();

        $reminder = $care->send($sender, $group, $recipient, $data['phrase_key']);
        $care->deliverDue();

        return response()->json(['data' => [
            'id' => $reminder->id,
            'text' => $reminder->text,
            'status' => CareService::senderStatus($reminder->fresh()),
            'deliver_at' => $reminder->deliver_at->toIso8601String(),
            'remaining_today' => $care->remainingToday($sender, $recipient),
        ]], 201);
    }

    /** 收到的提醒（近 30 天，被静音的不出现） */
    public function inbox(Request $request): JsonResponse
    {
        $items = Reminder::where('recipient_id', $request->user()->id)
            ->where('suppressed', false)
            ->whereNotNull('delivered_at')
            ->whereNull('merged_into_id')
            ->with('sender:id,nickname,avatar_path')
            ->latest('id')->limit(100)->get()
            ->map(fn (Reminder $r) => [
                'id' => $r->id,
                'care_group_id' => $r->care_group_id,
                'sender' => $r->sender ? [
                    'id' => $r->sender->id,
                    'nickname' => $r->sender->displayName(),
                    'avatar_url' => $r->sender->avatarUrl(),
                ] : null,
                // 合并到这条的其他提醒人，如“妈妈、爸爸”
                'senders' => Reminder::where('merged_into_id', $r->id)->orWhere('id', $r->id)
                    ->with('sender:id,nickname')->get()
                    ->map(fn (Reminder $x) => $x->sender?->displayName())->filter()->unique()->values(),
                'text' => $r->text,
                'topic' => $r->topic,
                'delivered_at' => $r->delivered_at->toIso8601String(),
                'acked' => (bool) $r->acked_at,
            ]);

        return response()->json(['data' => $items]);
    }

    public function ack(Request $request, Reminder $reminder, CareService $care): JsonResponse
    {
        $care->ack($request->user(), $reminder);

        return response()->json(['acked' => true]);
    }
}
