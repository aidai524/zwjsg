import AVFoundation
import CoreML
import Flutter
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import Vision

/// 拍照形象（iOS）：Vision 找 5 个点 → 按 DCT-Net 官方模板对齐成 288x288 → Core ML 卡通化 → Vision 抠出人像。
/// 平涂墨线贴纸和变狗图层在 Flutter 里画（packages/avatar_engine 的 PhotoSticker、PhotoDogAvatar），两端共用。
/// 照片只在内存里处理，不存盘、不上传。
/// 模型：DCT-Net 日漫头像（阿里达摩院，Apache 2.0），由 TF 冻结图转成 Core ML，见 ios/Runner/Models/。
///
/// 通道 `zwjsg/cartoon`（和安卓的 CartoonPlugin.kt 一样）：`camera` 拍自拍、`library` 从相册选，
/// 只回传卡通图和人像蒙版（`cartoonRgba`、`mask`，都是 288x288，第一行在最上面）和找到几张脸（`faces`），
/// 照片本身不出原生层。没拍、没选就关了回 null。
/// 名字里的 Lab 是技术验证时起的。验证页、样图和调试用的自动跑一遍 2026-11-27 都删了，这里只剩形象创建用的。
final class CartoonLabPlugin: NSObject, FlutterPlugin, PHPickerViewControllerDelegate,
  UIImagePickerControllerDelegate, UINavigationControllerDelegate
{
  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = CartoonLabPlugin()
    registrar.addMethodCallDelegate(
      plugin, channel: FlutterMethodChannel(name: "zwjsg/cartoon", binaryMessenger: registrar.messenger()))
  }

  private struct LabError: Error {
    let message: String
  }

  private static let size = 288

  /// 官方 96x112 模板（各加 1），x 再加 8 补成 112x112 正方形，按 ratio 0.75 缩，再放大到 288
  private static let target: [CGPoint] = {
    let template: [(CGFloat, CGFloat)] = [
      (30.29459953, 51.69630051), (65.53179932, 51.50139999), (48.02519989, 71.73660278),
      (33.54930115, 92.3655014), (62.72990036, 92.20410156),
    ]
    let scale = CGFloat(size) / 112
    return template.map { p in
      CGPoint(x: ((p.0 + 9 - 56) * 0.75 + 56) * scale, y: ((p.1 + 1 - 56) * 0.75 + 56) * scale)
    }
  }()

  /// 照片从哪来：选图器给的是文件数据，相机给的是内存里的图
  private enum Photo {
    case data(Data)
    case image(UIImage)
  }

  /// 等用户拍照或选图时，先把 Flutter 的回调存着
  private var pending: FlutterResult?
  private var model: MLModel?
  private let queue = DispatchQueue(label: "cartoon", qos: .userInitiated)

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "camera":
      openCamera(result)
    case "library":
      openLibrary(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 选图、拍照

  /// 系统选图器不需要相册权限，App 只拿到用户选的那一张
  private func openLibrary(_ result: @escaping FlutterResult) {
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    show(picker, result, failMessage: "打不开相册")
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let result = takePending() else { return }
    let type = UTType.image.identifier
    guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier(type) else {
      return result(nil) // 没选就关了
    }
    // 只读进内存，不让系统先拷一份文件
    provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
      DispatchQueue.main.async {
        guard let data else {
          return result(FlutterError(code: "load_failed", message: "照片没读出来", details: nil))
        }
        self.process(.data(data), result)
      }
    }
  }

  private static let cameraDenied = "没有相机权限：去系统设置里允许“再玩我是狗”使用相机，或者从相册选一张"

  /// 系统相机拍一张，优先用前置摄像头。拍到的照片只在内存里，不存进相册
  private func openCamera(_ result: @escaping FlutterResult) {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      return result(FlutterError(code: "no_camera", message: "这台设备用不了相机，从相册选一张吧", details: nil))
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      presentCamera(result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          if granted {
            self.presentCamera(result)
          } else {
            result(FlutterError(code: "camera_denied", message: Self.cameraDenied, details: nil))
          }
        }
      }
    default:
      result(FlutterError(code: "camera_denied", message: Self.cameraDenied, details: nil))
    }
  }

  private func presentCamera(_ result: @escaping FlutterResult) {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
    // 全屏打开：半屏的话用户下滑关掉时系统不回调，Flutter 那边会一直等
    picker.modalPresentationStyle = .fullScreen
    picker.delegate = self
    show(picker, result, failMessage: "打不开相机")
  }

  func imagePickerController(
    _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    guard let result = takePending() else { return }
    guard let image = info[.originalImage] as? UIImage else {
      return result(FlutterError(code: "load_failed", message: "照片没拍下来，再试一次", details: nil))
    }
    process(.image(image), result)
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    takePending()?(nil) // 没拍就关了
  }

  /// 取出等着的回调（只能取一次）
  @discardableResult
  private func takePending() -> FlutterResult? {
    defer { pending = nil }
    return pending
  }

  private func show(_ controller: UIViewController, _ result: @escaping FlutterResult, failMessage: String) {
    guard pending == nil else {
      return result(FlutterError(code: "busy", message: "上一张还没处理完", details: nil))
    }
    guard let top = Self.topViewController() else {
      return result(FlutterError(code: "no_window", message: failMessage, details: nil))
    }
    pending = result
    top.present(controller, animated: true)
  }

  private func process(_ photo: Photo, _ result: @escaping FlutterResult) {
    queue.async {
      do {
        let out = try self.run(photo)
        let encoded: [String: Any] = [
          "cartoonRgba": FlutterStandardTypedData(bytes: out.cartoon),
          "mask": FlutterStandardTypedData(bytes: out.mask),
          "faces": out.faces,
        ]
        DispatchQueue.main.async { result(encoded) }
      } catch let error as LabError {
        DispatchQueue.main.async { result(FlutterError(code: "lab_failed", message: error.message, details: nil)) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "lab_failed", message: "出错了：\(error.localizedDescription)", details: nil))
        }
      }
    }
  }

  // MARK: - 流程

  /// 卡通图 RGBA、人像蒙版（每像素 1 字节，255 是人），都是 288x288，第一行在最上面；照片里有几张脸
  private func run(_ source: Photo) throws -> (cartoon: Data, mask: Data, faces: Int) {
    let photo = try Self.decode(source)
    let (points, faces) = try Self.fivePoints(photo)
    let aligned = try Self.warp(photo, Self.similarity(points, Self.target))

    if model == nil {
      guard let url = Bundle.main.url(forResource: "DCTNetAnimeHead", withExtension: "mlmodelc") else {
        throw LabError(message: "模型不在包里")
      }
      let config = MLModelConfiguration()
      config.computeUnits = .all
      model = try MLModel(contentsOf: url, configuration: config)
    }
    guard let model,
          let inputName = model.modelDescription.inputDescriptionsByName.keys.first,
          let outputName = model.modelDescription.outputDescriptionsByName.keys.first
    else { throw LabError(message: "模型读不出来") }

    let input = try MLDictionaryFeatureProvider(
      dictionary: [inputName: MLFeatureValue(multiArray: Self.inputArray(aligned.bytes))])
    let output = try model.prediction(from: input)
    guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
      throw LabError(message: "模型没给出结果")
    }
    let cartoon = try Self.rgba(from: array)
    // 抠出人像（在对齐后的照片上抠，和卡通图逐像素对得上），给“平涂墨线贴纸”用
    let mask = try Self.personMask(aligned.image)
    return (Data(cartoon), Data(mask), faces)
  }

  /// 在内存里解码并转正，最长边缩到 1280 以内
  private static func decode(_ photo: Photo) throws -> CGImage {
    switch photo {
    case .data(let data): return try decode(data)
    case .image(let image): return try upright(image)
    }
  }

  /// 相机拍的图：按拍摄方向画正，最长边缩到 1280 以内
  private static func upright(_ image: UIImage) throws -> CGImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > 0 else { throw LabError(message: "照片读不出来") }
    let scale = min(1, 1280 / longest)
    let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let cg = drawn.cgImage else { throw LabError(message: "照片读不出来") }
    return cg
  }

  /// 在内存里解码并按 EXIF 转正，最长边缩到 1280 以内（4800 万像素的原图也不用整张解开）
  private static func decode(_ data: Data) throws -> CGImage {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: 1280,
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw LabError(message: "照片读不出来") }
    return image
  }

  /// 5 个点：左眼、右眼（按图上左右）、鼻尖、左嘴角、右嘴角；像素坐标，原点在左上角。人多时取最大的脸
  private static func fivePoints(_ image: CGImage) throws -> ([CGPoint], Int) {
    let request = VNDetectFaceLandmarksRequest()
    try VNImageRequestHandler(cgImage: image).perform([request])
    let results = request.results ?? []
    guard let face = results.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
          let lm = face.landmarks
    else { throw LabError(message: "没找到人脸，换一张正脸、光线亮一点的照片") }
    let size = CGSize(width: image.width, height: image.height)
    func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
      (region?.pointsInImage(imageSize: size) ?? []).map { CGPoint(x: $0.x, y: size.height - $0.y) }
    }
    func center(_ p: [CGPoint]) -> CGPoint? {
      guard !p.isEmpty else { return nil }
      let n = CGFloat(p.count)
      return CGPoint(x: p.map(\.x).reduce(0, +) / n, y: p.map(\.y).reduce(0, +) / n)
    }
    let lips = points(lm.outerLips)
    guard let eyeA = center(points(lm.leftPupil)) ?? center(points(lm.leftEye)),
          let eyeB = center(points(lm.rightPupil)) ?? center(points(lm.rightEye)),
          // 鼻尖用“鼻子”轮廓（鼻翼、鼻孔一圈 8 个点）的中心：实测比鼻梁线最下面的点更接近模型模板的鼻尖，
          // 鼻梁线的最低点会固定往一边偏 10 像素左右（288 头像里）
          let nose = center(points(lm.nose)) ?? points(lm.noseCrest).max(by: { $0.y < $1.y }),
          let mouthLeft = lips.min(by: { $0.x < $1.x }),
          let mouthRight = lips.max(by: { $0.x < $1.x })
    else { throw LabError(message: "五官没找全，换一张正脸照片") }
    let eyes = [eyeA, eyeB].sorted { $0.x < $1.x }
    return ([eyes[0], eyes[1], nose, mouthLeft, mouthRight], results.count)
  }

  /// 最小二乘相似变换（旋转 + 等比缩放 + 平移，不镜像）：src → dst
  private static func similarity(_ src: [CGPoint], _ dst: [CGPoint]) -> CGAffineTransform {
    let n = CGFloat(src.count)
    let sm = CGPoint(x: src.map(\.x).reduce(0, +) / n, y: src.map(\.y).reduce(0, +) / n)
    let dm = CGPoint(x: dst.map(\.x).reduce(0, +) / n, y: dst.map(\.y).reduce(0, +) / n)
    var dot: CGFloat = 0, cross: CGFloat = 0, norm: CGFloat = 0
    for (s, d) in zip(src, dst) {
      let sx = s.x - sm.x, sy = s.y - sm.y, dx = d.x - dm.x, dy = d.y - dm.y
      dot += sx * dx + sy * dy
      cross += sx * dy - sy * dx
      norm += sx * sx + sy * sy
    }
    let a = dot / norm, b = cross / norm
    // (x, y) → (a·x − b·y + tx, b·x + a·y + ty)
    return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: dm.x - (a * sm.x - b * sm.y), ty: dm.y - (b * sm.x + a * sm.y))
  }

  /// 按变换把原图画进 288x288，图外的地方填白（和官方一样）；返回图和 RGBA 字节（第一行是最上面）
  private static func warp(_ image: CGImage, _ m: CGAffineTransform) throws -> (image: CGImage, bytes: [UInt8]) {
    var bytes = [UInt8](repeating: 255, count: size * size * 4)
    let drawn: Bool = bytes.withUnsafeMutableBytes { buf in
      guard let ctx = CGContext(
        data: buf.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.interpolationQuality = .high
      // 从后往前看：原图按左上角原点画 → 映射到 288 头像的坐标 → 换回 CG 左下角原点
      ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(size)))
      ctx.concatenate(m)
      ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(image.height)))
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    guard drawn, let cg = cgImage(rgba: bytes) else { throw LabError(message: "对齐失败") }
    return (cg, bytes)
  }

  /// 模型要 [288, 288, 3]、BGR、0–255 的浮点
  private static func inputArray(_ rgba: [UInt8]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [NSNumber(value: size), NSNumber(value: size), 3], dataType: .float32)
    let p = array.dataPointer.bindMemory(to: Float.self, capacity: size * size * 3)
    for i in 0..<(size * size) {
      p[i * 3] = Float(rgba[i * 4 + 2])
      p[i * 3 + 1] = Float(rgba[i * 4 + 1])
      p[i * 3 + 2] = Float(rgba[i * 4])
    }
    return array
  }

  /// 模型输出 [288, 288, 3]、BGR、0–255 → 不透明的 RGBA 字节（第一行是最上面）
  private static func rgba(from array: MLMultiArray) throws -> [UInt8] {
    let values = MLShapedArray<Float>(converting: array).scalars
    guard values.count == size * size * 3 else { throw LabError(message: "模型结果尺寸不对") }
    var rgba = [UInt8](repeating: 255, count: size * size * 4)
    for i in 0..<(size * size) {
      rgba[i * 4] = UInt8(max(0, min(255, values[i * 3 + 2])))
      rgba[i * 4 + 1] = UInt8(max(0, min(255, values[i * 3 + 1])))
      rgba[i * 4 + 2] = UInt8(max(0, min(255, values[i * 3])))
    }
    return rgba
  }

  /// 苹果 Vision 的人像分割（iOS 15+），缩成 288x288、每像素 1 字节（255 是人）。
  /// 系统给的蒙版是固定的 2016x1512，按面积平均缩回 288x288，边缘不会有锯齿
  private static func personMask(_ image: CGImage) throws -> [UInt8] {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    try VNImageRequestHandler(cgImage: image).perform([request])
    guard let buffer = request.results?.first?.pixelBuffer else { throw LabError(message: "抠图失败，换一张试试") }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw LabError(message: "抠图失败，换一张试试") }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let src = base.assumingMemoryBound(to: UInt8.self)
    var out = [UInt8](repeating: 0, count: size * size)
    for y in 0..<size {
      let y0 = y * height / size, y1 = max(y0 + 1, (y + 1) * height / size)
      for x in 0..<size {
        let x0 = x * width / size, x1 = max(x0 + 1, (x + 1) * width / size)
        var sum = 0
        for sy in y0..<y1 {
          let row = src + sy * rowBytes
          for sx in x0..<x1 { sum += Int(row[sx]) }
        }
        out[y * size + x] = UInt8(sum / ((y1 - y0) * (x1 - x0)))
      }
    }
    return out
  }

  /// 不透明的 RGBA 字节 → 图片（拷一份数据，不和缓冲区共用内存）
  private static func cgImage(rgba: [UInt8]) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
    return CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
