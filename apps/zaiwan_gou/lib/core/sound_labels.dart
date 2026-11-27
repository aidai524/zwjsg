/// 听狗叫要分的几种声音。原生的声音分类器只管给每类声音打分，归成哪种由这里定（规则只在 Dart 这一份）。
enum SoundKind {
  /// 狗叫：真狗叫、学得特别像的人
  dog,

  /// 人声：说话、喊、叫、笑、唱……学狗叫的人多半落在这里，也算数
  voice,

  /// 手上的声音：拍手、打响指、敲桌子、拍东西
  clap,

  /// 不是叫出来的：吹气、吹口哨、喘粗气
  breath,
}

/// 两个平台的分类器各有自己的类别名，名字不重：
/// - iOS：系统自带的声音分类器（SoundAnalysis 的 SNClassifySoundRequest .version1，303 类，名字像 `dog_bark`），
///   全部类别见 test/fixtures/apple_sound_labels.txt（从 Mac 上导出来的，iPhone 上是同一个分类器）
/// - 安卓：Google 开源的 YAMNet（521 类，名字像 `Bark`），原生从 android/app/src/main/assets/yamnet_labels.txt 读
///
/// 没列出来的类别不算进任何一种（环境声、乐器、机器……）。测试会检查这里的每个名字在对应的类别表里都有
const soundKinds = <String, SoundKind>{
  // iOS · 狗
  'dog': SoundKind.dog,
  'dog_bark': SoundKind.dog,
  'dog_bow_wow': SoundKind.dog,
  'dog_growl': SoundKind.dog,
  'dog_howl': SoundKind.dog,
  'dog_whimper': SoundKind.dog,
  // iOS · 人声
  'speech': SoundKind.voice,
  'shout': SoundKind.voice,
  'yell': SoundKind.voice,
  'battle_cry': SoundKind.voice,
  'children_shouting': SoundKind.voice,
  'screaming': SoundKind.voice,
  'whispering': SoundKind.voice,
  'babble': SoundKind.voice,
  'laughter': SoundKind.voice,
  'baby_laughter': SoundKind.voice,
  'giggling': SoundKind.voice,
  'snicker': SoundKind.voice,
  'belly_laugh': SoundKind.voice,
  'chuckle_chortle': SoundKind.voice,
  'crying_sobbing': SoundKind.voice,
  'baby_crying': SoundKind.voice,
  'sigh': SoundKind.voice,
  'singing': SoundKind.voice,
  'choir_singing': SoundKind.voice,
  'yodeling': SoundKind.voice,
  'humming': SoundKind.voice,
  'rapping': SoundKind.voice,
  // iOS · 手上的声音
  'clapping': SoundKind.clap,
  'applause': SoundKind.clap,
  'finger_snapping': SoundKind.clap,
  'slap_smack': SoundKind.clap,
  'knock': SoundKind.clap,
  'tap': SoundKind.clap,
  'thump_thud': SoundKind.clap,
  // iOS · 不是叫出来的
  'breathing': SoundKind.breath,
  'whistling': SoundKind.breath,
  'nose_blowing': SoundKind.breath,
  'wind_noise_microphone': SoundKind.breath,

  // 安卓（YAMNet）· 狗
  'Dog': SoundKind.dog,
  'Bark': SoundKind.dog,
  'Yip': SoundKind.dog,
  'Howl': SoundKind.dog,
  'Bow-wow': SoundKind.dog,
  'Growling': SoundKind.dog,
  'Whimper (dog)': SoundKind.dog,
  // 安卓 · 人声
  'Speech': SoundKind.voice,
  'Child speech, kid speaking': SoundKind.voice,
  'Conversation': SoundKind.voice,
  'Narration, monologue': SoundKind.voice,
  'Babbling': SoundKind.voice,
  'Shout': SoundKind.voice,
  'Bellow': SoundKind.voice,
  'Whoop': SoundKind.voice,
  'Yell': SoundKind.voice,
  'Children shouting': SoundKind.voice,
  'Screaming': SoundKind.voice,
  'Whispering': SoundKind.voice,
  'Laughter': SoundKind.voice,
  'Baby laughter': SoundKind.voice,
  'Giggle': SoundKind.voice,
  'Snicker': SoundKind.voice,
  'Belly laugh': SoundKind.voice,
  'Chuckle, chortle': SoundKind.voice,
  'Crying, sobbing': SoundKind.voice,
  'Baby cry, infant cry': SoundKind.voice,
  'Whimper': SoundKind.voice,
  'Wail, moan': SoundKind.voice,
  'Sigh': SoundKind.voice,
  'Singing': SoundKind.voice,
  'Choir': SoundKind.voice,
  'Yodeling': SoundKind.voice,
  'Chant': SoundKind.voice,
  'Mantra': SoundKind.voice,
  'Child singing': SoundKind.voice,
  'Rapping': SoundKind.voice,
  'Humming': SoundKind.voice,
  'Groan': SoundKind.voice,
  'Grunt': SoundKind.voice,
  // 安卓 · 手上的声音
  'Hands': SoundKind.clap,
  'Clapping': SoundKind.clap,
  'Applause': SoundKind.clap,
  'Finger snapping': SoundKind.clap,
  'Slap, smack': SoundKind.clap,
  'Knock': SoundKind.clap,
  'Tap': SoundKind.clap,
  'Thump, thud': SoundKind.clap,
  // 安卓 · 不是叫出来的
  'Breathing': SoundKind.breath,
  'Whistling': SoundKind.breath,
  'Wind noise (microphone)': SoundKind.breath,
};
