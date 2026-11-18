<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\AvatarExportController;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class AvatarExportTest extends TestCase
{
    use RefreshDatabase;

    /** 1x1 的 PNG */
    private const PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake(config('filesystems.avatar_disk'));
    }

    private function userWithAvatar(): User
    {
        $user = User::factory()->create();
        $path = "avatars/{$user->id}/sticker.png";
        Storage::disk(config('filesystems.avatar_disk'))->put($path, base64_decode(self::PNG_BASE64));
        $user->forceFill(['avatar_path' => $path])->save();

        return $user;
    }

    private function export(User $user): string
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/me/avatar/export')
            ->assertCreated()
            ->json('data.code');
    }

    private function redeem(string $code, ?string $key = 'series-test-key')
    {
        return $this->withHeaders($key === null ? [] : ['X-Series-Key' => $key])
            ->postJson('/api/v1/avatar-exports/redeem', ['code' => $code]);
    }

    public function test_export_needs_login_and_a_photo_avatar(): void
    {
        $this->postJson('/api/v1/me/avatar/export')->assertUnauthorized();

        $this->actingAs(User::factory()->create(), 'sanctum')->postJson('/api/v1/me/avatar/export')
            ->assertUnprocessable()
            ->assertJsonValidationErrors('avatar');
    }

    public function test_code_works_once_and_returns_the_cartoon_png(): void
    {
        $code = $this->export($this->userWithAvatar());
        $this->assertMatchesRegularExpression('/^['.AvatarExportController::ALPHABET.']{8}$/', $code);

        $res = $this->redeem($code)->assertOk()->assertHeader('Content-Type', 'image/png');
        $this->assertSame(base64_decode(self::PNG_BASE64), $res->getContent());

        // 取过一次就作废
        $this->redeem($code)->assertNotFound();
    }

    public function test_code_ignores_case_spaces_and_dashes(): void
    {
        $code = $this->export($this->userWithAvatar());
        $typed = strtolower(substr($code, 0, 4)).' - '.strtolower(substr($code, 4));

        $this->redeem($typed)->assertOk();
    }

    public function test_code_expires_after_ten_minutes(): void
    {
        $code = $this->export($this->userWithAvatar());
        $this->travel(11)->minutes();

        $this->redeem($code)->assertNotFound();
    }

    public function test_redeem_needs_the_series_key(): void
    {
        $code = $this->export($this->userWithAvatar());

        $this->redeem($code, key: null)->assertForbidden();
        $this->redeem($code, key: 'wrong-key')->assertForbidden();

        // 服务端没配密钥时谁都取不到，不能拿空密钥蒙混过去
        config(['services.series.export_key' => null]);
        $this->redeem($code, key: '')->assertServiceUnavailable();

        // 被拒绝的请求不会把码用掉
        config(['services.series.export_key' => 'series-test-key']);
        $this->redeem($code)->assertOk();
    }

    public function test_deleted_account_or_avatar_cannot_be_redeemed(): void
    {
        $user = $this->userWithAvatar();
        $code = $this->export($user);
        $user->delete();

        $this->redeem($code)->assertNotFound();
        $this->redeem('ABC')->assertNotFound();
    }
}
