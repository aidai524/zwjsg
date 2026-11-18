<?php

namespace App\Support;

/**
 * 温度单位。数据源、缓存、规则判断和接口里的数字一律是摄氏度（数字照搬数据源）；
 * 只有服务端拼给人看的句子（秋裤理由、关心群的一句事实、早安推送标题）按用户选的单位换算。
 * 换算方法和 App 的 lib/core/temp_unit.dart 保持一致：四舍五入到整数。
 */
final class TempUnit
{
    public const CELSIUS = 'c';

    public const FAHRENHEIT = 'f';

    public const ALL = [self::CELSIUS, self::FAHRENHEIT];

    public static function convert(int $celsius, string $unit): int
    {
        return $unit === self::FAHRENHEIT ? (int) round($celsius * 9 / 5 + 32) : $celsius;
    }

    /** 句子里的温度，例如“23°” */
    public static function deg(int $celsius, string $unit): string
    {
        return self::convert($celsius, $unit).'°';
    }
}
