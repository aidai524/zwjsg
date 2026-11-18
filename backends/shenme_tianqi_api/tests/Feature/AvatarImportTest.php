<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class AvatarImportTest extends TestCase
{
    use RefreshDatabase;

    /** 1x1 的 PNG */
    private const PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

    private function fakeGou(mixed $body, int $status = 200): void
    {
        Http::fake(['gou.test/*' => Http::response($body, $status, ['Content-Type' => 'image/png'])]);
    }

    public function test_import_hands_the_png_back_and_sends_the_series_key(): void
    {
        $this->fakeGou(base64_decode(self::PNG_BASE64));

        // 不登录也能导入；码的大小写、空格、连字符不讲究
        $this->postJson('/api/v1/avatar/import', ['code' => 'abcd - efgh'])->assertOk()
            ->assertJsonPath('data.png', self::PNG_BASE64);

        Http::assertSent(fn (Request $r) => $r->url() === 'https://gou.test/api/v1/avatar-exports/redeem'
            && $r->hasHeader('X-Series-Key', 'series-test-key')
            && $r['code'] === 'ABCDEFGH');
    }

    public function test_malformed_code_is_rejected_without_asking_gou(): void
    {
        Http::fake();
        $this->postJson('/api/v1/avatar/import', ['code' => 'ABC1'])->assertUnprocessable()
            ->assertJsonValidationErrors('code');
        Http::assertNothingSent();
    }

    public function test_wrong_or_expired_code_says_so(): void
    {
        Http::fake(['gou.test/*' => Http::response(['message' => '导出码不对或已经过期'], 404)]);

        $this->postJson('/api/v1/avatar/import', ['code' => 'ABCDEFGH'])->assertUnprocessable()
            ->assertJsonPath('errors.code.0', '导出码不对或已经过期，回“再玩我是狗”重新生成一个');
    }

    public function test_gou_down_or_not_configured_returns_503(): void
    {
        Http::fake(['gou.test/*' => Http::failedConnection()]);
        $this->postJson('/api/v1/avatar/import', ['code' => 'ABCDEFGH'])->assertServiceUnavailable();

        Http::fake(['gou.test/*' => Http::response('', 500)]);
        $this->postJson('/api/v1/avatar/import', ['code' => 'ABCDEFGH'])->assertServiceUnavailable();

        config(['services.series.export_key' => null]);
        $this->postJson('/api/v1/avatar/import', ['code' => 'ABCDEFGH'])->assertServiceUnavailable();
    }

    public function test_anything_but_a_small_png_is_refused(): void
    {
        $this->fakeGou('<html>not an image</html>');
        $this->postJson('/api/v1/avatar/import', ['code' => 'ABCDEFGH'])->assertStatus(502);
    }

    public function test_back_to_the_default_avatar_deletes_the_stored_one(): void
    {
        Storage::fake(config('filesystems.avatar_disk'));
        $user = User::factory()->create();
        $path = "avatars/{$user->id}/a.png";
        Storage::disk(config('filesystems.avatar_disk'))->put($path, base64_decode(self::PNG_BASE64));
        $user->forceFill(['avatar_path' => $path])->save();

        $this->actingAs($user, 'sanctum')->deleteJson('/api/v1/me/avatar')->assertOk()
            ->assertJsonPath('data.avatar_url', null);
        Storage::disk(config('filesystems.avatar_disk'))->assertMissing($path);
        $this->assertNull($user->fresh()->avatar_path);
    }
}
