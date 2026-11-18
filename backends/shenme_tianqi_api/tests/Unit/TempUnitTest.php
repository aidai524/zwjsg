<?php

namespace Tests\Unit;

use App\Support\TempUnit;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/** 和 App 的 test/temp_unit_test.dart 用同一组数，两端换算结果要一致 */
class TempUnitTest extends TestCase
{
    #[DataProvider('pairs')]
    public function test_celsius_to_fahrenheit_rounds_to_an_integer(int $celsius, int $fahrenheit): void
    {
        $this->assertSame($fahrenheit, TempUnit::convert($celsius, TempUnit::FAHRENHEIT));
        $this->assertSame($celsius, TempUnit::convert($celsius, TempUnit::CELSIUS));
    }

    public static function pairs(): array
    {
        return [[0, 32], [100, 212], [-40, -40], [37, 99], [14, 57], [10, 50], [-1, 30], [-18, 0], [20, 68], [19, 66]];
    }

    public function test_sentences_get_a_degree_sign(): void
    {
        $this->assertSame('57°', TempUnit::deg(14, TempUnit::FAHRENHEIT));
        $this->assertSame('14°', TempUnit::deg(14, TempUnit::CELSIUS));
        $this->assertSame('0°', TempUnit::deg(-18, TempUnit::FAHRENHEIT));
    }
}
