<?php

namespace Tests\Unit;

use App\Services\DogMeter;
use Tests\TestCase;

class DogMeterTest extends TestCase
{
    public function test_stage_follows_thresholds(): void
    {
        $meter = new DogMeter;

        $this->assertSame(0, $meter->stageFor(0));
        $this->assertSame(0, $meter->stageFor(29));
        $this->assertSame(1, $meter->stageFor(30));
        $this->assertSame(2, $meter->stageFor(72));
        $this->assertSame(3, $meter->stageFor(90));
        $this->assertSame(4, $meter->stageFor(134));
        $this->assertSame(5, $meter->stageFor(150));
        $this->assertSame(5, $meter->stageFor(400));
    }

    public function test_percent_from_minutes(): void
    {
        $meter = new DogMeter;

        $this->assertSame(72, $meter->percentFor(130, 180));
        $this->assertSame(0, $meter->percentFor(30, 0));
    }
}
