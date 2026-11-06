import 'package:flutter/material.dart';

/// 首页背景色：按天气状态，和设计稿首页的几个场景一致
Color sceneColor(String cond, String outfitKey) {
  if (cond == 'sunny' && outfitKey == 'hot') return const Color(0xFFFF9F45);
  if (cond == 'cloudy' && (outfitKey == 'cold' || outfitKey == 'freezing')) return const Color(0xFFCFE3F7);
  return switch (cond) {
    'sunny' => const Color(0xFFFFD23F),
    'cloudy' => const Color(0xFFE6E9EF),
    'light_rain' || 'heavy_rain' => const Color(0xFFA9C1E8),
    'thunder' => const Color(0xFF8E8AC7),
    'snow' => const Color(0xFFE8F1FA),
    'wind' => const Color(0xFFDCE9C9),
    'smog' => const Color(0xFFC9C4B5),
    'dust' => const Color(0xFFE6CFA3),
    'humid' => const Color(0xFFBFE3D0),
    _ => const Color(0xFFF3F4F6),
  };
}

/// 预警颜色（气象部门的 severityColor）
Color warningColor(String color) => switch (color) {
      'Red' => const Color(0xFFD32F2F),
      'Orange' => const Color(0xFFF08C00),
      'Yellow' => const Color(0xFFFFD23F),
      'Blue' => const Color(0xFF2F6BFF),
      'Black' => const Color(0xFF1B1B1F),
      _ => const Color(0xFFF3F4F6),
    };

Color onWarningColor(String color) => (color == 'Red' || color == 'Blue' || color == 'Black') ? Colors.white : const Color(0xFF1B1B1F);

const decisionKeys = ['umbrella', 'long_johns', 'car_wash', 'laundry'];

const decisionTitles = {
  'umbrella': '带不带伞',
  'long_johns': '穿不穿秋裤',
  'car_wash': '洗不洗车',
  'laundry': '晾不晾衣服',
};

const decisionRules = {
  'umbrella': '7–22 点里，只要有一小时降水概率 ≥ 50% 就说“带”；30–50% 说“随便”；紫外线很强时也会提醒带伞遮阳。',
  'long_johns': '看今天最低的体感温度：低于 10° 就建议穿。',
  'car_wash': '未来 3 天都没有雨、没有沙尘，才说“洗”。',
  'laundry': '白天 8–18 点没有雨、平均湿度低于 70%、风力小于 5 级，才说“晾”。',
};

const snarkLevels = ['正经', '损友', '毒舌'];

String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
String dayLabel(DateTime d, int index) => index == 0 ? '今天' : (index == 1 ? '明天' : '周${_weekdays[d.weekday - 1]}');
