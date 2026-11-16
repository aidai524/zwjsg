// 用苹果 Vision 找人脸的 5 个点：左眼、右眼（按图上的左右）、鼻尖、左嘴角、右嘴角。
// 输出 JSON，像素坐标，原点在左上角。手机上会用同样的办法定位，替代 DCT-Net 自带的人脸检测和关键点模型。
import Foundation
import ImageIO
import Vision

let path = CommandLine.arguments[1]
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  print(#"{"error":"读不了图片"}"#)
  exit(1)
}
let size = CGSize(width: image.width, height: image.height)
let request = VNDetectFaceLandmarksRequest()
try VNImageRequestHandler(cgImage: image).perform([request])
guard let face = (request.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }),
      let lm = face.landmarks
else {
  print(#"{"error":"没找到人脸"}"#)
  exit(2)
}

/// Vision 的原点在左下角，翻成左上角
func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
  (region?.pointsInImage(imageSize: size) ?? []).map { CGPoint(x: $0.x, y: size.height - $0.y) }
}

func center(_ p: [CGPoint]) -> CGPoint {
  CGPoint(x: p.map(\.x).reduce(0, +) / CGFloat(p.count), y: p.map(\.y).reduce(0, +) / CGFloat(p.count))
}

let eyeA = points(lm.leftPupil).isEmpty ? center(points(lm.leftEye)) : center(points(lm.leftPupil))
let eyeB = points(lm.rightPupil).isEmpty ? center(points(lm.rightEye)) : center(points(lm.rightPupil))
let eyes = [eyeA, eyeB].sorted { $0.x < $1.x }
// 鼻尖用“鼻子”轮廓的中心（比鼻梁线最下面的点更接近模板的鼻尖，见 nose_candidates.swift 的对比）
let nose = points(lm.nose).isEmpty ? points(lm.noseCrest).max(by: { $0.y < $1.y })! : center(points(lm.nose))
let lips = points(lm.outerLips)
let mouthLeft = lips.min(by: { $0.x < $1.x })!
let mouthRight = lips.max(by: { $0.x < $1.x })!

let box = face.boundingBox
let result: [String: Any] = [
  "points": [eyes[0], eyes[1], nose, mouthLeft, mouthRight].map { [Double($0.x), Double($0.y)] },
  "faceBox": [Double(box.minX * size.width), Double((1 - box.maxY) * size.height),
              Double(box.width * size.width), Double(box.height * size.height)],
  "faces": request.results?.count ?? 0,
]
print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
