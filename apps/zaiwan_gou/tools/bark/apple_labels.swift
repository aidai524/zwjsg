// 导出 iOS 系统自带的声音分类器（SoundAnalysis 的 .version1，iPhone 和 Mac 上是同一个）的全部类别名，一行一个。
// 在 apps/zaiwan_gou 下运行：swift tools/bark/apple_labels.swift > test/fixtures/apple_sound_labels.txt
import SoundAnalysis

let request = try! SNClassifySoundRequest(classifierIdentifier: .version1)
for name in request.knownClassifications.sorted() {
  print(name)
}
