import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import 'temp_unit.dart';

/// 首页背景色：按天气状态，和设计稿首页的几个场景对应。
/// 都是浅一档的柔和色（2026-11-19 调淡，原来晴天是整页亮黄、高温是亮橙，太刺眼），
/// 黄色的决策卡、白卡片放在上面才显眼。
Color sceneColor(String cond, String outfitKey) {
  if (cond == 'sunny' && outfitKey == 'hot') return const Color(0xFFFCDCC2);
  if (cond == 'cloudy' && (outfitKey == 'cold' || outfitKey == 'freezing')) return const Color(0xFFDCEAF6);
  return switch (cond) {
    'sunny' => const Color(0xFFFDF0C9),
    'cloudy' => const Color(0xFFE6E9EF),
    'light_rain' || 'heavy_rain' => const Color(0xFFCCDBF0),
    'thunder' => const Color(0xFFDAD6EF),
    'snow' => const Color(0xFFE8F1FA),
    'wind' => const Color(0xFFE2ECD3),
    'smog' => const Color(0xFFE2DED4),
    'dust' => const Color(0xFFEEDFC2),
    'humid' => const Color(0xFFD3EBDD),
    _ => Pop.paper,
  };
}

/// 预警颜色（气象部门的 severityColor）。不在这几种里的（比如没有颜色的防御提醒）用白底，放在哪种天气的底色上都不突兀
Color warningColor(String color) => switch (color) {
      'Red' => const Color(0xFFD32F2F),
      'Orange' => const Color(0xFFF08C00),
      'Yellow' => const Color(0xFFFFD23F),
      'Blue' => const Color(0xFF2F6BFF),
      'Black' => const Color(0xFF1B1B1F),
      _ => Pop.white,
    };

Color onWarningColor(String color) => (color == 'Red' || color == 'Blue' || color == 'Black') ? Colors.white : const Color(0xFF1B1B1F);

const decisionKeys = ['umbrella', 'long_johns', 'car_wash', 'laundry'];

const decisionTitles = {
  'umbrella': '带不带伞',
  'long_johns': '穿不穿秋裤',
  'car_wash': '洗不洗车',
  'laundry': '晾不晾衣服',
};

/// 秋裤卡的阈值（摄氏度），只用来写说明；判断在服务端，和 config/weather.php 的 decisions.long_johns.feels_below 一致
const longJohnsFeelsBelow = 10;

/// 决策详情里的“怎么判断的”，温度按用户选的单位写
String decisionRule(String key, TempUnit unit) => switch (key) {
      'umbrella' => '7–22 点里，只要有一小时降水概率 ≥ 50% 就说“带”；30–50% 说“随便”；紫外线很强时也会提醒带伞遮阳。',
      'long_johns' => '看今天最低的体感温度：低于 ${unit.deg(longJohnsFeelsBelow)} 就建议穿。',
      'car_wash' => '未来 3 天都没有雨、没有沙尘，才说“洗”。',
      'laundry' => '白天 8–18 点没有雨、平均湿度低于 70%、风力小于 5 级，才说“晾”。',
      _ => '',
    };

const snarkLevels = ['正经', '损友', '毒舌'];

String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
String dayLabel(DateTime d, int index) => index == 0 ? '今天' : (index == 1 ? '明天' : '周${_weekdays[d.weekday - 1]}');
