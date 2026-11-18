# 梗名 App 系列（zwjsg）

一个仓库放整个系列。各 app **独立上架、独立后端、独立数据库、账号不互通**；共用的是代码（设计规范、形象引擎、登录与接口模块）。

| App | 一句话 | App 目录 | 后端目录 | 本地端口 |
| --- | --- | --- | --- | --- |
| 再玩我是狗 | 手机刷得越多，形象越像狗；少刷一点才能做回人 | `apps/zaiwan_gou/` | `backends/zaiwan_gou_api/` | 8000 |
| 什么鬼天气 | 准的天气 + 替你遭罪的嘴贫形象 + 家人关心群 | `apps/shenme_tianqi/` | `backends/shenme_tianqi_api/` | 8001 |
| 再吃我是猪 | 规划中 | — | — | — |

```
packages/
  pop_ui/            黄黑波普设计规范：颜色、描边、硬阴影、主题、波普按钮（Flutter）
  avatar_engine/     卡通形象引擎：人物底层 + 各 app 的叠加层（变狗 DogAvatar、天气 WeatherAvatar）
  series_core/       接口客户端基类：token、错误处理、短信登录、退出、注销（Flutter）
  php/series-auth/   短信验证码服务 + 发送接口（Laravel，composer 本地路径包）
apps/                各 app 的 Flutter 工程，用 path 依赖引用 packages/
backends/            各 app 的 Laravel 工程，用 composer path 仓库引用 packages/php/
```

技术：App 用 Flutter（安卓原生 Kotlin，iOS 原生 Swift 待接入）；后端 Laravel 13 + Sanctum，MySQL / PostgreSQL，Redis。产品需求、UI 设计见各自的需求文档和 UI 设计画布（链接在 `CLAUDE.md`）。

## 系列约定

- 改了 `packages/` 里的东西，所有 app 都要跑一遍测试。
- 用户可以把“再玩我是狗”的卡通形象**主动、一次性**导入其他 app（导出码方案，见下面“形象导出和导入”）；除此之外各 app 之间不传任何用户数据。
- 原始照片只在手机内存里处理，**不落盘、不上传**；服务端只存卡通形象。

---

## 后端：本地运行

需要 PHP 8.3+ 和 Composer。两个后端步骤一样，换目录和端口即可：

```bash
cd backends/zaiwan_gou_api          # 或 backends/shenme_tianqi_api
composer install                    # 会把 packages/php/series-auth 软链接进来
cp .env.example .env
php artisan key:generate
touch database/database.sqlite      # 本地默认用 SQLite
php artisan migrate --seed
php artisan storage:link
php artisan serve --host=0.0.0.0 --port=8000   # 天气后端用 --port=8001
php artisan test
```

本地登录：调用 `POST /api/v1/auth/sms/send` 后，验证码会写进 `storage/logs/laravel.log`（开发环境不真的发短信）。

两个后端共有的接口（前缀 `/api/v1`，除登录外都要 `Authorization: Bearer <token>`）：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `auth/sms/send` | 发送验证码（同一手机号 1 分钟 1 次） |
| POST | `auth/sms/login` | 验证码登录，返回 token |
| POST | `auth/wechat/login` | 微信登录（待配置，现在返回 501） |
| POST | `auth/logout` | 退出 |
| GET / PATCH / DELETE | `me`、`me/settings`、`me` | 当前用户 / 修改设置 / 注销并删除所有数据 |
| POST | `me/avatar` | 上传卡通形象（png/webp，≤1MB） |

形象导出和导入（两个后端之间唯一的调用）：
- 狗 App 在“我的 › 形象 › 导出到「什么鬼天气」”调 `POST me/avatar/export`，拿到 8 位导出码（去掉了容易看错的 0 1 I L O），10 分钟内有效、只能用一次。要先登录、有拍照形象。
- 用户把码填进天气 App，天气 App 调自己后端的 `POST avatar/import`（不用登录）；天气后端带请求头 `X-Series-Key` 去调狗后端的 `POST avatar-exports/redeem`，拿到卡通形象（PNG）原样交回 App。只认 1MB、1024 像素以内的 PNG。
- 天气 App 把形象存在手机上，登录了再用 `POST me/avatar` 存到天气后端。两边账号不互通，导过去以后互不影响。
- 配置：两个后端的 `.env` 配同一个 `SERIES_EXPORT_KEY`（随机长字符串，比如 `openssl rand -hex 32` 生成的），天气后端再配 `GOU_API_BASE`（狗后端地址，写到 `/api/v1`，本地是 `http://127.0.0.1:8000/api/v1`）。没配时狗后端不让取图，天气后端的导入返回 503。

---

## 再玩我是狗

隐私：具体 app 的名称、图标和用时**只在手机上用**，可以交给 Flutter 显示今日排行，**绝不传给服务端**；服务端只接收每天的狗度、分钟数、犬种（`test/ranking_test.dart` 锁定了上报内容）。iOS 的排行由系统报告扩展 `ios/ScreenTimeReport/` 画出来，App 读不到里面的数字。狗度规则两处同步：`apps/zaiwan_gou/lib/core/dog_meter.dart`、`breeds.dart` ↔ `backends/zaiwan_gou_api/config/dog.php`、`app/Services/DogMeter.php`。

本 app 的接口：`GET daily-records?from=&to=`（历史）、`PUT daily-records/{YYYY-MM-DD}`（上报狗度，返回新解锁犬种）、`GET breeds`（图鉴）、`POST me/avatar/export`（生成形象导出码）、`POST avatar-exports/redeem`（给天气后端凭码取图，要带系列密钥）。

App 第一次需要先生成平台工程（已有的文件不会被覆盖）：

```bash
cd apps/zaiwan_gou
flutter create --org com.zwjsg --project-name zwjsg_app --platforms android,ios .
flutter pub get
flutter test
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1
```

真机调试：USB 连好后 `adb reverse tcp:8000 tcp:8000`，`API_BASE` 用 `http://127.0.0.1:8000/api/v1`；或者用电脑的局域网 IP。

应用图标：源文件在 `apps/zaiwan_gou/assets/icon/`，`dart run flutter_launcher_icons` 生成两端图标；iOS 名字用 `plutil -replace CFBundleDisplayName -string "再玩我是狗" ios/Runner/Info.plist`。

第一次打开：引导 → 登录（可跳过）→ 形象 → 设目标 → 今天。安卓“今天”页会提示打开**使用情况访问权限**；没有权限、iOS 或模拟器上显示“演示数据”，可拖滑杆看变狗效果。

“今天”页从上到下：头部（形象、狗度、阶段，右上角“晒一下”）→ 进度卡 → “今天时间去哪了”（一句吐槽 + 前三名，安卓底部还有拿起次数和 23 点后用时，点开看完整排行）→ “这周”（周一到周日一排小形象，加上连续做人几天、离传说犬种“狼”还差几天，点开看历史记录）。两张卡片的代码在 `lib/features/today/today_cards.dart`。iOS 的前三名是报告扩展的精简版（报告名 `topAppsCompact`），App 读不到数字；“狼”最终以服务端判定为准，卡片上只按手机里的记录给进度。

不依赖外部账号的几块：
- 结算卡：头部“晒一下”随时打开。到每晚提醒的时间（默认 22:00，没开提醒也按这个时间）之前，标题是“此刻的我”，卡上写“此刻狗度”和时间；之后是“今日结算”。“保存图片”存到相册（gal），“晒给朋友”打开系统分享面板（share_plus），可以直接发微信。用微信 SDK 分享要等开放平台。
- 每晚提醒：本地通知（flutter_local_notifications），不经过服务器。设目标页点“开始做人”时请求通知权限，默认 22:00；在“我的 › 结算卡提醒”里开关、换时间，点通知直接打开结算卡。登录后提醒时间同步到 `remind_at`，以后做服务端推送时用。安卓用非精确闹钟，可能晚几分钟，国内部分系统还要用户允许后台运行。
- 昵称：“我的”页点名字修改，最长 16 个字，登录后同步到服务端，也显示在结算卡上。
- 隐私政策：`lib/features/me/privacy_page.dart`，“我的”页和登录页都能打开。内容按现在的数据处理写成，上架前要补运营者名称和联系方式，并请法务审核。
- 新犬种解锁动画（`lib/widgets/unlock_celebration.dart`）：上报每日结果时服务端返回这次新解锁的犬种，App 先存在手机上（`pending_unlocks`，服务端只告诉一次），在底部导航的哪个页面都会弹；看过一个删一个，一次解锁几种就一个个弹。现在只有登录了的安卓用户会上报，iOS 还拿不到犬种解锁。

App 时间锁（免费的基础功能，“我的 › App 时间锁”）：选几个 App 和每天的额度，合计用满就锁到第二天 0 点；最多 10 个锁，只存在手机上，不上传。苹果审核指南 4.10 不允许对屏幕使用时间相关的功能收费，所以不能做成会员功能。
- iOS：系统屏蔽（ManagedSettings）。每个锁一个统计周期 `lock.<id>`，用满时监控扩展打上屏蔽，0 点解开；屏蔽页扩展 `ios/ShieldConfig/` 换上狗的文案和配色。
- 安卓：无障碍服务 `LockAccessibilityService`，只听切换 App 的事件。被锁的 App 一打开就算今天用了多久：用满就退回桌面、弹出拦截页 `LockedActivity`；没用满就到点再查一次。用户要在系统“无障碍”里手动打开，小米、华为等还要允许自启动。
- 紧急解锁：每个锁每天 3 次，每次再用 5 分钟（按使用时长算），用满自动锁回去。安卓在拦截页（“还是要刷”）和时间锁页都能解；iOS 在时间锁页里解，原生层撤掉屏蔽，再单独监控 `grace.<id>`，用满由监控扩展重新锁上。次数和分钟数以原生层为准（`LockStore.kt`、`ScreenTimeStore.swift`）。

首次打开先弹隐私政策（`consent_page.dart`，国内商店要求）：同意之前路由只放行隐私政策页，不读使用数据、不读应用列表、不请求权限。政策有重要变化时把 `AppState.privacyVersion` 加 1，所有人重新同意。

历史记录（“今天”页 › “这周”卡片）：每次刷新今天的数据时在手机上存一条（`lib/core/history.dart`），同一天只留最后一次，最多 400 天；可以看最近 7 天或按月的日历。演示数据不记。

iOS 屏幕使用时间（技术验证中）：
- 最低 iOS 16；签名必须用付费开发者团队，免费的 Personal Team 不支持 Family Controls。
- iOS 只告诉 App 用量到了哪个阈值，拿不到分钟数。“今天”页点“去开启”，依次授权、选 App、按每日目标开始统计，之后显示真实阶段：狗度显示成“≥60%”，已刷时长显示下限，不显示拿起次数和 23 点后时长；拿不到分类，犬种先统一按默认的柯基。改每日目标会按新阈值重新统计。
- iOS 的阶段数据暂不上传服务端：开发者协议 3.3.3(P) 不允许把使用数据传出设备，iOS 怎么上报还没定。
- 验证页在“我的 › 技术验证 › 屏幕使用时间”，可以用 10 分钟的测试目标，看每次阈值通知的时间，对照系统“设置 › 屏幕使用时间”看准不准。
- 阈值由 Flutter 按 `dog_meter.dart` 算好传给原生层（`ios/Runner/ScreenTimePlugin.swift`）。到阈值时系统调起监控扩展 `ios/ScreenTimeMonitor/`，扩展把阶段写进 App Group `group.com.zwjsg.zwjsgApp`。选中的 App 是系统的不透明令牌，只存在本机，Flutter 只拿到数量。
- 真机调试不用 Apple 批准。发 TestFlight 或 App Store 前，账户持有人要给主 App `com.zwjsg.zwjsgApp` 和三个扩展 `.ScreenTimeMonitor`、`.ScreenTimeReport`、`.ShieldConfig` 分别申请 Family Controls 发布权限。

拍照形象（iOS 已接进形象创建，安卓还没做）：
- 入口：引导里的“先做一个你”，以后在“我的 › 换个形象”。拍一张自拍（系统相机，优先前置）或用系统选图器选一张 → 手机本地卡通化 → 画成贴纸 → 预览（顺便看刷多了会变成什么样）→ “就用这个”。安卓先用默认形象。
- 第一次用照片前单独弹一次同意（人脸信息，`FaceConsentSheet`），说清照片不保存不上传、卡通形象会上传、AI 生成会标注、只用本人照片。同意记在本机，退出登录后也不用再同意。
- 流程：苹果 Vision 找五官 → 对齐成 288×288 → Core ML 跑 DCT-Net 日漫头像模型（Apache 2.0，`ios/Runner/Models/`，3 MB）→ Vision 抠出人像，代码在 `ios/Runner/CartoonLab.swift`。形象创建走 `zwjsg/cartoon` 通道，只把卡通图和人像蒙版交给 Flutter，照片本身不出原生层、不存盘、不上传。
- 画风（2026-11-16 定）：日漫 + 平涂墨线。卡通图再压成平涂色块、描墨线，抠成白边黑描边的贴纸，在 `packages/avatar_engine` 的 `PhotoSticker`（纯 Dart，iOS、安卓共用）。变狗图层是 `PhotoDogAvatar`：阶段 1 耳朵、2 狗鼻子、3 狗毛、4 舌头和尾巴、5 狗嘴筒，现在是代码画的示意，等美术按 288 的对齐模板画正式素材。
- 保存：贴纸（PNG）存在 App 支持目录（`AvatarStore`，在 `packages/avatar_engine`，和天气 App 共用）。登录了就传服务端（`POST /me/avatar`，只传贴纸）；没登录或没网时先存手机上，登录或下次打开时补传；换手机登录后从 `avatar_url` 下载回来。换掉已有的拍照形象按服务端次数算（默认 3 次），用完时服务端回 422，手机上的形象不变。退出登录会删掉手机上的形象。
- 各处显示用 `MyAvatar`：有拍照形象就用它，没有就用代码画的默认形象。
- 导出到「什么鬼天气」：有拍照形象时“我的 › 形象”里多一行，没登录先去登录；形象还没传上服务端的先补传，再生成导出码，弹层里分两段显示（ABCD-EFGH），可以复制（`lib/features/me/export_avatar_sheet.dart`）。
- AI 标识：用了拍照形象的结算卡，右下角印“AI生成”（文字高度不低于卡片短边的 5%），导出、分享的 PNG 里写入 GB 45438-2025 的 AIGC 元数据（`lib/core/aigc_label.dart`）。上线前请法务确认，`ContentProducer` 换成公司名称或备案号。
- 技术验证页还在“我的 › 技术验证 › 拍照形象（本地卡通化）”，能看对齐后的照片和各步耗时。模型来源、转换脚本和实测数据见 `tools/cartoon/README.md`。验证页和样图上线前要删掉；开源许可页要附 Apache 2.0 许可证。

---

## 什么鬼天气

天气 App：官方数据 + 四张决策卡（带伞 / 秋裤 / 洗车 / 晾衣）+ 跟着天气遭罪的卡通形象 + 三档吐槽（正经 / 损友 / 毒舌）+ 家人关心群。

### 合规与规则

- 天气和预警只来自和风天气转发的气象部门官方数据；**预警原文照登**（标题、正文、发布单位、时间不改）。
- 来源标注（和风的要求）：显示了和风数据的页面都要放 `QWeatherCredit`（“天气服务由和风天气驱动”，链到官网）；接口返回的 `attributions` 要原样显示，不能写死或改写。
- 吐槽文案人工撰写（`config/quips.php`），不用 AI 生成，不改写预报结论；黄色及以上预警进入**严肃模式**，吐槽暂停。
- 玩法结论都在服务端算（`app/Services/WeatherInterpreter.php`，阈值在 `config/weather.php`），App 只展示。
- 关心群防骚扰（`app/Services/CareService.php`）：只能选固定关心话；同一人每天最多提醒同一人 2 次；30 分钟内同话题合并成一条推送；被提醒者本地 22:00–07:00 发的延迟到 07:00（预警除外）；静音对发送者无感知；记录 30 天后删除；群里只显示城市名。

### App 端

- 首次打开先弹隐私政策（`lib/features/privacy/consent_page.dart`）：同意之前路由只放行隐私政策页，不查天气、不请求权限。政策有重要变化时把 `AppState.privacyVersion` 加 1，所有人重新同意。设置页也能打开完整政策。
- 设置页的推送（`PushSection`）：早安播报开关、工作日和周末分开设时间，预警推送开关。推送要发到账号上，所以登录后才能设；设置存在服务端（`PATCH me/settings` 的 `morning_push_*`、`alert_push_on`），推送通道接好后生效。
- 温度单位（设置页）：摄氏度 / 华氏度，不登录也能设，存在手机上；登录后同步到服务端的 `temp_unit`，早安推送按它写。接口里的温度数字一律是摄氏度（照搬数据源），App 显示时换算（`lib/core/temp_unit.dart`）；服务端拼的句子（秋裤理由、关心群的一句事实、早安推送标题）按请求带的 `unit` 写，没带再看用户设置（`app/Support/TempUnit.php`）。两边换算方法要一致，测试用的是同一组数。
- 从“再玩我是狗”导入形象：引导页和“设置 › 我的形象”都能填导出码（`lib/features/settings/import_avatar_sheet.dart`），大小写、空格、连字符不讲究。不登录也能导，先存在手机上，登录后传服务端，换手机登录时下载回来；可以用回默认形象（`DELETE me/avatar`），退出登录会删掉手机上的。导入的形象在首页、严肃模式、设置和关心群里显示：`PhotoWeatherAvatar`（`packages/avatar_engine`）在贴纸上叠穿戴和天气，照片里的衣服换不了，冷热改成冒汗、围巾、毛线帽；群里别人的形象从 `avatar_url` 下载，App 开着时同一个地址只下一次。
- 应用图标：源文件在 `apps/shenme_tianqi/assets/icon/`（翻白眼的云 + 雨和闪电，SVG）。改了 SVG 先导出同名 1024 PNG，例如 `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir=$(mktemp -d) --default-background-color=00000000 --window-size=1024,1024 --screenshot=icon_full.png "file://$PWD/icon_full.svg"`，再运行 `dart run flutter_launcher_icons` 生成两端图标。这个工具（0.14.4）会把 `ios/Runner.xcodeproj/project.pbxproj` 里的 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` 错改成 `AppIcon`，生成后把这个文件还原。iOS 主屏上的名字是“什么鬼天气”（`CFBundleDisplayName`）。

### 配置

`.env` 里填和风天气的 API Host 和 Key（控制台 → 项目 → 凭据）：

```
QWEATHER_HOST=xxxxxx.re.qweatherapi.com
QWEATHER_KEY=你的key
PUSH_DRIVER=log      # 推送先写日志，上线前接统一推送 / 厂商通道 / APNs
GOU_API_BASE=http://127.0.0.1:8000/api/v1   # 导入形象：狗后端地址
SERIES_EXPORT_KEY=和狗后端一样的随机串
```

定时任务（`routes/console.php`）：`care:deliver` 每分钟推送到点的提醒；`weather:morning` 每分钟找到点的用户发早安播报；`care:prune` 每天删 30 天前的提醒记录。本地调试用 `php artisan schedule:work`。

### 本 app 的接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `cities/search?q=` | 城市搜索（不用登录） |
| GET | `weather/{locationId}?level=&adm=&unit=` | 天气 + 玩法结论 + 吐槽（不用登录；登录后按用户设置的档位） |
| POST | `avatar/import` | 凭“再玩我是狗”的导出码取一次卡通形象（不用登录，返回 base64 的 PNG） |
| DELETE | `me/avatar` | 用回默认形象，删掉服务端存的形象 |
| GET / POST | `cities` | 关注的城市（最多 5 个，第一个自动设为常驻） |
| PATCH / DELETE | `cities/{id}` | 设为常驻 / 删除 |
| GET / POST | `care-groups` | 我的关心群 / 建群 |
| POST | `care-groups/join` | 用邀请码加入（2–8 人） |
| GET / PATCH | `care-groups/{id}` | 群详情（成员城市天气、一句事实、可选关心话、今天剩余次数）/ 改群名 |
| POST | `care-groups/{id}/leave` | 退群（群主退出自动转让，没人了解散） |
| POST | `reminders` | 发提醒 |
| GET | `reminders/inbox` | 收到的提醒 |
| POST | `reminders/{id}/ack` | 收到 ♥（合并的几位都会收到回执） |
| GET / POST / DELETE | `mutes` | 静音某人或整个群 |

### App 本地运行

```bash
cd apps/shenme_tianqi
flutter create --org com.zwjsg --project-name shenme_tianqi --platforms android,ios .
flutter pub get
flutter test
adb reverse tcp:8001 tcp:8001     # 真机 USB 调试
flutter run --dart-define=API_BASE=http://127.0.0.1:8001/api/v1
```

不登录就能看天气（城市存在本机）；建关心群需要登录，登录后本机城市会同步到服务端。

---

## 还没做

再玩我是狗：
- [ ] 技术验证：iOS 屏幕使用时间接口
- [ ] 形象创建：安卓的本地卡通化、捏脸；正式的变狗图层素材
- [ ] 结算卡用微信 SDK 分享（现在走系统分享）、下载二维码（上架后）
- [ ] App 时间锁的后续：iOS 屏蔽页上的“还是要刷”（要再加一个屏蔽按钮扩展）、电话和支付等白名单、按狗度或时间段触发
- [ ] P2：狗群；商业化

什么鬼天气：
- [ ] 确认和风天气商用授权和数据来源资质；接入真实推送通道
- [ ] 预警推送（新出现的黄色及以上预警推给用户）；定位（只取区县级）
- [ ] 关心群微信分享卡片
- [ ] 吐槽文案扩充到每格 10 条以上（必须人工写）
- [ ] 照片形象的正式穿戴和遭罪素材（现在是代码画的示意）

系列：
- [ ] 短信服务商接入（阿里云 / 腾讯云）、微信登录（每个 app 单独的开放平台应用）
- [ ] 正式美术素材替换代码画的形象；标题字体换成已授权的圆体
