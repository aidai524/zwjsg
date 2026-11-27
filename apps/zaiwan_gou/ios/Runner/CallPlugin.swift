import AVFoundation
import AudioToolbox
import DeviceActivity
import Flutter
import SoundAnalysis
import UIKit
import UserNotifications

/// 超时来电界面（Flutter 的 lib/features/call/call_screen.dart）要的原生能力（2026-11-23）：
/// 有没有来电、响铃和震动、接通和挂断的提示音、狗版的你说话、听狗叫、放行和拒接。
/// - 响铃跟系统来电一样：静音模式下不出声、只震动；接通以后的声音（提示音、狗版的你说话）静音模式下也放，像通话里的声音
/// - 听狗叫：每 20 毫秒一个音量（dBFS），加上系统自带的声音分类器（SoundAnalysis）每 0.25 秒的判断，交给 Flutter；
///   是不是两声狗叫由 lib/core/bark_detector.dart 判断。声音只在手机内存里过一下，不录音、不保存、不上传
/// - 狗版的你说的话是打包在 App 里的语音（提前用 MiniMax 合成、加好电话音效，lib/features/call/call_voice.dart）；
///   放不了时才用系统语音在手机上念，念的话里不带 App 名称
final class CallPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = CallPlugin()
    let channel = FlutterMethodChannel(name: "zwjsg/call", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    FlutterEventChannel(name: "zwjsg/bark_sounds", binaryMessenger: registrar.messenger()).setStreamHandler(plugin)
    DispatchQueue.global(qos: .utility).async { installRingSound() }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pending":
      result(pendingPayload())
    case "ring":
      ring()
      result(nil)
    case "stopRing":
      stopRing()
      result(nil)
    case "tone":
      tone(args["name"] as? String)
      result(nil)
    case "playVoice":
      result(playVoice(args["asset"] as? String))
    case "speak":
      speak(args["text"] as? String)
      result(nil)
    case "stopSpeaking":
      stopSpeaking()
      result(nil)
    case "startListening":
      startListening(result)
    case "stopListening":
      stopListening()
      result(nil)
    case "grant":
      result(grant(args["lockId"] as? String))
    case "decline":
      decline(args["lockId"] as? String)
      result(nil)
    case "hangUp":
      // 接了又挂了：不放行也不锁死，屏蔽页还在，下次打开那个 App 还是来电
      ScreenTimeStore.clearCall()
      CallNotice.cancel()
      result(nil)
    case "close":
      // 页面由 Flutter 关：停掉声音，把声音还给别的 App（音乐不再被压低）
      stopRing()
      stopSpeaking()
      stopListening()
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      result(nil)
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
      result(nil)
    case "previewNotice":
      previewNotice(args, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 来电

  /// 正在打来的电话；没有真的来电时，看有没有“试一下来电通知”的那一通
  private func pendingPayload() -> [String: Any]? {
    if let real = realPendingPayload() { return real }
    guard var preview = ScreenTimeStore.takePreviewCall() else { return nil }
    preview["preview"] = true
    return preview
  }

  /// 真的来电。限时删了、已经放行、今天拒接过的都不算
  private func realPendingPayload() -> [String: Any]? {
    guard let call = ScreenTimeStore.pendingCall, let lock = ScreenTimeStore.lock(call.id),
      ScreenTimeStore.isLockedToday(call.id), !ScreenTimeStore.isGraceActive(call.id),
      !ScreenTimeStore.isDeclinedToday(call.id)
    else { return nil }
    let s = LockShield.selection(of: lock)
    var payload: [String: Any] = [
      "lockId": lock.id,
      "limitMinutes": lock.minutes,
      "apps": s?.applicationTokens.count ?? 0,
      "categories": s?.categoryTokens.count ?? 0,
      "webDomains": s?.webDomainTokens.count ?? 0,
      "stage": ScreenTimeStore.stageToday,
      "answered": call.answered,
    ]
    if let pct = lock.dogPercent { payload["dogPercent"] = pct }
    return payload
  }

  /// 学会两声狗叫：放行，再用满 10 分钟监控扩展又会挡上、再打来
  private func grant(_ id: String?) -> Bool {
    guard let id, let lock = ScreenTimeStore.lock(id), !ScreenTimeStore.isDeclinedToday(id) else { return false }
    LockShield.snooze(lock)
    ScreenTimeStore.clearCall()
    CallNotice.cancel()
    return true
  }

  /// 拒接：今天锁死，屏蔽页换成“今天锁死了”，明天 0 点由监控扩展解开
  private func decline(_ id: String?) {
    guard let id, let lock = ScreenTimeStore.lock(id) else { return }
    ScreenTimeStore.setDeclinedToday(id)
    ScreenTimeStore.clearCall()
    CallNotice.cancel()
    DeviceActivityCenter().stopMonitoring([ScreenTimeStore.graceActivity(id)])
    ScreenTimeStore.setGraceActive(id, false)
    LockShield.apply(lock)
    ScreenTimeStore.append("限时 \(id.prefix(4))：拒接，今天锁死")
  }

  /// “试一下来电通知”：过几秒响一条和真的一样的来电通知（铃声也一样），点通知回到 App 就是这通试一下的来电，不锁也不放行。
  /// App 开着的时候系统不弹，所以要先回到桌面或者锁屏
  private func previewNotice(_ args: [String: Any], _ result: @escaping FlutterResult) {
    // Flutter 交过来的来电没有空值，能直接存进 UserDefaults；保险起见再滤一遍
    let call = (args["call"] as? [String: Any] ?? [:]).filter { !($0.value is NSNull) }
    let minutes = call["limitMinutes"] as? Int ?? 60
    let reason = (call["dogPercent"] as? Int).map { "今天狗度到 \($0)% 了" }
      ?? "说好一天 \(ScreenTimeStore.formatMinutes(minutes))，时间到了"
    let delay = max((args["delaySeconds"] as? NSNumber)?.doubleValue ?? 8, 1)
    let center = UNUserNotificationCenter.current()
    func reply(_ value: String) { DispatchQueue.main.async { result(value) } }
    func schedule(soundOn: Bool) {
      ScreenTimeStore.recordPreviewCall(call, ringsAt: Date().addingTimeInterval(delay))
      CallNotice.ring(reason: reason, after: delay, preview: true) { error in
        reply(error != nil ? "failed" : (soundOn ? "scheduled" : "noSound"))
      }
    }
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .notDetermined:
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          if granted { schedule(soundOn: true) } else { reply("denied") }
        }
      case .denied:
        reply("denied")
      default:
        schedule(soundOn: settings.soundSetting != .disabled)
      }
    }
  }

  // MARK: - 响铃、提示音、说话

  private var ringing = false
  private var ringPlayer: AVAudioPlayer?
  private var buzzTimer: Timer?
  private var tonePlayer: AVAudioPlayer?
  private let speech = AVSpeechSynthesizer()
  private var voicePlayer: AVAudioPlayer?

  /// Flutter 资源在 App 包里的位置（assets/sounds/）
  fileprivate static func assetURL(_ name: String) -> URL? {
    let key = FlutterDartProject.lookupKey(forAsset: "assets/sounds/\(name)")
    return Bundle.main.path(forResource: key, ofType: nil).map { URL(fileURLWithPath: $0) }
  }

  private func activate(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode = .default,
                        options: AVAudioSession.CategoryOptions = []) {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(category, mode: mode, options: options)
    try? session.setActive(true)
  }

  /// 原创铃声（2.4 秒一句）一直循环，每句开头震一下
  private func ring() {
    guard !ringing else { return }
    ringing = true
    stopListening()
    activate(.soloAmbient)
    if let url = Self.assetURL("ring.caf"), let player = try? AVAudioPlayer(contentsOf: url) {
      player.numberOfLoops = -1
      player.play()
      ringPlayer = player
    }
    buzz()
    buzzTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in self?.buzz() }
  }

  /// 连着震两下，像来电那样长长的一下
  private func buzz() {
    AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate) {
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
  }

  private func stopRing() {
    ringing = false
    buzzTimer?.invalidate()
    buzzTimer = nil
    ringPlayer?.stop()
    ringPlayer = nil
  }

  private func tone(_ name: String?) {
    guard let name, let url = Self.assetURL("\(name).wav") else { return }
    activate(.playback, options: [.duckOthers])
    tonePlayer = try? AVAudioPlayer(contentsOf: url)
    tonePlayer?.play()
  }

  /// 放一句打包好的语音（Flutter 资源路径），返回时长（毫秒）；找不到、放不了返回 nil，Flutter 改用系统语音念。
  /// 跟系统语音一样，静音模式下也放（像通话里的声音），别的 App 的声音先压低
  private func playVoice(_ asset: String?) -> Int? {
    guard let asset else { return nil }
    stopSpeaking()
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil),
      let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    else { return nil }
    activate(.playback, mode: .spokenAudio, options: [.duckOthers])
    guard player.play() else { return nil }
    voicePlayer = player
    return Int(player.duration * 1000)
  }

  private func speak(_ text: String?) {
    guard let text, !text.isEmpty else { return }
    stopSpeaking()
    activate(.playback, mode: .spokenAudio, options: [.duckOthers])
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    utterance.pitchMultiplier = 1.15
    speech.speak(utterance)
  }

  private func stopSpeaking() {
    if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
    voicePlayer?.stop()
    voicePlayer = nil
  }

  // MARK: - 听狗叫

  private let audioEngine = AVAudioEngine()
  private var listening = false
  private var soundSink: FlutterEventSink?
  /// 不满 20 毫秒的那一截，留到下一块一起算（只在音频线程用）
  private var pendingSum: Float = 0
  private var pendingCount = 0
  /// 系统自带的声音分类器（iOS 15 起有，303 类，不联网）：每 0.25 秒判断一次最近 1 秒的声音
  private var analyzer: SNAudioStreamAnalyzer?
  private var soundObserver: SoundObserver?
  private let analysisQueue = DispatchQueue(label: "com.zwjsg.bark.analysis")
  /// 每次开始听、叫停都加 1：等权限时已经叫停了、上一次晚到的音量和分类结果，对不上就不要
  private var listenTicket = 0

  /// 'listening'（音量 + 声音分类）/ 'levels'（分类器开不了，只有音量）/ 'denied' / 'failed'
  private func startListening(_ result: @escaping FlutterResult) {
    stopRing()
    stopSpeaking()
    stopListening()
    let ticket = listenTicket
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async {
        guard granted else { return result("denied") }
        // 等权限的时候 Flutter 已经叫停了（挂断、切走）
        guard ticket == self.listenTicket else { return result("failed") }
        do {
          result(try self.startAudio() ? "listening" : "levels")
        } catch {
          self.stopListening()
          result("failed")
        }
      }
    }
  }

  /// 开麦克风；声音分类器也开起来了返回 true
  private func startAudio() throws -> Bool {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement)
    try session.setActive(true)
    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    let step = max(Int(format.sampleRate / 50), 1)
    pendingSum = 0
    pendingCount = 0
    let ticket = listenTicket
    let analyzer = makeAnalyzer(format: format, ticket: ticket)
    self.analyzer = analyzer
    // 从开始听算起第几个采样：分类结果的时间跟音量对得上
    var position: AVAudioFramePosition = 0
    input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(step), format: format) { [weak self] buffer, _ in
      guard let self, let samples = buffer.floatChannelData?[0] else { return }
      var levels: [Double] = []
      for i in 0..<Int(buffer.frameLength) {
        self.pendingSum += samples[i] * samples[i]
        self.pendingCount += 1
        if self.pendingCount == step {
          let rms = sqrt(self.pendingSum / Float(step))
          levels.append(20 * log10(max(Double(rms), 1e-5)))
          self.pendingSum = 0
          self.pendingCount = 0
        }
      }
      if let analyzer {
        // 分类器比较费时，放到别的队列，别卡住录音线程
        let at = position
        self.analysisQueue.async { analyzer.analyze(buffer, atAudioFramePosition: at) }
      }
      position += AVAudioFramePosition(buffer.frameLength)
      if levels.isEmpty { return }
      DispatchQueue.main.async {
        if ticket == self.listenTicket { self.soundSink?(levels) }
      }
    }
    listening = true
    audioEngine.prepare()
    try audioEngine.start()
    return analyzer != nil
  }

  /// 1 秒一窗、每 0.25 秒一次（窗口重叠 75%）。开不了（极少见）返回 nil，Flutter 那边只按音量算
  private func makeAnalyzer(format: AVAudioFormat, ticket: Int) -> SNAudioStreamAnalyzer? {
    do {
      let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
      request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 48_000)
      request.overlapFactor = 0.75
      let analyzer = SNAudioStreamAnalyzer(format: format)
      let observer = SoundObserver { [weak self] window in
        DispatchQueue.main.async {
          guard let self, ticket == self.listenTicket else { return }
          self.soundSink?(window)
        }
      }
      try analyzer.add(request, withObserver: observer)
      soundObserver = observer
      return analyzer
    } catch {
      ScreenTimeStore.append("声音分类器开不了：\(error.localizedDescription)")
      return nil
    }
  }

  private func stopListening() {
    listenTicket += 1
    guard listening else { return }
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    let analyzer = self.analyzer
    analysisQueue.async { analyzer?.removeAllRequests() }
    self.analyzer = nil
    soundObserver = nil
    // 不通知别的 App：狗版的你插完话还要接着听，别让音乐在中间响起来；整个来电关掉时（close）才通知
    try? AVAudioSession.sharedInstance().setActive(false)
    listening = false
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    soundSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    soundSink = nil
    stopListening()
    return nil
  }

  // MARK: - 通知铃声

  /// 换了铃声就加 1，手机上那份会重新拷一遍
  private static let ringSoundVersion = 1

  /// 铃声拷到 App Group 的 Library/Sounds：监控扩展发的来电通知也用这个铃声
  private static func installRingSound() {
    guard let defaults = ScreenTimeStore.defaults,
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ScreenTimeStore.appGroup),
      let source = assetURL("ring.caf")
    else { return }
    let dir = container.appendingPathComponent("Library/Sounds", isDirectory: true)
    let target = dir.appendingPathComponent(ScreenTimeStore.ringSound)
    let fm = FileManager.default
    if defaults.integer(forKey: "ringSoundVersion") == ringSoundVersion, fm.fileExists(atPath: target.path) { return }
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
      try fm.copyItem(at: source, to: target)
      defaults.set(ringSoundVersion, forKey: "ringSoundVersion")
    } catch {
      ScreenTimeStore.append("来电铃声没装上：\(error.localizedDescription)")
    }
  }
}

/// 把系统声音分类器的结果交给 Flutter：{'end': 毫秒, 'length': 毫秒, 'labels': {类别名: 分数}}，
/// 只给分数到 0.02 的前 12 类；时间从开始听算起，跟音量同一条时间线。归成哪种声音由 lib/core/sound_labels.dart 定
private final class SoundObserver: NSObject, SNResultsObserving {
  private let send: ([String: Any]) -> Void

  init(_ send: @escaping ([String: Any]) -> Void) {
    self.send = send
  }

  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let result = result as? SNClassificationResult else { return }
    var labels: [String: Double] = [:]
    for item in result.classifications.sorted(by: { $0.confidence > $1.confidence }).prefix(12) where item.confidence >= 0.02 {
      labels[item.identifier] = item.confidence
    }
    let range = result.timeRange
    send([
      "end": Int((CMTimeRangeGetEnd(range).seconds * 1000).rounded()),
      "length": Int((range.duration.seconds * 1000).rounded()),
      "labels": labels,
    ])
  }
}
