import 'package:flutter_test/flutter_test.dart';
import 'package:shenme_tianqi/core/models.dart';

void main() {
  test('解析天气接口返回', () {
    final w = WeatherData({
      'location_id': '101010100',
      'now': {'temp': 18, 'feels_like': 16, 'text': '小雨', 'humidity': 90, 'wind_dir': '北风', 'wind_scale': 3},
      'hourly': [
        {'time': '2026-11-06T15:00+08:00', 'temp': 17, 'text': '小雨', 'pop': 60},
      ],
      'daily': [
        {'date': '2026-11-06', 'temp_max': 20, 'temp_min': 12, 'text_day': '小雨'},
      ],
      'warnings': [],
      'air': null,
      'attribution': '天气数据：和风天气',
      'view': {
        'cond': 'light_rain',
        'outfit': {'key': 'mild', 'label': '长袖/薄外套', 'feels_like': 16},
        'serious': false,
        'serious_warnings': [],
        'banner_warnings': [],
        'decisions': {
          'umbrella': {'verdict': 'take', 'label': '带', 'reason': '15点前后降水概率 60%', 'pop': 60, 'hour': 15},
        },
        'quip': '雨不大，但足够让你后悔没带伞。',
      },
    });

    expect(w.temp, 18);
    expect(w.cond, 'light_rain');
    expect(w.outfitKey, 'mild');
    expect(w.decision('umbrella').isAction, isTrue);
    expect(w.decision('umbrella').hour, 15);
    expect(w.decision('laundry').label, ''); // 没给的决策不报错
    expect(w.hourly.single.pop, 60);
    expect(w.todayMin, 12);
    expect(w.air, isNull);
  });

  test('城市序列化往返', () {
    const c = City(locationId: '101280101', name: '广州', adm: '广东省', isHome: true, serverId: 3);
    final back = City.fromJson(c.toJson());
    expect(back.locationId, c.locationId);
    expect(back.isHome, isTrue);
    expect(back.serverId, 3);
  });

  test('群成员的天气摘要', () {
    final m = Member.fromJson({
      'id': 2,
      'nickname': '妈妈',
      'is_me': false,
      'city': '哈尔滨',
      'remaining_today': 2,
      'weather': {
        'temp': -4,
        'text': '小雪',
        'cond': 'snow',
        'outfit': 'freezing',
        'fact': '最低体感约 -9°',
        'alert': null,
        'phrases': [
          {'key': 'snow_warm', 'text': '下雪了，穿暖和点', 'topic': 'snow'},
        ],
      },
    });
    expect(m.temp, -4);
    expect(m.phrases.single.key, 'snow_warm');
    expect(m.alert, isNull);
  });
}
