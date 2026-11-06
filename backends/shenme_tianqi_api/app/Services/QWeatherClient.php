<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * 和风天气接口的薄封装。只做请求和错误处理，不做业务判断。
 * 文档：https://dev.qweather.com/docs/api/
 */
class QWeatherClient
{
    public function cityLookup(string $keyword): array
    {
        return $this->get('/geo/v2/city/lookup', ['location' => $keyword, 'number' => 10, 'range' => 'cn'])['location'] ?? [];
    }

    public function now(string $locationId): array
    {
        return $this->get('/v7/weather/now', ['location' => $locationId]);
    }

    public function hourly(string $locationId): array
    {
        return $this->get('/v7/weather/24h', ['location' => $locationId]);
    }

    public function daily(string $locationId): array
    {
        return $this->get('/v7/weather/7d', ['location' => $locationId]);
    }

    /** 按经纬度查询，最多两位小数。localTime 让时间带本地时区，默认是 UTC */
    public function alerts(string $lat, string $lon): array
    {
        return $this->get("/weatheralert/v1/current/{$lat}/{$lon}", ['localTime' => 'true']);
    }

    /** 按经纬度查询，最多两位小数 */
    public function air(string $lat, string $lon): array
    {
        return $this->get("/airquality/v1/current/{$lat}/{$lon}", []);
    }

    private function get(string $path, array $query): array
    {
        try {
            $res = $this->http()->get($path, $query + ['lang' => 'zh']);
        } catch (ConnectionException $e) {
            // 超时、断网、没配 Host 都走这里；ConnectionException 不是 RuntimeException，不转换调用方接不住
            throw new RuntimeException("QWeather unreachable {$path}", previous: $e);
        }

        if (! $res->successful()) {
            throw new RuntimeException("QWeather HTTP {$res->status()} {$path}");
        }

        $body = $res->json() ?? [];
        // v7 / geo 接口用 code 字段表示业务状态，200 才是成功
        if (isset($body['code']) && (string) $body['code'] !== '200') {
            throw new RuntimeException("QWeather code {$body['code']} {$path}");
        }

        return $body;
    }

    private function http(): PendingRequest
    {
        $host = config('services.qweather.host');

        return Http::baseUrl(str_starts_with($host, 'http') ? $host : "https://{$host}")
            ->withHeaders(['X-QW-Api-Key' => (string) config('services.qweather.key')])
            ->acceptJson()
            ->timeout(config('services.qweather.timeout', 5))
            ->retry(1, 200, throw: false);
    }
}
