import 'dart:collection';
import 'dart:math' as math;

import 'sound_labels.dart';

/// 听狗叫时原生交过来的（安卓 CallPlugin.kt、iOS CallPlugin.swift）：[MicLevel] 或 [SoundWindow]
sealed class MicInput {
  const MicInput();
}

/// 每 20 毫秒一个音量（dBFS）
final class MicLevel extends MicInput {
  const MicLevel(this.db);

  final double db;
}

/// 一段声音（大约 1 秒）里，每种声音的分数（0–1，各管各的，加起来不一定是 1）
class SoundScores {
  const SoundScores({this.dog = 0, this.voice = 0, this.clap = 0, this.breath = 0});

  final double dog;
  final double voice;
  final double clap;
  final double breath;

  /// 叫出来的：人声或者狗叫
  double get vocal => math.max(dog, voice);

  double of(SoundKind kind) => switch (kind) {
        SoundKind.dog => dog,
        SoundKind.voice => voice,
        SoundKind.clap => clap,
        SoundKind.breath => breath,
      };

  /// 每种取两边大的
  SoundScores max(SoundScores o) => SoundScores(
        dog: math.max(dog, o.dog),
        voice: math.max(voice, o.voice),
        clap: math.max(clap, o.clap),
        breath: math.max(breath, o.breath),
      );
}

/// 手机上的声音分类器对一段声音的判断：iOS 用系统自带的分类器，安卓用 YAMNet（都不联网）。
/// 时间从这次开始听算起（毫秒），跟音量是同一条时间线：第 k 个音量是 [k×20, (k+1)×20) 毫秒
final class SoundWindow extends MicInput {
  const SoundWindow({required this.endMs, required this.lengthMs, this.scores = const SoundScores()});

  /// 原生交过来的：{'end': 毫秒, 'length': 毫秒, 'labels': {分类器的类别名: 0–1}}，类别名按 [soundKinds] 归成几种
  factory SoundWindow.fromMap(Map<dynamic, dynamic> m) {
    final best = {for (final k in SoundKind.values) k: 0.0};
    final labels = m['labels'];
    if (labels is Map) {
      labels.forEach((name, score) {
        final kind = soundKinds[name];
        if (kind != null && score is num) best[kind] = math.max(best[kind]!, score.toDouble());
      });
    }
    return SoundWindow(
      endMs: (m['end'] as num? ?? 0).toInt(),
      lengthMs: (m['length'] as num? ?? 0).toInt(),
      scores: SoundScores(
        dog: best[SoundKind.dog]!,
        voice: best[SoundKind.voice]!,
        clap: best[SoundKind.clap]!,
        breath: best[SoundKind.breath]!,
      ),
    );
  }

  final int endMs;
  final int lengthMs;
  final SoundScores scores;

  int get startMs => endMs - lengthMs;
}

/// 听到的一声判成了什么
enum Heard {
  /// 算一声：叫出来的（人声、狗叫）；分类器拿不准的也算，宁可放过，不把人卡死
  bark,

  /// 是叫出来的，但太小声，没算
  tooQuiet,

  /// 拍手、打响指、敲桌子，不算
  clap,

  /// 吹气、吹口哨这类不是叫出来的，不算
  notVoice,

  /// 太长了（一直说、一直喊、放音乐），不算
  tooLong,
}

/// 判出来的一声
class BarkSound {
  const BarkSound(this.heard, {this.scores, this.count = 0});

  final Heard heard;

  /// 分类器给的分数；分类器用不了、等不到时是 null（只按音量算）
  final SoundScores? scores;

  /// 算上这一声，一共听到几声
  final int count;

  /// 像狗指数（0–100）：分类器觉得这声有多像狗叫
  int? get dogPercent => scores == null ? null : (scores!.dog * 100).round();

  /// 像到狗版的你都服了
  bool get veryDog => heard == Heard.bark && (scores?.dog ?? 0) >= BarkDetector.veryDogMin;
}

/// 听两声狗叫：超时来电想再玩 10 分钟，得对着手机学两声“汪！汪！”。
/// 只在手机上听，不录音、不保存、不上传，也不识别说了什么。
///
/// 1. 先按音量切出每一声（每 20 毫秒一个音量）：开头 0.4 秒估计环境有多吵；
///    一声 = 比环境响 [riseDb] 以上（至少 [minLoudDb]）、持续 [minBarkMs]–[maxBarkMs] 毫秒，后面安静 [gapMs] 毫秒。
///    比环境响 [softRiseDb] 但没到上面那么响的，记成“小声的一声”。
/// 2. 每一声再看手机上的声音分类器（[SoundWindow]）怎么说：叫出来的（人声、狗叫）算一声；
///    拍手、敲东西、吹气不算；分类器拿不准的也算（宁可放过）；小声的人声提醒大点声；太长的不算。
///    分类器用不了（[classify] 是 false）、或者一声结束 [classifyWaitMs] 毫秒还没等到分类，就只按音量算，跟以前一样。
/// 3. 一共听到 [need] 声就算学会了。中间狗版的你会插话（这时原生停下不听），所以不限两声隔多久。
///
/// 两端都用这一份：原生只交音量和分类器的分数，归成哪种声音见 sound_labels.dart。
class BarkDetector {
  BarkDetector({this.frameMs = 20, this.classify = true});

  final int frameMs;

  /// 原生能给声音分类；不能就只按音量算
  bool classify;

  static const calibrateMs = 400;
  static const riseDb = 15.0;
  static const minLoudDb = -38.0;

  /// 小声的一声：比环境响这么多，但没到 [riseDb]
  static const softRiseDb = 8.0;
  static const softMinDb = -50.0;

  /// 一声里中间小一点也算同一声
  static const releaseDb = 6.0;
  static const minBarkMs = 80;
  static const maxBarkMs = 800;
  static const gapMs = 120;
  static const need = 2;

  /// 人声或狗叫的分数到这么多，就算是叫出来的
  static const vocalMin = 0.1;

  /// 拍手、吹气的分数到这么多（并且比叫出来的高），就判成不算
  static const otherMin = 0.2;

  /// 狗叫的分数到这么多：像到狗版的你都服了
  static const veryDogMin = 0.5;

  /// 一声结束后，最多等分类器这么久（按音量的时间算）
  static const classifyWaitMs = 1500;

  /// 分类结果留多久，给刚结束的那一声用
  static const _keepWindowsMs = 4000;

  final _calibration = <double>[];
  bool _calibrated = false;
  double _floor = -60;
  int _elapsed = 0;
  final _loud = _BurstTracker();
  final _soft = _BurstTracker();
  final _windows = Queue<SoundWindow>();
  final _pending = <_Pending>[];

  /// 这次一共听到几声
  int count = 0;

  bool get done => count >= need;

  /// 正叫到一半，或者刚叫完还在等分类器：这时别插话
  bool get busy => _loud.active || _soft.active || _pending.isNotEmpty;

  /// 喂一个音量或者一个分类结果，返回这下判出来的声音（多半是空的）
  List<BarkSound> feed(MicInput input) => switch (input) {
        MicLevel(:final db) => _feedLevel(db),
        SoundWindow() => _feedWindow(input),
      };

  /// 原生停下又重新开始听（中间狗版的你插了句话）：时间从 0 重新算，还没判完的那几声不要了；
  /// 已经听到几声、环境有多吵沿用
  void restart({required bool classify}) {
    this.classify = classify;
    _elapsed = 0;
    _loud.reset();
    _soft.reset();
    _windows.clear();
    _pending.clear();
    if (!_calibrated) _calibration.clear();
  }

  double get _threshold => math.max(_floor + riseDb, minLoudDb);

  List<BarkSound> _feedLevel(double db) {
    _elapsed += frameMs;
    if (!_calibrated) {
      _calibration.add(db);
      if (_elapsed + frameMs > calibrateMs) {
        // 取偏安静的那一档：开头就喊也不至于把“环境噪音”估得太高
        final sorted = [..._calibration]..sort();
        _floor = sorted[sorted.length ~/ 4].clamp(-80.0, -30.0);
        _calibrated = true;
      }
      return const [];
    }
    final threshold = _threshold;
    final out = <BarkSound>[];
    final loud = _loud.feed(_elapsed, frameMs, db, threshold);
    if (!_loud.active && loud == null && db < threshold) {
      // 环境慢慢变吵、变安静，跟着调
      _floor = math.min(_floor * 0.95 + math.max(db, -80.0) * 0.05, -30.0);
    }
    if (loud != null) _closed(loud, soft: false, out);
    final soft = _soft.feed(_elapsed, frameMs, db, math.max(_floor + softRiseDb, softMinDb));
    // 响的那一声也会被“小声”的盯上：只要没响到算一声的，才是小声的一声
    if (soft != null && soft.peak < threshold && !_loud.active) _closed(soft, soft: true, out);
    for (final p in [..._pending]) {
      if (_elapsed - p.burst.endMs >= classifyWaitMs) _resolve(p, out);
    }
    return out;
  }

  List<BarkSound> _feedWindow(SoundWindow w) {
    _windows.addLast(w);
    while (_windows.isNotEmpty && w.endMs - _windows.first.endMs > _keepWindowsMs) {
      _windows.removeFirst();
    }
    final out = <BarkSound>[];
    for (final p in [..._pending]) {
      p.add(w);
      if (w.endMs >= p.burst.endMs) _resolve(p, out);
    }
    return out;
  }

  /// 切出了一声：太短的（咔哒声）不管；分类器能用就等它的判断，用不了按音量算
  void _closed(_Burst burst, List<BarkSound> out, {required bool soft}) {
    if (burst.ms < minBarkMs) return;
    final p = _Pending(burst, soft: soft);
    if (!classify) {
      _resolve(p, out);
      return;
    }
    _pending.add(p);
    for (final w in _windows) {
      p.add(w);
    }
    if (_windows.any((w) => w.endMs >= burst.endMs)) _resolve(p, out);
  }

  void _resolve(_Pending p, List<BarkSound> out) {
    _pending.remove(p);
    final s = p.scores;
    final tooLong = p.burst.ms > maxBarkMs;
    if (p.soft) {
      // 小声的：分类器说是叫出来的才提醒大点声；别的（翻书、碰桌子）不管
      if (s != null && s.vocal >= vocalMin && !tooLong) out.add(BarkSound(Heard.tooQuiet, scores: s, count: count));
      return;
    }
    if (s != null && s.vocal < vocalMin) {
      if (s.clap >= otherMin && s.clap >= s.breath) {
        out.add(BarkSound(Heard.clap, scores: s, count: count));
        return;
      }
      if (s.breath >= otherMin) {
        out.add(BarkSound(Heard.notVoice, scores: s, count: count));
        return;
      }
    }
    if (tooLong) {
      out.add(BarkSound(Heard.tooLong, scores: s, count: count));
      return;
    }
    count++;
    out.add(BarkSound(Heard.bark, scores: s, count: count));
  }
}

/// 切出来的一声：[startMs] 到 [endMs]（最后一个够响的音量结束的时候），最响 [peak] dBFS
class _Burst {
  const _Burst(this.startMs, this.endMs, this.peak);

  final int startMs;
  final int endMs;
  final double peak;

  int get ms => endMs - startMs;
}

/// 按一个门槛切声音：够响就开始一声，中间小一点（[BarkDetector.releaseDb] 以内）不断，安静够 [BarkDetector.gapMs] 才算这声结束
class _BurstTracker {
  bool active = false;
  int _start = 0;
  int _lastLoud = 0;
  int _quiet = 0;
  double _peak = -120;

  void reset() {
    active = false;
    _quiet = 0;
  }

  /// [now] 是这一帧结束的时间；一声结束了就返回它
  _Burst? feed(int now, int frameMs, double db, double threshold) {
    if (!active) {
      if (db >= threshold) {
        active = true;
        _start = now - frameMs;
        _lastLoud = now;
        _quiet = 0;
        _peak = db;
      }
      return null;
    }
    if (db >= threshold - BarkDetector.releaseDb) {
      _lastLoud = now;
      _quiet = 0;
      _peak = math.max(_peak, db);
      return null;
    }
    _quiet += frameMs;
    if (_quiet < BarkDetector.gapMs) return null;
    active = false;
    return _Burst(_start, _lastLoud, _peak);
  }
}

/// 切出来、还在等分类器判断的一声
class _Pending {
  _Pending(this.burst, {required this.soft});

  final _Burst burst;
  final bool soft;
  SoundScores? scores;

  /// 跟这一声沾边的分类结果，每种取最高的
  void add(SoundWindow w) {
    if (w.endMs <= burst.startMs || w.startMs >= burst.endMs) return;
    scores = scores == null ? w.scores : scores!.max(w.scores);
  }
}
