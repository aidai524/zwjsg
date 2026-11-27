import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/app_state.dart';
import '../../core/bark_detector.dart';
import '../../core/call_channel.dart';
import '../../core/dog_meter.dart';
import 'call_script.dart';
import 'call_voice.dart';
import 'call_widgets.dart';

/// 来电界面走到哪一步了
enum CallPhase {
  /// 响铃：拒接（今天锁死）/ 接听
  ringing,

  /// 通话中：狗版的你一句一句说，可以学狗叫、挂断
  talking,

  /// 在听你学狗叫
  listening,

  /// 没听清，再来一次
  missed,

  /// 没开麦克风、麦克风打不开：按住 10 秒代替
  noMic,

  /// 学会了，放行，过一会儿自己挂断
  granted,

  /// 接了又挂了（不玩了）
  ended,

  /// 拒接了：今天锁死
  declined,

  /// 安卓：今天拒接过，再打开那个 App 直接是这一页
  locked,
}

/// 超时来电（2026-11-23 起两端共用）：像 FaceTime 的来电界面——铺满屏幕的模糊形象、一圈圈的波纹、
/// 一直在晃的接听键、铃声和震动；接听后有通话计时、狗版的你一句一句说（字幕 + 打包好的语音，台词见 [CallScript]），
/// 再选学两声狗叫（再玩 10 分钟）还是挂断（不玩了）。拒接 = 这个限时今天锁死，明天 0 点解开。
/// 学狗叫时狗版的你会插话（2026-11-24）：学了一声“再来一声”、拍手“拍手不算”、太小声、太长、特别像，各说一次；
/// 插话时先停下不听，说完接着听。
/// 打电话来的是用户自己越刷越像狗的那个身份（2026-11-23 起叫“狗版的你”，不叫“你的狗”）。
///
/// 安卓：CallReminderActivity 用单独的 Flutter 引擎跑 [CallApp]（入口 main.dart 的 callMain）；
/// iOS：App 里由 CallGate 弹出这一页。
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.call,
    this.backend = const PlatformCallBackend(),
    this.onClose,
    this.random,
    this.now,
  });

  final IncomingCall call;
  final CallBackend backend;

  /// 关掉来电界面，参数是放行了没有。默认关掉这一页（iOS）；安卓交给原生关 Activity
  final ValueChanged<bool>? onClose;

  /// 挑哪句台词；只在测试里传
  final math.Random? random;

  /// 现在几点（半夜换一句开场）；只在测试里传
  final DateTime Function()? now;

  /// 响多久没人接就不响了（界面还在，还是得选）
  static const ringFor = Duration(seconds: 30);

  /// 估一个字念多久（系统语音一秒四五个字）：字幕按这个一句一句出来，念完了才催
  static const perChar = Duration(milliseconds: 240);

  /// 提完条件多久还没动静就催一句
  static const nudgeAfter = Duration(seconds: 6);

  /// 估一句话念多久
  static Duration speakTime(String line) => perChar * line.length;

  /// 听多久没听到两声就让再来一次（狗版的你插完话重新算）
  static const listenFor = Duration(seconds: 12);

  /// 判出一声以后，等这么久没接着叫，狗版的你才插话（连着“汪！汪！”不打断）
  static const reactAfter = Duration(milliseconds: 900);

  /// 没开麦克风时，按住多久代替学狗叫
  static const holdFor = Duration(seconds: 10);

  /// 放行以后，说完那句话再挂断，最多等这么久
  static const grantedFor = Duration(seconds: 5);

  /// 挂断后“通话结束”停多久再关掉
  static const endedFor = Duration(milliseconds: 1200);

  /// 波形画最近多少个音量
  static const waveLevels = 30;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  late CallPhase _phase;
  int _stage = 0;
  bool _ringTimedOut = false;
  Timer? _ringTimer;

  // 通话
  late final math.Random _random = widget.random ?? math.Random();
  int _seconds = 0;
  Timer? _clock;

  /// 这通电话要说的：开场、按阶段吐槽、提条件。接通时挑好，字幕和念的一样
  List<String> _script = const [];
  final _lines = <String>[];
  Timer? _lineTimer;
  Timer? _speakTimer;
  Timer? _quietTimer;
  Timer? _nudgeTimer;
  bool _speaker = true;
  bool _speaking = false;

  /// 放行时说的那句（原文，带语气词）
  String _grantedLine = '';

  /// 用户挑的声音
  CallVoice _voice = CallVoice.fallback;

  // 听狗叫
  bool _micDenied = false;
  int _heard = 0;
  final _recent = <double>[];
  BarkDetector? _detector;
  StreamSubscription<MicInput>? _mic;
  Timer? _listenTimer;

  /// 刚判出来的那一声（爪印下面写着像狗多少）
  BarkSound? _last;

  /// 狗版的你正在插话（这时原生停下不听）；插的那句（原文，带语气词）
  bool _reacting = false;
  String? _reaction;
  Timer? _reactTimer;

  /// 这一轮已经插过的话：每种一轮只说一次
  final _reacted = <Heard>{};

  /// 每次开麦克风、关麦克风都加 1：开的时候等原生回话，回来时已经关了（挂断、插话）就不管了
  int _micSession = 0;

  // 没麦克风时按住
  Timer? _holdTimer;
  int _heldMs = 0;

  Timer? _endTimer;
  bool _hungUp = false;
  bool _closed = false;

  IncomingCall get call => widget.call;
  CallBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _phase = call.locked
        ? CallPhase.locked
        : call.answered
            ? CallPhase.talking
            : CallPhase.ringing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_phase == CallPhase.ringing) _startRinging();
      // iOS：在屏蔽页上已经点了接听
      if (_phase == CallPhase.talking) _connect();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _stage = call.stageFor(state.goalMinutes);
    _voice = CallVoice.byName(state.callVoiceName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAll();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 切走了就别一直响、一直说、一直听；回来接着响
      backend.stopRing();
      backend.stopSpeaking();
      _holdUp();
      if (_phase == CallPhase.listening) {
        _stopListening();
        setState(() {
          _phase = CallPhase.missed;
          _reacting = false;
        });
      }
    } else if (state == AppLifecycleState.resumed && _phase == CallPhase.ringing && !_ringTimedOut) {
      backend.ring();
    }
  }

  // MARK: 响铃

  void _startRinging() {
    backend.ring();
    _ringTimer = Timer(CallScreen.ringFor, () {
      backend.stopRing();
      if (mounted) setState(() => _ringTimedOut = true);
    });
  }

  void _answer() {
    if (_phase != CallPhase.ringing) return;
    HapticFeedback.mediumImpact();
    setState(() => _phase = CallPhase.talking);
    _connect();
  }

  Future<void> _decline() async {
    if (_phase != CallPhase.ringing) return;
    _ringTimer?.cancel();
    HapticFeedback.mediumImpact();
    backend.stopRing();
    backend.tone(CallTone.hangup);
    setState(() => _phase = CallPhase.declined);
    if (!call.preview) await backend.decline(call.lockId);
  }

  // MARK: 通话

  /// 接通时挑这通电话的台词（原文，带语气词）：试一下来电是“演习”，半夜换一句开场，再按今天的阶段吐槽、提条件。
  /// App 名称和分钟数不在台词里，写在标题下面（[_limitInfo]）
  List<String> _pickScript() {
    final now = (widget.now ?? DateTime.now)();
    final open = call.preview
        ? CallScript.openDrill
        : CallScript.isNight(now)
            ? CallScript.openNight
            : CallScript.pick(CallScript.open, _random);
    return [open, CallScript.stage[_stage], CallScript.pick(CallScript.ask, _random)];
  }

  void _connect() {
    _ringTimer?.cancel();
    backend.stopRing();
    backend.tone(CallTone.connect);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _script = _pickScript();
    _lines
      ..clear()
      ..add(CallScript.plain(_script.first));
    _speaking = true;
    // 等接通的“嘟”响完再开口
    _speakTimer = Timer(_toneGap, () => _sayLine(0));
  }

  static const _toneGap = Duration(milliseconds: 450);

  /// 两句之间停一下
  static const _lineGap = Duration(milliseconds: 250);

  /// 狗版的你说一句（原文，带语气词）：放用户挑的那个声音打包好的语音；放不了（资源缺了之类）再用系统语音念。
  /// 关了扬声器就不出声。返回这句大概说多久。说的时候界面已经换到别的阶段（比如开始听狗叫了），马上停掉
  Future<Duration> _say(String line, {required CallPhase during}) async {
    final plain = CallScript.plain(line);
    if (!_speaker) return CallScreen.speakTime(plain);
    final ms = await backend.playVoice(_voice.asset(line));
    if (!mounted || _phase != during) {
      backend.stopSpeaking();
      return Duration.zero;
    }
    if (ms != null && ms > 0) return Duration(milliseconds: ms);
    backend.speak(plain);
    return CallScreen.speakTime(plain);
  }

  /// 一句一句说，字幕跟着出；最后一句说完 [CallScreen.nudgeAfter] 还没动静就催一句
  Future<void> _sayLine(int i) async {
    if (!mounted || i >= _script.length || _phase != CallPhase.talking) return;
    if (i > 0) setState(() => _lines.add(CallScript.plain(_script[i])));
    final took = await _say(_script[i], during: CallPhase.talking);
    if (!mounted || _phase != CallPhase.talking) return;
    if (i + 1 < _script.length) {
      _lineTimer = Timer(took + _lineGap, () => _sayLine(i + 1));
    } else {
      _quietTimer = Timer(took, () {
        if (mounted) setState(() => _speaking = false);
        _nudgeTimer = Timer(CallScreen.nudgeAfter, _nudge);
      });
    }
  }

  /// 提完条件半天没动静：催一句，只催一次
  Future<void> _nudge() async {
    if (!mounted || _phase != CallPhase.talking) return;
    final line = CallScript.pick(CallScript.nudge, _random);
    setState(() {
      _lines.add(CallScript.plain(line));
      _speaking = true;
    });
    final took = await _say(line, during: CallPhase.talking);
    if (!mounted) return;
    _quietTimer = Timer(took, () {
      if (mounted) setState(() => _speaking = false);
    });
  }

  void _toggleSpeaker() {
    setState(() => _speaker = !_speaker);
    if (!_speaker) {
      backend.stopSpeaking();
    } else if (_phase == CallPhase.talking && _script.isNotEmpty) {
      // 再打开扬声器：把条件再说一遍
      _say(_script.last, during: CallPhase.talking);
    }
  }

  /// 接了又挂了：不放行，也不锁死
  Future<void> _hangUp() async {
    if (_closed || _phase == CallPhase.ended) return;
    _stopAll();
    backend.tone(CallTone.hangup);
    setState(() {
      _phase = CallPhase.ended;
      _speaking = false;
    });
    if (!call.preview) await backend.hangUp(call.lockId);
    _endTimer = Timer(CallScreen.endedFor, () => _close(false));
  }

  // MARK: 学狗叫

  Future<void> _startBark() async {
    _stopListening();
    _holdUp();
    backend.stopSpeaking();
    _lineTimer?.cancel();
    _quietTimer?.cancel();
    _speakTimer?.cancel();
    _nudgeTimer?.cancel();
    setState(() {
      _phase = CallPhase.listening;
      _heard = 0;
      _recent.clear();
      _speaking = false;
      _last = null;
      _reaction = null;
      _reacting = false;
    });
    _reacted.clear();
    _detector = BarkDetector();
    await _listen();
  }

  /// 开麦克风听；插完话接着听也走这里（已经听到几声接着算）
  Future<void> _listen() async {
    final session = ++_micSession;
    _mic = backend.mic().listen(_onMic, onError: (Object _) {});
    final result = await backend.startListening();
    if (!mounted || session != _micSession || _phase != CallPhase.listening || _reacting) return;
    if (result != 'listening' && result != 'levels') {
      _stopListening();
      setState(() {
        _phase = CallPhase.noMic;
        _micDenied = result == 'denied';
      });
      return;
    }
    // 分类器用不了（'levels'）：只按音量算，跟以前一样
    _detector?.classify = result == 'listening';
    _listenTimer = Timer(CallScreen.listenFor, _missed);
  }

  /// 听了半天没听到两声
  void _missed() {
    _stopListening();
    if (!mounted) return;
    setState(() => _phase = CallPhase.missed);
    // 麦克风已经关了，才开口（不会把自己的声音当成狗叫）
    _say(CallScript.missed, during: CallPhase.missed);
  }

  void _onMic(MicInput input) {
    final detector = _detector;
    if (detector == null || _phase != CallPhase.listening || _reacting) return;
    final heard = detector.feed(input);
    if (input is MicLevel) {
      _recent.add(input.db);
      if (_recent.length > CallScreen.waveLevels) _recent.removeAt(0);
    }
    if (heard.isEmpty) {
      if (input is MicLevel) setState(() {});
      return;
    }
    if (heard.any((s) => s.heard == Heard.bark)) HapticFeedback.heavyImpact();
    setState(() {
      _heard = detector.count;
      _last = heard.last;
    });
    if (detector.done) {
      _grant();
      return;
    }
    _planReaction(heard.last);
  }

  /// 判出一声以后，等一小会儿没接着叫，狗版的你才插话；每种话一轮只说一次
  void _planReaction(BarkSound sound) {
    _reactTimer?.cancel();
    if (_reacted.contains(sound.heard)) return;
    final line = switch (sound.heard) {
      Heard.bark => sound.veryDog ? CallScript.veryDog : CallScript.pick(CallScript.barkOne, _random),
      Heard.tooQuiet => CallScript.tooQuiet,
      Heard.clap => CallScript.notVoice,
      Heard.tooLong => CallScript.tooLong,
      // 吹气、吹口哨：爪印下面写一行就行
      Heard.notVoice => null,
    };
    if (line == null) return;
    void fire() {
      if (!mounted || _phase != CallPhase.listening) return;
      // 正叫到一半（或者刚叫完还没判）：等这声完了再说
      if (_detector?.busy ?? false) {
        _reactTimer = Timer(CallScreen.reactAfter, fire);
        return;
      }
      _react(sound.heard, line);
    }

    _reactTimer = Timer(CallScreen.reactAfter, fire);
  }

  /// 狗版的你插一句：先停下不听（不会把自己的声音当成狗叫），说完接着听，已经听到几声接着算
  Future<void> _react(Heard heard, String line) async {
    if (!mounted || _phase != CallPhase.listening || _reacting) return;
    _reacted.add(heard);
    _listenTimer?.cancel();
    _pauseMic();
    setState(() {
      _reacting = true;
      _speaking = true;
      _reaction = line;
    });
    final took = await _say(line, during: CallPhase.listening);
    if (!mounted || _phase != CallPhase.listening) return;
    _reactTimer = Timer(took + _lineGap, _resume);
  }

  Future<void> _resume() async {
    if (!mounted || _phase != CallPhase.listening) return;
    setState(() {
      _reacting = false;
      _speaking = false;
      // 字幕换回提示：还差几声
      _reaction = null;
    });
    _detector?.restart(classify: true);
    await _listen();
  }

  /// 不听了：关麦克风，这一轮作废
  void _stopListening() {
    _listenTimer?.cancel();
    _listenTimer = null;
    _reactTimer?.cancel();
    _reactTimer = null;
    _pauseMic();
    _detector = null;
  }

  /// 关麦克风（插话时也关），听到几声还留着
  void _pauseMic() {
    _micSession++;
    if (_mic == null) return;
    _mic!.cancel();
    _mic = null;
    backend.stopListening();
  }

  /// 按住：每 100 毫秒记一次，按满 [CallScreen.holdFor] 就放行；中途松手从头来
  void _holdDown() {
    _holdTimer?.cancel();
    _heldMs = 0;
    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _heldMs += 100;
      if (_heldMs >= CallScreen.holdFor.inMilliseconds) {
        timer.cancel();
        _grant();
        return;
      }
      if (mounted) setState(() {});
    });
  }

  void _holdUp() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_heldMs == 0) return;
    _heldMs = 0;
    if (mounted && _phase == CallPhase.noMic) setState(() {});
  }

  Future<void> _grant() async {
    if (_phase == CallPhase.granted) return;
    _stopListening();
    _holdTimer?.cancel();
    _heldMs = 0;
    HapticFeedback.heavyImpact();
    setState(() {
      _phase = CallPhase.granted;
      _heard = BarkDetector.need;
      _speaking = true;
      _reacting = false;
      _grantedLine = CallScript.pick(CallScript.granted, _random);
    });
    var ok = call.preview;
    if (!call.preview) {
      try {
        ok = await backend.grant(call.lockId);
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted) return;
    if (!ok) {
      // 限时可能刚被删掉：不放行，挂断
      _hangUp();
      return;
    }
    // 说完那句再挂断（最多等 [CallScreen.grantedFor]）
    final took = await _say(_grantedLine, during: CallPhase.granted);
    if (!mounted) return;
    final wait = took + _lineGap * 2;
    _endTimer = Timer(wait < CallScreen.grantedFor ? wait : CallScreen.grantedFor, () {
      backend.tone(CallTone.hangup);
      if (mounted) {
        setState(() {
          _hungUp = true;
          _speaking = false;
        });
      }
      _endTimer = Timer(CallScreen.endedFor, () => _close(true));
    });
  }

  // MARK: 关掉

  void _close(bool granted) {
    if (_closed) return;
    _closed = true;
    _stopAll();
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(granted);
      return;
    }
    // iOS、“试一下来电”：原生只收起声音（把声音还给别的 App），页面由这里关
    backend.close(granted: granted);
    if (mounted) Navigator.of(context).pop(granted);
  }

  /// 安卓的返回键：响铃时 = 先不接（不锁死，下次打开那个 App 还会来电），通话中 = 挂断
  void _back() {
    switch (_phase) {
      case CallPhase.ringing:
        _stopAll();
        if (!call.preview) backend.hangUp(call.lockId);
        _close(false);
      case CallPhase.talking || CallPhase.listening || CallPhase.missed || CallPhase.noMic:
        _hangUp();
      case CallPhase.ended || CallPhase.declined || CallPhase.locked:
        _close(false);
      case CallPhase.granted:
        break;
    }
  }

  void _stopAll() {
    for (final t in [_ringTimer, _clock, _lineTimer, _speakTimer, _quietTimer, _nudgeTimer, _holdTimer, _endTimer]) {
      t?.cancel();
    }
    backend.stopRing();
    backend.stopSpeaking();
    _stopListening();
  }

  // MARK: 界面

  bool get _lockedOut => _phase == CallPhase.declined || _phase == CallPhase.locked;

  /// 锁死的是什么：安卓写 App 名，iOS 只知道是哪个限时
  String get _what => call.label != null ? '「${call.label}」' : '这个限时里的 App ';

  /// 标题下面：哪个限时、今天用了多久。只写在屏幕上，不念
  String get _limitInfo {
    final used = call.usedMinutes;
    final name = call.label != null ? '「${call.label}」' : call.title;
    final dog = call.dogPercent;
    if (dog != null) {
      return used != null ? '$name今天 ${DogMeter.formatMinutes(used)} · 狗度过了 $dog%' : '$name · 今天狗度过了 $dog%';
    }
    final limit = DogMeter.formatMinutes(call.limitMinutes);
    return used != null ? '$name今天 ${DogMeter.formatMinutes(used)} · 一天限 $limit' : '$name · 一天限 $limit，用满了';
  }

  CallAvatarMood get _mood => switch (_phase) {
        CallPhase.ringing => _ringTimedOut ? CallAvatarMood.quiet : CallAvatarMood.ringing,
        CallPhase.talking || CallPhase.granted => _speaking ? CallAvatarMood.speaking : CallAvatarMood.quiet,
        CallPhase.listening => _reacting ? CallAvatarMood.speaking : CallAvatarMood.listening,
        CallPhase.missed || CallPhase.noMic || CallPhase.ended => CallAvatarMood.quiet,
        CallPhase.declined || CallPhase.locked => CallAvatarMood.sad,
      };

  String get _clockText => '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Pop.overlayOnDark,
        child: Scaffold(
          backgroundColor: CallColors.night,
          body: Stack(
            fit: StackFit.expand,
            children: [
              CallBackdrop(stage: _stage, gloomy: _lockedOut),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 28),
                      _header(),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final size = math.max(40.0, math.min(_lockedOut ? 120.0 : 168.0, box.maxHeight / 1.9));
                            return Center(child: CallAvatar(stage: _stage, mood: _mood, size: size, hops: _heard));
                          },
                        ),
                      ),
                      _middle(),
                      const SizedBox(height: 18),
                      _bottom(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    const subtitleStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: CallColors.faint,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final Widget subtitle = switch (_phase) {
      CallPhase.ringing when !_ringTimedOut => const CallingDots(text: '再玩我是狗 · 语音通话', style: subtitleStyle),
      CallPhase.ringing => const Text('响了半天没人接……它不挂，接一下吧', style: subtitleStyle),
      // 狗版的你的声音是 AI 合成的：通话中一直写明（MiniMax 用户协议、《人工智能生成合成内容标识办法》要求显著标识）
      CallPhase.talking || CallPhase.missed => Text('$_clockText · AI 合成语音', style: subtitleStyle),
      CallPhase.noMic => Text(_clockText, style: subtitleStyle),
      CallPhase.listening =>
        Text(_reacting ? '$_clockText · AI 合成语音' : '$_clockText · 正在听你学狗叫', style: subtitleStyle),
      CallPhase.granted => Text(_hungUp ? '通话结束' : '$_clockText · 放行了 · AI 合成语音', style: subtitleStyle),
      CallPhase.ended => const Text('通话结束', style: subtitleStyle),
      CallPhase.declined => const Text('已拒接', style: subtitleStyle),
      CallPhase.locked => const Text('今天拒接过', style: subtitleStyle),
    };
    return Column(
      children: [
        const Text('狗版的你',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
        const SizedBox(height: 6),
        subtitle,
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [_pill(DogMeter.stageNames[_stage]), if (!_lockedOut) _pill(_limitInfo)],
        ),
        if (call.preview) ...[
          const SizedBox(height: 10),
          const CallHint(icon: Icons.science_outlined, text: '试一下：不会真的锁上，也不会真的放行'),
        ],
      ],
    );
  }

  Widget _middle() {
    switch (_phase) {
      case CallPhase.ringing:
        return const SizedBox.shrink();
      case CallPhase.talking:
        return Align(alignment: Alignment.centerLeft, child: CallCaptions(lines: _lines));
      case CallPhase.ended:
        return Align(
          alignment: Alignment.centerLeft,
          child: Opacity(opacity: 0.5, child: CallCaptions(lines: _lines.isEmpty ? const ['不玩了。'] : _lines)),
        );
      case CallPhase.listening:
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CallCaptions(lines: [
                _reaction != null
                    ? CallScript.plain(_reaction!)
                    : _heard == 0
                        ? '对着手机学两声狗叫：汪！汪！'
                        : '还差一声：汪！',
              ]),
            ),
            const SizedBox(height: 10),
            BarkMeter(heard: _heard, levels: _reacting ? const [] : _recent, note: _note, paused: _reacting),
          ],
        );
      case CallPhase.missed:
        return Column(
          children: [
            Align(alignment: Alignment.centerLeft, child: CallCaptions(lines: [CallScript.plain(CallScript.missed)])),
            const SizedBox(height: 10),
            BarkMeter(heard: _heard, listening: false, note: _note),
          ],
        );
      case CallPhase.noMic:
        return Align(
          alignment: Alignment.centerLeft,
          child: CallCaptions(lines: [
            _micDenied
                ? '没开麦克风，就学不了狗叫。去设置里打开，或者按住下面的按钮 ${CallScreen.holdFor.inSeconds} 秒。'
                : '麦克风打不开（可能别的 App 在用）。按住下面的按钮 ${CallScreen.holdFor.inSeconds} 秒也行。',
          ]),
        );
      case CallPhase.granted:
        return Column(
          children: [
            Align(alignment: Alignment.centerLeft, child: CallCaptions(lines: [CallScript.plain(_grantedLine)])),
            const SizedBox(height: 10),
            BarkMeter(heard: _heard, listening: false, note: _note),
          ],
        );
      case CallPhase.declined:
        return LockedCard(title: '今天锁死了', body: '你拒接了狗版自己的电话。\n$_what明天 0 点才能再玩。');
      case CallPhase.locked:
        return LockedCard(title: '今天锁死了', body: '你今天拒接过狗版自己的电话。\n$_what明天 0 点才能再玩。');
    }
  }

  /// 爪印下面那行：刚才那声判成了什么、像狗多少（像狗指数）。
  /// 试一下来电时多写一行分类器给的分数，方便在真机上看判得准不准
  String? get _note {
    final sound = _last;
    if (sound == null) return null;
    final dog = sound.dogPercent;
    final text = switch (sound.heard) {
      Heard.bark => dog == null ? '听到一声' : '这声像狗 $dog%',
      Heard.tooQuiet => '太小声，没算',
      Heard.clap => '拍手、敲东西不算',
      Heard.notVoice => '不像叫出来的，没算',
      Heard.tooLong => '太长了，没算',
    };
    if (!call.preview) return text;
    final s = sound.scores;
    String pct(double v) => '${(v * 100).round()}%';
    return s == null
        ? '$text\n（分类器没给结果，只按音量算）'
        : '$text\n狗叫 ${pct(s.dog)} · 人声 ${pct(s.voice)} · 拍打 ${pct(s.clap)} · 吹气 ${pct(s.breath)}';
  }

  /// 标题下面的小标签
  static Widget _pill(String text) => Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(color: CallColors.glass, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
      );

  Widget _bottom() {
    const snooze = LockService.snoozeMinutes;
    const hangUpSize = 64.0;
    Widget hangUp() => CallButton(
          icon: Icons.call_end,
          label: '挂断',
          color: CallColors.decline,
          size: hangUpSize,
          semanticsLabel: '挂断，不玩了',
          onTap: _hangUp,
        );
    switch (_phase) {
      case CallPhase.ringing:
        return Column(
          children: [
            CallHint(icon: Icons.lock_outline, text: '拒接 = $_what今天锁死，明天 0 点再来'),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallButton(
                  icon: Icons.call_end,
                  label: '拒接',
                  color: CallColors.decline,
                  semanticsLabel: '拒接，今天锁死',
                  onTap: _decline,
                ),
                AcceptCallButton(onTap: _answer),
              ],
            ),
          ],
        );
      case CallPhase.talking:
        return Column(
          children: [
            CallControls(children: [
              CallButton(
                icon: _speaker ? Icons.volume_up : Icons.volume_off,
                label: '扬声器',
                color: _speaker ? Colors.white : CallColors.glass,
                iconColor: _speaker ? Pop.ink : Colors.white,
                size: hangUpSize,
                semanticsLabel: _speaker ? '扬声器开着' : '扬声器关了',
                onTap: _toggleSpeaker,
              ),
              CallButton(
                icon: Icons.pets,
                label: '学狗叫',
                color: Pop.yellow,
                iconColor: Pop.ink,
                size: hangUpSize,
                semanticsLabel: '学两声狗叫，再玩 $snooze 分钟',
                onTap: _startBark,
              ),
              hangUp(),
            ]),
            const SizedBox(height: 10),
            const Text('学会两声狗叫，再玩 $snooze 分钟；挂断就是不玩了',
                style: TextStyle(fontSize: 12.5, color: CallColors.faint)),
          ],
        );
      case CallPhase.listening:
        return CallControls(children: [hangUp()]);
      case CallPhase.missed:
        return CallControls(children: [
          CallButton(
            icon: Icons.replay,
            label: '再学一次',
            color: Pop.yellow,
            iconColor: Pop.ink,
            size: hangUpSize,
            onTap: _startBark,
          ),
          hangUp(),
        ]);
      case CallPhase.noMic:
        final seconds = CallScreen.holdFor.inSeconds;
        final progress = _heldMs / CallScreen.holdFor.inMilliseconds;
        return Column(
          children: [
            HoldToConfirm(
              label: _heldMs > 0 ? '按住别松… ${((1 - progress) * seconds).ceil()}' : '按住 $seconds 秒，再玩 $snooze 分钟',
              progress: progress,
              onDown: _holdDown,
              onUp: _holdUp,
            ),
            const SizedBox(height: 14),
            CallControls(children: [
              if (_micDenied)
                CallButton(
                  icon: Icons.settings,
                  label: '去设置',
                  color: CallColors.glass,
                  size: hangUpSize,
                  semanticsLabel: '去设置打开麦克风',
                  onTap: backend.openSettings,
                ),
              hangUp(),
            ]),
          ],
        );
      case CallPhase.granted || CallPhase.ended:
        // 占着位置，字和形象不会跳
        return const SizedBox(height: 64);
      case CallPhase.declined || CallPhase.locked:
        return PopButton(label: '好', onPressed: () => _close(false));
    }
  }
}

/// 弹出来电界面（iOS 的 CallGate、“试一下来电”）：像来电一样从屏幕里浮出来。返回放行了没有
Future<bool?> showCallScreen(BuildContext context, IncomingCall call, {CallBackend backend = const PlatformCallBackend()}) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<bool>(
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => CallScreen(call: call, backend: backend),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(curved), child: child),
      );
    },
  ));
}

/// 安卓超时来电页的整个 App：CallReminderActivity 单独的 Flutter 引擎里只跑这一页
class CallApp extends StatelessWidget {
  const CallApp({super.key, required this.call, this.backend = const PlatformCallBackend()});

  final IncomingCall call;
  final CallBackend backend;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '再玩我是狗',
      debugShowCheckedModeBanner: false,
      theme: Pop.theme(),
      home: CallScreen(call: call, backend: backend, onClose: (granted) => backend.close(granted: granted)),
    );
  }
}
