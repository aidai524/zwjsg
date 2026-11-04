# 再玩我是狗（zwjsg）

手机刷得越多，你的卡通形象就越像一只狗；少刷一点，才能做回人。

| 目录 | 内容 | 技术 |
| --- | --- | --- |
| `app/` | 手机 App | Flutter（安卓原生部分 Kotlin，iOS 原生部分 Swift 待接入） |
| `api/` | 后端 API | Laravel 13 + Sanctum，MySQL / PostgreSQL，Redis |

产品需求、UI 设计见项目文档（需求文档、UI 设计画布）。

## 隐私约定（写代码时必须遵守）

- 原始照片只在手机内存里处理，**不落盘、不上传**；服务端只存卡通形象。
- 具体 app 名称只在安卓原生层用于计算，**不传给 Flutter，更不传给服务端**；服务端只接收每天的狗度、分钟数、犬种。
- 狗度规则在两处实现，改动时一起改：`app/lib/core/dog_meter.dart`、`api/config/dog.php` + `api/app/Services/DogMeter.php`。

---

## 后端：本地运行

需要 PHP 8.3+ 和 Composer。

```bash
cd api
composer install
cp .env.example .env
php artisan key:generate
touch database/database.sqlite      # 本地默认用 SQLite
php artisan migrate --seed
php artisan storage:link
php artisan serve --host=0.0.0.0 --port=8000
```

跑测试：

```bash
php artisan test
```

本地登录：调用 `POST /api/v1/auth/sms/send` 后，验证码会写进 `storage/logs/laravel.log`（开发环境不真的发短信）。

### 接口（前缀 `/api/v1`）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `auth/sms/send` | 发送验证码（同一手机号 1 分钟 1 次） |
| POST | `auth/sms/login` | 验证码登录，返回 token |
| POST | `auth/wechat/login` | 微信登录（待配置，现在返回 501） |
| POST | `auth/logout` | 退出 |
| GET | `me` | 当前用户 |
| PATCH | `me/settings` | 修改昵称、时区、每日目标、提醒时间 |
| DELETE | `me` | 注销并删除所有数据 |
| POST | `me/avatar` | 上传卡通形象（png/webp，≤1MB） |
| GET | `daily-records?from=&to=` | 历史记录 |
| PUT | `daily-records/{YYYY-MM-DD}` | 上报某天的狗度，返回新解锁的犬种 |
| GET | `breeds` | 图鉴（全部犬种 + 解锁情况） |

除登录接口外都需要 `Authorization: Bearer <token>`。

---

## App：本地运行

需要 Flutter 3.22+（Dart 3.4+）。仓库里只放了 `lib/`、测试和安卓原生代码，**第一次需要先生成平台工程**（已有的文件不会被覆盖）：

```bash
cd app
flutter create --org com.zwjsg --project-name zwjsg_app --platforms android,ios .
flutter pub get
flutter test
```

运行（安卓模拟器访问电脑本机的后端用 `10.0.2.2`）：

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1
```

真机调试时把 `API_BASE` 换成电脑的局域网 IP，例如 `http://192.168.1.10:8000/api/v1`。

### 应用图标和名称

图标源文件在 `app/assets/icon/`（SVG 可编辑，PNG 用于生成）。生成两端图标：

```bash
cd app
flutter pub get
dart run flutter_launcher_icons
# iOS 桌面显示的名字（安卓已在 AndroidManifest 里设好）
plutil -replace CFBundleDisplayName -string "再玩我是狗" ios/Runner/Info.plist
```

安卓 8+ 用自适应图标（黄色底 + 前景），安卓 13+ 支持跟随系统配色的单色图标；iOS 用不透明的完整图标。

### 第一次打开时

1. 引导 → 登录（也可以“先不登录，随便看看”）→ 形象创建（暂用默认形象）→ 设目标 → 今天。
2. 安卓：“今天”页会提示打开**使用情况访问权限**，点“去打开”，在系统设置里找到“再玩我是狗”并打开开关，返回 App 自动刷新。
3. 没有权限、在 iOS 或模拟器上时，显示“演示数据”，可以拖动滑杆看不同时长下的变狗效果。

### 目录

```
app/lib/
  main.dart / app.dart        入口、路由（go_router）
  core/                       主题、狗度规则、犬种、接口、全局状态、原生通道
  widgets/                    形象（分层绘制）、波普按钮、底部导航
  features/                   各页面：onboarding / today / card / dex / group / me
app/android/app/src/main/kotlin/com/zwjsg/zwjsg_app/
  UsagePlugin.kt              读取当天使用时长、拿起次数、分类汇总
```

## 还没做（按开发顺序）

- [ ] 技术验证：iOS 屏幕使用时间接口（需向苹果申请权限）
- [ ] 技术验证：照片本地卡通化方案
- [ ] 形象创建：拍照 / 相册 → 卡通化 → 上传
- [ ] 结算卡：截图保存相册、微信分享；每晚提醒推送
- [ ] 短信服务商接入（阿里云 / 腾讯云）、微信登录
- [ ] 正式美术素材替换代码画的形象；标题字体换成已授权的圆体
- [ ] P2：狗群、硬核模式；商业化
