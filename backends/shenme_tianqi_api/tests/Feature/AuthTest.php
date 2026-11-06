<?php

namespace Tests\Feature;

use App\Models\User;
use Series\Auth\Sms\SmsSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    private ?string $lastCode = null;

    protected function setUp(): void
    {
        parent::setUp();

        $test = $this;
        $this->app->instance(SmsSender::class, new class($test) implements SmsSender
        {
            public function __construct(private AuthTest $test) {}

            public function sendCode(string $phone, string $code): void
            {
                $this->test->captureCode($code);
            }
        });
    }

    public function captureCode(string $code): void
    {
        $this->lastCode = $code;
    }

    public function test_sms_login_creates_user_and_returns_token(): void
    {
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800001111'])->assertOk();
        $this->assertNotNull($this->lastCode);

        $res = $this->postJson('/api/v1/auth/sms/login', [
            'phone' => '13800001111',
            'code' => $this->lastCode,
        ])->assertOk();

        $res->assertJsonPath('is_new', true)
            ->assertJsonPath('user.phone_masked', '138****1111')
            ->assertJsonPath('user.snark_level', 1);

        $this->getJson('/api/v1/me', ['Authorization' => 'Bearer '.$res->json('token')])->assertOk();
    }

    public function test_wrong_code_is_rejected_and_code_is_single_use(): void
    {
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800002222'])->assertOk();
        $code = $this->lastCode;
        $wrong = $code === '111111' ? '222222' : '111111';

        $this->postJson('/api/v1/auth/sms/login', ['phone' => '13800002222', 'code' => $wrong])
            ->assertStatus(422);

        $this->postJson('/api/v1/auth/sms/login', ['phone' => '13800002222', 'code' => $code])->assertOk();
        $this->postJson('/api/v1/auth/sms/login', ['phone' => '13800002222', 'code' => $code])
            ->assertStatus(422);
    }

    public function test_invalid_phone_is_rejected(): void
    {
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '12345'])->assertStatus(422);
    }

    public function test_delete_account_removes_everything(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('app')->plainTextToken;
        $auth = ['Authorization' => 'Bearer '.$token];

        $this->postJson('/api/v1/cities', ['location_id' => '101010100', 'name' => '北京', 'adm' => '北京市'], $auth)
            ->assertCreated();
        $this->postJson('/api/v1/care-groups', ['name' => '我们家'], $auth)->assertCreated();

        $this->deleteJson('/api/v1/me', [], $auth)->assertOk();

        $this->assertDatabaseMissing('users', ['id' => $user->id]);
        $this->assertDatabaseCount('user_cities', 0);
        $this->assertDatabaseCount('care_groups', 0);
        $this->assertDatabaseCount('care_group_members', 0);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }
}
