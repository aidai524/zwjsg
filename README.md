# 梗名 App 系列（zwjsg）

一个仓库放整个系列。各 app **独立上架、独立后端、独立数据库、账号不互通**；共用的是代码（设计规范、形象引擎、登录与接口模块）。

| App | 一句话 | App 目录 | 后端目录 | 本地端口 |
| --- | --- | --- | --- | --- |
| 再玩我是狗 | 手机刷得越多，形象越像狗；少刷一点才能做回人 | `apps/zaiwan_gou/` | `backends/zaiwan_gou_api/` | 8000 |
| 什么鬼天气 | 准的天气 + 替你遭罪的嘴贫形象 + 家人关心群 | `apps/shenme_tianqi/` | `backends/shenme_tianqi_api/` | 8001 |
| 再吃我是猪 | 规划中 | — | — | — |

```
packages/
  pop_ui/            设计规范（奶油底 + 黄黑波普）：颜色、描边、硬阴影、主题、波普按钮（Flutter）
  avatar_engine/     卡通形象引擎：人物底层 + 各 app 的叠加层（变狗 DogAvatar、天气 WeatherAvatar，照片形象的 PhotoDogAvatar、PhotoWeatherAvatar），形象存在手机上（AvatarStore），给桌面小组件预先画形象图（WidgetImages）
  series_core/       接口客户端基类：token、错误处理、短信登录、退出、注销、上传和下载形象（Flutter）
  series_share/      分享：卡片截图、存相册、系统分享，AI 生成内容的显式标识（AiTag）和隐式标识（AigcLabel），用系统分享面板发文字（TextSharer）（Flutter）
  php/series-auth/   短信验证码服务 + 发送接口（Laravel，composer 本地路径包）
apps/                各 app 的 Flutter 工程，用 path 依赖引用 packages/
backends/            各 app 的 Laravel 工程，用 composer path 仓库引用 packages/php/
```

技术：App 用 Flutter（原生部分安卓用 Kotlin，iOS 用 Swift）；后端 Laravel 13 + Sanctum，MySQL / PostgreSQL，Redis。产品需求、UI 设计见各自的需求文档和 UI 设计画布（链接在 `CLAUDE.md`）。

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

### 接真实短信（阿里云）

两个后端共用 `series-auth` 里的发送器，按 `.env` 的 `SMS_DRIVER` 选：`log` 只写日志（开发用；`APP_ENV=production` 时会拒绝发码，免得线上悄悄只写日志），`aliyun` 走阿里云短信（SendSms 接口，V3 签名，没用 SDK）。上线前要自己做：

1. 在阿里云开通短信服务，申请**签名**（两个 App 可以各用各的）和**验证码模板**（模板里放一个变量，比如 `您的验证码是${code}，5 分钟内有效`），等审核通过。
2. 建一个 RAM 子账号，只给短信发送的权限（`AliyunDysmsFullAccess` 或只含 `dysms:SendSms` 的自定义策略），生成 AccessKey。
3. 在服务器的 `.env` 里填（不要提交到仓库）：`SMS_DRIVER=aliyun`、`ALIYUN_SMS_ACCESS_KEY_ID`、`ALIYUN_SMS_ACCESS_KEY_SECRET`、`ALIYUN_SMS_SIGN_NAME`、`ALIYUN_SMS_TEMPLATE_CODE`，模板变量不叫 `code` 时再填 `ALIYUN_SMS_TEMPLATE_PARAM`。
4. 发得太频繁、手机号不对时，App 会看到“发得太频繁了，过一会儿再试”这类话；其他错误只说“短信服务暂时不可用”，具体错误码写在日志里（手机号打码，不记验证码）。

真机上用真实账号建关心群，后端还要部署到公网：服务器、备案过的域名和 HTTPS，App 编译时把 `API_BASE` 指过去。

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

本 app 的接口：`GET daily-records?from=&to=`（历史）、`PUT daily-records/{YYYY-MM-DD}`（上报狗度，返回新解锁犬种）、`GET breeds`（图鉴）、`POST me/avatar/export`（生成形象导出码）、`POST avatar-exports/redeem`（给天气后端凭码取图，要带系列密钥）；群组：`GET / POST groups`、`POST groups/join`、`GET / PATCH groups/{id}`、`PATCH groups/{id}/me`（隐藏狗度、关掉汪一下）、`POST groups/{id}/leave`、`POST groups/{id}/nudges`（汪一下）、`GET nudges/inbox`、`POST nudges/seen`。加了群组以后要跑一次 `php artisan migrate`；`nudges:prune` 每天删 30 天前的汪一下记录，要定时任务在跑。

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

第一次打开：引导 → 登录（可跳过）→ 形象 → 选使用程度 → 今天。使用程度三档：正常使用 3 小时、重度使用 5 小时、无可自拔 8 小时（`dog_meter.dart` 的 `GoalTier`，后端 `config/dog.php` 的 `goal_tiers` 只收这三个值；旧版本自己设的小时数打开时换成最接近的一档）。只用真实数据：安卓“今天”页提示打开**使用情况访问权限**，iOS 提示打开屏幕使用时间；拿不到数据时狗度显示“？”、没有进度卡、不能晒，不用演示数据。

“今天”页从上到下（2026-11-20 改版）：头部（形象、狗度、阶段，右上角“晒一下”）。形象外面一圈是今天刷了多少（`stage_ring.dart`）：转满一圈是狗度 150%，刻度是每个阶段的门槛，超过目标的部分标红；圈下面写今日已刷、目标和“再刷多久你就会……”。→ “今天时间去哪了”（一句吐槽 + 前五名，设了超时来电的 App 后面带电话标记、超时的整条标红；安卓再写拿起次数和 23 点后用时；卡片底下一行是超时来电用到哪了，点了去管理限时；点卡片看完整排行）→ “这周”（一句小结：做人几天、变狗几天、安卓再写日均；每天一根柱子，头上是那天的形象，虚线是目标；连续做人几天、离传说犬种“狼”还差几天，点开看狗度统计）。超时来电不再单独占一张卡（它是设置，不是展示）。两张卡片的代码在 `lib/features/today/today_cards.dart`。iOS 的前五名是报告扩展的精简版（报告名 `topAppsCompact`，留了 176 点高），App 读不到数字；“狼”在安卓上以服务端判定为准，卡片上只按手机里的记录给进度。

不依赖外部账号的几块：
- 结算卡：头部“晒一下”随时打开。到每晚提醒的时间（默认 22:00，没开提醒也按这个时间）之前，标题是“此刻的我”，卡上写“此刻狗度”和时间；之后是“今日结算”。“保存图片”存到相册（gal），“晒给朋友”打开系统分享面板（share_plus），可以直接发微信。用微信 SDK 分享要等开放平台。
- 每晚提醒：本地通知（flutter_local_notifications），不经过服务器。设目标页点“开始做人”时请求通知权限，默认 22:00；在“我的 › 结算卡提醒”里开关、换时间，点通知直接打开结算卡。登录后提醒时间同步到 `remind_at`，以后做服务端推送时用。安卓用非精确闹钟，可能晚几分钟，国内部分系统还要用户允许后台运行。
- 昵称：“我的”页点名字修改，最长 16 个字，登录后同步到服务端，也显示在结算卡上。
- 隐私政策：`lib/features/me/privacy_page.dart`，“我的”页和登录页都能打开。内容按现在的数据处理写成，上架前要补运营者名称和联系方式，并请法务审核。
- 开源许可（2026-11-26）：“我的 › 开源许可”，用系列共用的许可页（`pop_ui` 的 `showPopLicenses`：Flutter 自带的 LicensePage，App 没接系统的中文本地化，这一页的标题等几处单独换成中文；狗 App 这边的入口和版本号在 `lib/features/me/licenses_page.dart`，版本号照 pubspec，测试会对一遍）。Dart 包的许可 Flutter 自己列；Dart 包以外、打包进 App 的模型和运行库在 `lib/core/licenses.dart` 补上，按平台列：安卓是 YAMNet 声音分类模型、它的类别名（AudioSet 本体，CC BY-SA 4.0）和 LiteRT 运行库，iOS 是 DCT-Net 卡通化模型和示例图。许可证全文在 `assets/licenses/`（从 LiteRT 1.4.2 的 AAR 自带的 LICENSE 拆出来：Apache 2.0 全文、Caffe 版权声明）。以后打包新的第三方模型、字体、素材，在 `licenses.dart` 加一条。
- 桌面小组件（iOS `ios/GouWidget/`，安卓 `android/app/src/main/kotlin/.../widget/`）：小号（2×2）是狗度、形象、阶段牌和一句吐槽；中号（4×2）再加今日已刷、目标和“再刷多久你就会……”，点小组件打开 App。狗度只在手机上算、不联网：安卓的小组件自己用 `TodayUsage` 算当天的使用时长（和 App 同一个算法），系统大约每 30 分钟叫醒一次，0 点另有闹钟让它变回人；iOS 只知道到了哪个阶段（监控扩展记在 App Group 里），到了新阶段监控扩展马上叫小组件刷新，狗度显示成“≥60%”，0 点变回人。阈值和文案由 App 交过去（照搬 `dog_meter.dart`），原生只做“分钟 ÷ 目标 → 数越过了几个阈值”。没开权限、没做完引导时提示打开 App，不显示演示数据。App 这边是 `lib/core/home_widget.dart` 的 `HomeWidgetSync`，6 张形象图（阶段 0–5）预先画好放进共享目录，换了形象或画法版本（`dogAvatarArtVersion`）才重画。iOS 的小组件要 iOS 17 以上。
- iOS 隐私清单（`PrivacyInfo.xcprivacy`）：主 App、监控扩展、小组件扩展各一份，都申报了读写 App Group 的 UserDefaults（原因 1C8F.1）；屏蔽页扩展、屏蔽页按钮扩展也读 App Group（今天的阶段、形象图、限时），一样申报；报告扩展 2026-11-27 起也读 App Group 里已经设了哪些限时（超时来电的建议跳过它们，只读），一样申报。主 App 的清单照隐私政策写明收集的数据：手机号、账号和昵称、登录后上传的卡通形象、同步的目标和提醒时间、群组（群名、加了哪些群、汪一下，算 OtherUserContent）；iOS 现在不上传每天的狗度，所以没写，以后 iOS 要上报时补上。改了隐私政策要一起改。
- 新犬种解锁动画（`lib/widgets/unlock_celebration.dart`）：上报每日结果时服务端返回这次新解锁的犬种，App 先存在手机上（`pending_unlocks`，服务端只告诉一次），在底部导航的哪个页面都会弹；看过一个删一个，一次解锁几种就一个个弹。安卓要登录了才上报；iOS 不上报，在手机上按同样的规则判定传说「狼」（连续 7 天做人，`AppState._judgeLocalWolf`，记在 `local_breed_unlocks`），解锁时一样弹。
- 图鉴（`lib/features/dex/`）：解锁了的用你的形象显示、写着梗和变成过几天；没解锁的是剪影和解锁条件，「狼」带连续做人的进度；点开一种狗看详情（怎么变成、怎么判、第一次解锁的日子、变成过几天）。iOS 拿不到 App 类别、拿起次数和时段，只能变狼和金毛寻回犬，图鉴上写明了。
- 进化形态（2026-11-26，规则和文案 `lib/core/evolution.dart`，画法 `packages/avatar_engine/lib/src/evolution.dart`）：连续做人 3 / 7 / 14 / 30 天依次解锁「学霸」「西装精英」「养生大师」「头顶光环」，解锁了一直在，中断只清零连续天数。连续做人按手机上的每天记录从昨天往前数（`humanStreakBefore`），今天没过完不算，所以第 3 天守住了、第 4 天打开 App 时解锁（`AppState.checkEvolutions`，每次读完使用情况调一次）。只在做人（阶段 0）时穿：`MyAvatar` 在阶段 0 给形象穿上用户挑的那种（没挑过穿最新解锁的），以前的日子、统计、犬种预览传 `evolved: false` 不穿。
  - 图鉴最上面一排四种（`evolution_section.dart`）：解锁了的是穿上它的你，正穿着的描黄边，没解锁的是剪影和要连续做人几天；点开能“做人时穿这个”或“不穿了”。
  - 解锁时弹“进化了”（`unlock_celebration.dart` 的 `EvolutionUnlockDialog`），和新犬种共用一个队列（名字是 `evo:` 开头），点“穿上看看”就穿上。
  - “这周”卡片多一句还差几天解锁下一种；结算卡做人那天写进化形态的名字和梗；桌面小组件做人那张图也穿上（形象图的签名带着穿哪种，换了就重画）。
  - 存在手机上（SharedPreferences 的 `evolutions`、`evolution_worn`），和每天的记录一样换手机不带过去、退出登录清掉，服务端不知道。
- 犬种（`lib/core/breeds.dart` 的 `judgeBreed`，和后端 `config/dog.php` 的 `breeds` 一致，测试会对一遍）：还是人的那天没有犬种；节日限定的最先判，再是稀有的。
  - 节日限定（2026-11-27，红框“限定”，日子在 `lib/core/festivals.dart` ↔ 后端 `config/dog.php` 的 `festival_breeds`，测试会对一遍）：元旦「立flag犬」、春节（除夕到正月初六）「旺财」、七夕「单身狗」、中秋「天狗」，那几天变狗，那天的犬种就是它。只看日期和阶段，iOS 也在手机上判定、解锁（没打开 App 的那天按监控扩展记的阶段补上）。图鉴里没拿到的只在那几天出现（写着还剩几天），过了不再出现、明年再来；拿到了一直在。农历节日的日子按年写死到 2030 年（用系统农历算的），过了要往后补。后端只在那几天、变狗时才收这种犬种，别的日子报上来的那天不记犬种；`GET breeds` 的总数不算没拿到的限定犬种。
  - 稀有「金毛寻回犬」（每天叼回一点自己）：前 4 天一天比一天刷得少，最后一天和今天都还是狗（`isRetrieverTrend`）。只看过完的日子，不拿今天比（早上谁都比昨天少）；安卓比分钟数，iOS 比监控扩展记下的每天最高阶段，在手机上判定、解锁（`AppState._judgeLocalBreeds`）。安卓从系统补历史时按日期从早到晚判，补完再重判今天。
  - 稀有「串串」（血统不纯，爱好很杂）：同一天里短视频、游戏、聊天办公三样各占两成以上（`muttShare`）。
  - 普通：23 点后占三成以上是哈士奇，拿起 120 次以上是吉娃娃，其余按占大头的分类：游戏边牧、聊天办公社畜柴犬、短视频柯基（iOS 拿不到分类，平时都是柯基）。
  - 传说「狼」：连续 7 天做人，服务端判定（iOS 在手机上判定）。

群组（原“狗群”，2026-11-20 改名并做完，底部导航第二个 Tab，要登录；`lib/features/group/`，后端 `GroupController`、`NudgeController`、`GroupService`）：
- 2–10 人的熟人群，一个人最多加 5 个群。建群起个名字（最长 16 字），用系统分享面板发一段带 8 位邀请码的话，对方在“群组 › 用邀请码加入”填进来；不许诺任何奖励（微信分享规则）。
- 群里只共享每天的狗度、阶段和犬种（不给分钟数，更没有 App 明细）。“今天谁最狗”：每个人的形象按今天的阶段画，最狗的在前；没同步、藏起来了的写清楚。“今天”按每个人自己本地的日期算。
- 昨天的狗王：昨天狗度最高的人（隐藏狗度的不参加，大家都是人就没有），能生成 3:4 的调侃卡存相册、分享；狗王用拍照形象时标“AI生成”、写隐式标识。
- 一起做人：从昨天往前数，全群连续几天都是人；只算最近 30 天上报过记录的人（iPhone 用户不上报，不算），那天还没进群的不算，那天没有记录的算断；连续 7 天拿“狼群”称号（原来规划的群限定装扮先不做）。
- 汪一下：点群里的人叫 TA 放下手机，同一个人每天最多汪同一个人 2 次。推送还没接，对方下次打开 App 或回到前台时弹“汪！”（`NudgeListener`），看过标成已读；对方关掉了汪一下的，照样记下但不给对方看，发的人看不出区别。记录 30 天后删。
- 右上角菜单：改群名（群主）、隐藏我的狗度、不接收汪一下、退出群组（群主退出交给最早进群的人，没人了就解散；注销账号时先退出所有群）。
- iPhone：苹果开发者协议 3.3.3(P) 不让使用数据离开手机，iOS 不上报，群里看不到 iPhone 用户的狗度；他们照样能看别人、汪别人，页面上写明了。

超时来电（单个 App 限时，免费的基础功能，“我的 › 超时来电”，“今天”页“时间去哪了”卡片底下那行也能进）：选几个 App 和每天的额度，合计用满后狗版的你打电话来问你还确定要玩吗。来电是一个像 FaceTime 的来电界面（2026-11-23，Flutter 两端共用 `lib/features/call/call_screen.dart`）：铺满屏幕的模糊形象、一圈圈的波纹、一直在晃的接听键、铃声和震动；接听后有通话计时，狗版的你一句一句说（打电话来的是用户自己变成狗的那个身份；台词在 `lib/features/call/call_script.dart`，字幕 + 提前用 MiniMax 生成好的语音，三个声音在超时来电页自己挑，通话中标明“AI 合成语音”，改了台词要按 `tools/voice/README.md` 重新生成；能关扬声器），再选“学狗叫”（对着手机学两声狗叫，再玩 10 分钟，到点再打）或“挂断”（不玩了）；**拒接就今天锁死，明天 0 点解开**。页面底下能“试一下来电”（响铃、说话、听狗叫都是真的，不锁也不放行）；iOS 还能“试一下来电通知”：8 秒后响一条和真的一样、带铃声的来电通知（App 开着时系统不弹，要先回到桌面或锁屏），点通知回到 App 就是试一下的来电（`CallPlugin.swift` 的 `previewNotice`，记在 `ScreenTimeStore.recordPreviewCall`）。最多 10 个限时，只存在手机上，不上传。
- 狗版的你的建议（2026-11-23，超时来电页最上面，`lock_advice_card.dart`，规则在 `lib/core/lock_advisor.dart`）：看最近 7 天，列出最费时间的几个 App，建议先给哪几个设限时。娱乐类（系统分类是视频、游戏、社交，或者在常见娱乐 App 的包名单里）日均 20 分钟以上就建议，认不出类别的要 45 分钟以上；微信、钉钉、地图、支付这些离不开的不建议；额度取不超过日均七成的一档，最多 3 个。安卓默认都勾上，能改额度，一键设好（一个 App 一个限时）；iOS 的数据出不了报告扩展，由扩展按同样的规则画出来（`LimitAdvice`），用户在系统的选择页里自己勾。
- 学狗叫（`lib/core/bark_detector.dart`，两端只用这一份；原生交音量和手机上声音分类器的分数）：
  - 先按音量切出每一声：每 20 毫秒一个音量，开头 0.4 秒估计环境噪音；一声 = 比环境响 15 dB 以上（至少 -38 dBFS）、持续 0.08–0.8 秒、后面安静 0.12 秒。比环境响 8 dB 但没到这么响的，记成“小声的一声”。
  - 再看声音分类器怎么说（2026-11-24）：iOS 用系统自带的（SoundAnalysis，303 类），安卓用打包的 YAMNet（Google 开源，Apache 2.0，521 类，`android/app/src/main/assets/yamnet.tflite`，`SoundClassifier.kt` 用 LiteRT 1.4.2 跑）。都是 1 秒一窗、每 0.25 秒一次，原生把类别名和分数原样交过来，`lib/core/sound_labels.dart` 归成狗叫、人声、拍手（拍手、打响指、敲桌子）、吹气（吹气、吹口哨）。叫出来的（人声或狗叫 ≥ 10%）算一声；拍手、吹气不算；分类器拿不准的也算（宁可放过）；小声的人声提醒大点声；超过 0.8 秒的不算。分类器开不了、一声结束 1.5 秒还没结果，就只按音量算。
  - 一共两声就过。学了一声、拍手、太小声、太长、学得特别像（狗叫 ≥ 50%），狗版的你各插一句（每种一轮一次，台词早就生成好了）；插话时先关麦克风，说完接着听，已经听到的接着算，所以不限两声隔多久。爪印下面写“这声像狗 N%”（像狗指数）；“试一下来电”多写一行分类器给的分数，方便在真机上看判得准不准。
  - 只在手机内存里判断，不录音、不保存、不上传，也不识别说了什么。没开麦克风、麦克风打不开时，按住按钮 10 秒代替，不会被卡死。
  - 模型和类别表的来源、怎么重新导出，见 `apps/zaiwan_gou/tools/bark/README.md`。苹果审核指南 4.10 不允许对屏幕使用时间相关的功能收费，所以不能做成会员功能。
- 按狗度来电（2026-11-27）：编辑限时时选“今天狗度到了”，挑 60 / 90 / 100 / 120 / 150%（`LockService.dogPresets`，默认 100%）：今天一共刷到目标的这么多以后，再打开选中的 App 就来电，接听、学狗叫、拒接都和按额度的一样。安卓的无障碍服务按今天一共刷了多久算（目标由 Flutter 交给原生层存在 `LockStore`，换目标时再交一次）；iOS 盯的是狗度统计的那些 App 一共刷了多久（要先在“今天”页开启屏幕使用时间的统计），换目标、重新选统计的 App 时跟着重设。来电界面、屏蔽页、来电通知都写“狗度到了”，不写额度。
- 安卓选 App（2026-11-27，`app_picker_page.dart`）：上面一排“短视频 / 社交 / 游戏”整类勾，再点一次整类取消（`lib/core/app_groups.dart`：先认常见的包名，再看系统分类，聊天办公的不算）；白名单（`LockWhitelist.kt`：系统默认的电话、短信，系统标成地图的，常见的支付、银行 App，系统设置）放在最后、灰的，勾不了，存的时候也滤掉，无障碍服务也不对它们来电。iOS 用系统的选择页，本来就能选类别；它的令牌是不透明的，认不出是哪个 App，做不了白名单。
- 安卓：无障碍服务 `LockAccessibilityService`，只听切换 App 的事件。设了限时的 App 一打开就算今天用了多久：用满就在它上面打开来电页 `CallReminderActivity`（不退回桌面）。它是单独任务栈里的 `FlutterActivity`，用单独的 Flutter 引擎跑 `main.dart` 的 `callMain`，只画来电界面；引擎启动要一会儿，原生一打开就先用手机自己的来电铃声响、震动（静音模式下跟系统来电一样）。原生能力在 `CallPlugin.kt`：来电信息、铃声、接通和挂断音、系统语音（手机有中文语音时念，念的话不带 App 名称）、听狗叫（`AudioRecord`，要 `RECORD_AUDIO` 权限；音量加上 `SoundClassifier` 的分类，模型第一次用时在后台装进内存）、放行（`LockStore.snooze`）、拒接（`LockStore.declineToday`）。放行了回到那个 App，拒接、挂断回桌面；今天拒接过的，再打开直接是“今天锁死了”。主界面也注册了一份 `CallPlugin`，给“试一下来电”用。再玩不限次数，用满 10 分钟（按使用时长算）再来电。用户要在系统“无障碍”里手动打开，小米、华为等还要允许自启动。
- iOS：系统屏蔽（ManagedSettings）。iOS 不让 App 在别的 App 上弹页面，国内上架也不能用 CallKit，屏蔽页也放不了动画和声音，所以来电界面在 App 里，铃声靠通知。每个限时一个统计周期 `lock.<id>`，用满时监控扩展打上屏蔽，记下一通来电（`ScreenTimeStore.recordCall`，10 分钟内打开 App 还在响），再发一条带原创铃声的通知（`CallNotice.ring`；铃声 `assets/sounds/ring.caf` 由主 App 启动时拷到 App Group 的 `Library/Sounds/dog_call.caf`）。屏蔽页扩展 `ios/ShieldConfig/` 做成来电样式（图标是今天这个阶段的形象），按钮由 `ios/ShieldActions/` 处理：绿色“接听”记下已接听（30 分钟内有效）、发通知把人带回 App；红字“拒接（今天锁死）”记下今天拒接，屏蔽页换成“今天锁死了”，只剩一个按钮。点通知、或者自己打开 App 时，`CallGate` 弹出来电界面（在屏蔽页上接过的直接是通话中）。原生能力在 `ios/Runner/CallPlugin.swift`：原创铃声循环、每句开头震一下（静音模式下不出声），接通后的提示音和系统语音静音模式下也放；听狗叫开麦克风每 20 毫秒把音量交给 Flutter，同时用系统自带的声音分类器（`SNClassifySoundRequest` `.version1`）每 0.25 秒判断一次；学会了调 `LockShield.snooze` 撤掉屏蔽、单独监控 `grace.<id>`，用满由监控扩展再挡上、再打来；拒接再挡上直到明天 0 点。
- 再玩的分钟数以原生层为准（`LockStore.SNOOZE_MINUTES`、`ScreenTimeStore.snoozeMinutes`），Flutter 只用来显示。

首次打开先弹隐私政策（`consent_page.dart`，国内商店要求）：同意之前路由只放行隐私政策页，不读使用数据、不读应用列表、不请求权限。政策有重要变化时把 `AppState.privacyVersion` 加 1，所有人重新同意。

狗度统计（“今天”页 › “这周”卡片，或“我的 › 狗度统计”，`lib/features/history/stats_page.dart`，算法在 `lib/core/history_stats.dart`）：最近 7 / 30 / 90 天的平均每天用时（iOS 是平均阶段）、做人和变狗天数、最长连续做人、最狗的一天、和前一段比、每天的柱状图（虚线是额度）、各阶段几天、星期几最容易变狗、变成过的犬种、最近 7 天最费时间的 App（安卓自己画，iOS 用报告扩展按 7 天画）；底部进“每天的记录”（按周、按月的日历）。数据只在手机上（`lib/core/history.dart`，每天一条，最多 400 天），只记真实数据。没打开 App 的日子也会补上：安卓从系统读最近约 10 天每天的汇总（`getPastDays`，系统已经没有记录的日子不补），登录后把前两天补报给服务端；iOS 的监控扩展每天记下到过的最高阶段（`ScreenTimeStore.stageHistory`）。

iOS 屏幕使用时间（技术验证中）：
- 最低 iOS 16；签名必须用付费开发者团队，免费的 Personal Team 不支持 Family Controls。
- iOS 只告诉 App 用量到了哪个阈值，拿不到分钟数。“今天”页点“去开启”，依次授权、选 App、按每日目标开始统计，之后显示真实阶段：狗度显示成“≥60%”，已刷时长显示下限，不显示拿起次数和 23 点后时长；拿不到分类，犬种先统一按默认的柯基。改每日目标会按新阈值重新统计。
- iOS 的阶段数据暂不上传服务端：开发者协议 3.3.3(P) 不允许把使用数据传出设备，iOS 怎么上报还没定。
- “我的 › 技术验证”2026-11-20 去掉了（屏幕使用时间和拍照形象两个验证页一起删了）。以前用验证页设过 10 分钟测试目标的，“今天”页会提示改回每日目标。
- 阈值由 Flutter 按 `dog_meter.dart` 算好传给原生层（`ios/Runner/ScreenTimePlugin.swift`）。到阈值时系统调起监控扩展 `ios/ScreenTimeMonitor/`，扩展把阶段写进 App Group `group.com.zwjsg.zwjsgApp`。选中的 App 是系统的不透明令牌，只存在本机，Flutter 只拿到数量。
- 真机调试不用 Apple 批准。发 TestFlight 或 App Store 前，账户持有人要给主 App `com.zwjsg.zwjsgApp` 和三个扩展 `.ScreenTimeMonitor`、`.ScreenTimeReport`、`.ShieldConfig` 分别申请 Family Controls 发布权限。

预设形象（2026-11-27，用户定不做捏脸：开头多一步、太复杂，影响转化）：
- 形象创建页（引导里的“先挑一个你”，以后在“我的 › 换个形象”）一格一张预设的脸，默认选中现在用的（没挑过是呆毛），点“就用这个”就往下走；最后一格用照片（只有 iOS，见下面的拍照形象）。
- 7 张：呆毛（原来的默认形象，一笔没改）、丸子头、长发、卷毛、寸头、粉色短发、中分，发型、发色、肤色不一样（`packages/avatar_engine` 的 `AvatarPreset`，画法 `PresetArt`，代码画的示意）。变狗图层大家一样；完全变狗以后头发没了，各留一个记号：呆毛、丸子、星星发夹、卷毛、粗眉毛、粉毛、中分。
- 有拍照形象也能换成预设形象：照片留在手机上，点照片那一格能换回来，来回换不用重新上传、不算换形象的次数。预设形象不是 AI 生成的，结算卡不标“AI生成”；导出到「什么鬼天气」只在用着拍照形象时有。
- 同步：挑的哪张存在手机上（`avatar_preset`），登录后传狗后端（`PATCH me/settings` 的 `avatar_preset`，只收 `config/dog.php` 的 `avatar_presets` 里的名字，Flutter 测试会对一遍；`null` 是换回拍照形象）。没登录、没网时，登录后或下次打开 App 时补上（先补传拍照形象，再补预设）；登录时这台手机上没挑过的，用服务端记着的那张。传了新的拍照形象，服务端就清掉预设。群组里用预设形象的人只给名字，不给拍照形象的地址。退出登录清掉。

拍照形象（iOS 2026-11-16、安卓 2026-11-27 接进形象创建）：
- 入口：形象创建页的最后一格（引导里的“先挑一个你”，以后在“我的 › 换个形象”），先选拍一张还是从相册选。拍一张自拍（系统相机，优先前置）或用系统选图器选一张 → 手机本地卡通化 → 画成贴纸 → 预览（顺便看刷多了会变成什么样）→ “就用这个”。安卓先用默认形象。
- 第一次用照片前单独弹一次同意（人脸信息，`FaceConsentSheet`），说清照片不保存不上传、卡通形象会上传、AI 生成会标注、只用本人照片。同意记在本机，退出登录后也不用再同意。
- 流程：苹果 Vision 找五官 → 对齐成 288×288 → Core ML 跑 DCT-Net 日漫头像模型（Apache 2.0，`ios/Runner/Models/`，3 MB）→ Vision 抠出人像，代码在 `ios/Runner/CartoonLab.swift`。形象创建走 `zwjsg/cartoon` 通道，只把卡通图和人像蒙版交给 Flutter，照片本身不出原生层、不存盘、不上传。
- 安卓（2026-11-27，`CartoonPlugin.kt`、`CartoonPipeline.kt`、`CartoonCameraActivity.kt`，同一个 `zwjsg/cartoon` 通道）：拍照用 App 里的 CameraX 相机页（系统相机只会把照片写成文件），`takePicture` 直接拿内存里的 JPEG；相册用系统的照片选择器，读进内存。MediaPipe 的人脸检测和人脸网格找 5 个点 → 和 iOS 同一个模板对齐成 288 → DCT-Net 的 TFLite 版卡通化 → MediaPipe 自拍抠图（往外放大 1.5 倍再抠），用听狗叫已经带着的 LiteRT 1.4.2 跑。4 个模型在 `android/app/src/main/assets/cartoon/`（约 6 MB，加上 CameraX 安装包约多 7 MB），来源、转换和在 Mac 上的核对见 `apps/zaiwan_gou/tools/cartoon/README.md`。还没在安卓真机上试过。
- 画风（2026-11-16 定）：日漫 + 平涂墨线。卡通图再压成平涂色块、描墨线，抠成白边黑描边的贴纸，在 `packages/avatar_engine` 的 `PhotoSticker`（纯 Dart，iOS、安卓共用）。变狗图层是 `PhotoDogAvatar`，和默认形象同一套画法（2026-11-23 改）：阶段 1 大垂耳（带“砰”的线条）、2 亮鼻子、3 狗毛、4 长舌头和摇尾巴、5 狗嘴筒加 ω 嘴、爪子里捧着手机；现在是代码画的示意，等美术按 288 的对齐模板画正式素材。
- 保存：贴纸（PNG）存在 App 支持目录（`AvatarStore`，在 `packages/avatar_engine`，和天气 App 共用）。登录了就传服务端（`POST /me/avatar`，只传贴纸）；没登录或没网时先存手机上，登录或下次打开时补传；换手机登录后从 `avatar_url` 下载回来。换掉已有的拍照形象按服务端次数算（默认 3 次），用完时服务端回 422，手机上的形象不变。退出登录会删掉手机上的形象。
- 各处显示用 `MyAvatar`：用着拍照形象就用它，不然用代码画的 `DogAvatar`（挑的那张预设形象，没挑过是呆毛）。默认形象 2026-11-23 改成 Q 版：大头、带高光的大眼睛、腮红、尖刘海加呆毛、亮黄卫衣；阶段 1 大垂耳，2 亮鼻子和 ω 嘴，3 狗毛脸、眼圈斑、项圈，4 吐长舌头、摇尾巴，5 完全变狗、捧着手机。改了画法把 `dogAvatarArtVersion` 加 1（现在是 2），桌面小组件、来电页、屏蔽页用的形象图会重画。
- 导出到「什么鬼天气」：有拍照形象时“我的 › 形象”里多一行，没登录先去登录；形象还没传上服务端的先补传，再生成导出码，弹层里分两段显示（ABCD-EFGH），可以复制（`lib/features/me/export_avatar_sheet.dart`）。
- AI 标识：用了拍照形象的结算卡，右下角印“AI生成”（文字高度不低于卡片短边的 5%），导出、分享的 PNG 里写入 GB 45438-2025 的 AIGC 元数据（`packages/series_share` 的 `AigcLabel`，和天气卡共用）。上线前请法务确认，`ContentProducer` 换成公司名称或备案号。
- Flutter 的卡通化验证页 2026-11-20 删了；原生的 `zwjsg/cartoon_lab` 通道和样图还在（`CARTOON_LAB_AUTORUN` 开关在真机上测卡通化要用），上线前删掉。模型来源、转换脚本和实测数据见 `tools/cartoon/README.md`；DCT-Net 的 Apache 2.0 许可证已经附在“我的 › 开源许可”里（iOS）。

---

## 什么鬼天气

天气 App：官方数据 + 四张决策卡（带伞 / 秋裤 / 洗车 / 晾衣）+ 跟着天气遭罪的卡通形象 + 三档吐槽（正经 / 损友 / 毒舌）+ 家人关心群。

### 合规与规则

- 天气和预警只来自和风天气转发的气象部门官方数据；**预警原文照登**（标题、正文、发布单位、时间不改）。
- 来源标注（[和风的规定](https://dev.qweather.com/docs/terms/attribution/)）：产品里要写明“天气服务由和风天气驱动”并链到官网；用了预警、空气质量的地方必须原样显示接口给的来源（`attributions`）。2026-11-19 用户定：“由和风天气驱动”只放在设置页（`QWeatherCredit()`）；严肃模式、天气详情页、有预警横幅时的首页、关心群页用 `QWeatherCredit(attributions: …, brand: false)` 只显示来源。分享卡和桌面小组件出了 App，照旧写“天气服务由和风天气驱动”。
- 吐槽文案人工撰写（`config/quips.php`），不用 AI 生成，不改写预报结论；黄色及以上预警进入**严肃模式**，吐槽暂停。
- 玩法结论都在服务端算（`app/Services/WeatherInterpreter.php`，阈值在 `config/weather.php`），App 只展示。
- 关心群防骚扰（`app/Services/CareService.php`）：只能选固定关心话；同一人每天最多提醒同一人 2 次；30 分钟内同话题合并成一条推送；被提醒者本地 22:00–07:00 发的延迟到 07:00（预警除外）；静音对发送者无感知；记录 30 天后删除；群里只显示城市名。

### App 端

- 首次打开先弹隐私政策（`lib/features/privacy/consent_page.dart`）：同意之前路由只放行隐私政策页，不查天气、不请求权限。政策有重要变化时把 `AppState.privacyVersion` 加 1，所有人重新同意。设置页也能打开完整政策。
- 开源许可（2026-11-26）：设置页“隐私政策”下面，用和狗 App 共用的许可页（`pop_ui` 的 `showPopLicenses`；入口和版本号在 `lib/features/settings/licenses_page.dart`，版本号照 pubspec，测试会对一遍）。天气 App 没有打包 Dart 包以外的第三方模型、字体、素材（天气动画是代码画的），列的就是 Dart 包的许可；以后打包了，像狗 App 的 `lib/core/licenses.dart` 那样补上。
- 设置页的推送（`PushSection`）：早安播报开关、工作日和周末分开设时间，预警推送开关。推送要发到账号上，所以登录后才能设；设置存在服务端（`PATCH me/settings` 的 `morning_push_*`、`alert_push_on`），推送通道接好后生效。
- 温度单位（设置页）：摄氏度 / 华氏度，不登录也能设，存在手机上；登录后同步到服务端的 `temp_unit`，早安推送按它写。接口里的温度数字一律是摄氏度（照搬数据源），App 显示时换算（`lib/core/temp_unit.dart`）；服务端拼的句子（秋裤理由、关心群的一句事实、早安推送标题）按请求带的 `unit` 写，没带再看用户设置（`app/Support/TempUnit.php`）。两边换算方法要一致，测试用的是同一组数。
- 首页（`lib/features/home/`）：每个城市只显示到“今天的决定”，下面“天气详情”进详情页 `weather_detail_page.dart`（接下来 12 小时、未来 7 天、空气质量、湿度和风、接下来几个钟头的湿度和风力）。底色上叠一层天气动画 `weather_backdrop.dart`：晴天太阳光圈慢慢转（高温加热浪）、多云云朵飘、下雨雨丝、雷阵雨闪电、下雪雪花、大风风线、雾霾和沙尘颗粒、闷热水汽；严肃模式不放；系统开了“减弱动态效果”只画一帧；一圈 60 秒，粒子按整数圈走，循环接得上。测试里在 `test/flutter_test_config.dart` 关掉动画（不然 `pumpAndSettle` 等不完）。
- 决策详情的“每小时下雨的概率”（`PopChart`）：每根柱子都写百分比，上面一句话说结论；晴天全是 0% 时以前只剩细线，看着像没数据。
- 天气卡（`lib/features/card/weather_card_page.dart`）：首页右上角“晒一下”，3:4 的卡片上有城市和实况时间、温度（按温度单位）、形象和吐槽、四张决策卡的结论、“天气服务由和风天气驱动”和 App 图标；能存相册、用系统分享面板发出去（截图和分享在 `packages/series_share`）。预警期间（严肃模式）不显示入口，也不生成卡片。用了导入的照片形象时右下角标“AI生成”（字高不低于卡片宽的 5%），导出的 PNG 写入 AIGC 隐式标识，`ContentProducer` 先写“什么鬼天气”。存相册在 iOS 要 `NSPhotoLibraryAddUsageDescription`，安卓 10 及以下要 `WRITE_EXTERNAL_STORAGE`。
- 从“再玩我是狗”导入形象：引导页和“设置 › 我的形象”都能填导出码（`lib/features/settings/import_avatar_sheet.dart`），大小写、空格、连字符不讲究。不登录也能导，先存在手机上，登录后传服务端，换手机登录时下载回来；可以用回默认形象（`DELETE me/avatar`），退出登录会删掉手机上的。导入的形象在首页、严肃模式、设置和关心群里显示：`PhotoWeatherAvatar`（`packages/avatar_engine`）在贴纸上叠穿戴和天气，照片里的衣服换不了，冷热改成冒汗、围巾、毛线帽；群里别人的形象从 `avatar_url` 下载，App 开着时同一个地址只下一次。
- 关心群邀请（`lib/features/care/group_page.dart`）：右上角“+ 邀请”和群里只有自己时的大按钮都弹手机系统的分享面板（`packages/series_share` 的 `TextSharer`），发一段写清楚怎么加入的话（带邀请码，不带链接，还没有下载页）；面板打不开时复制下来。页面上能看到邀请码，点一下只复制邀请码；群满 8 人后不再显示邀请。微信邀请卡片等微信开放平台账号。
- 桌面小组件（iOS `ios/WeatherWidget/`，安卓 `android/app/src/main/kotlin/.../widget/`）：小号（2×2）是城市、天气、温度、形象和伞、秋裤两张决策卡；中号（4×2）再加实况时间、最低最高温、一句话结论（和关心群的“一句事实”同一套规则）和四张决策卡，点小组件打开 App。小组件大约每 30 分钟自己取一次 `GET widget/{locationId}`：不登录、不带吐槽，温度和句子服务端按单位写好，两端原样显示；取不到时显示 3 小时内的旧数据，再久就提示取不到。预警期间（严肃模式）只显示第一条预警的标题原文、发布单位和时间，形象举伞，不显示决策卡。App 这边是 `lib/core/home_widget.dart` 的 `HomeWidgetSync`：同意隐私政策、选了城市以后把常驻城市和温度单位交给小组件；小组件跑不了 Flutter，所以 App 把 61 张形象图（6 档衣服 × 10 种天气，加预警时举伞的一张）预先画好放进共享目录（iOS 是 App Group `group.com.zwjsg.shenmeTianqi`，安卓是 `files/avatars`），形象换了或者画法版本（`weatherAvatarArtVersion`）变了才重画。iOS 的小组件要 iOS 17 以上。
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
| GET | `widget/{locationId}?unit=&adm=` | 桌面小组件的精简天气（不用登录、不带吐槽；温度和句子按 `unit` 写好；严肃模式给第一条预警的标题、发布单位和时间） |
| POST | `avatar/import` | 凭“再玩我是狗”的导出码取一次卡通形象（不用登录，返回 base64 的 PNG） |
| DELETE | `me/avatar` | 用回默认形象，删掉服务端存的形象 |
| GET / POST | `cities` | 关注的城市（不限个数，只有 50 个的防刷上限；第一个长期关注的自动设为常驻；带 `expires_at` 是临时城市，到点不再返回） |
| PATCH / DELETE | `cities/{id}` | 设为常驻、临时改长期（`expires_at: null`） / 删除 |
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

不登录就能看天气（城市存在本机）；建关心群需要登录，登录后本机城市会同步到服务端。关注的城市不限个数；加城市时可以选临时看 1 / 3 / 7 天（出差、旅行），到点 App 打开或回到前台时清掉，服务端每小时 `cities:prune` 兜底，临时城市不能当常驻。首页蓝色和其他颜色的预警横幅能点 × 关掉（按条记在手机上），黄色及以上的严肃模式不能关。

iOS：最低 iOS 15（Xcode 27 不支持更低的版本，`Podfile` 的 post_install 也把插件统一设成 15）；和“再玩我是狗”一样用 UIScene 生命周期（iOS 27 的要求），原生插件在 `AppDelegate.swift` 的 `PluginsRegistrant` 里注册。模拟器上用 `flutter run -d <模拟器>`；`flutter build ios --simulator` 在 Flutter 3.38 + Xcode 27 上同时打两种架构时会报 “does not contain architectures”，跟代码无关。

---

## 还没做

再玩我是狗：
- [ ] 技术验证：iOS 屏幕使用时间接口
- [ ] 形象创建：安卓的拍照形象（2026-11-27 做了）要在安卓真机上试；正式的预设形象和变狗图层素材（不做捏脸，2026-11-26 定）
- [ ] 结算卡用微信 SDK 分享（现在走系统分享）、下载二维码（上架后）
- [ ] 超时来电的后续：按时间段触发（按狗度、白名单、按类勾 2026-11-27 做了）；在真机上试来电界面（安卓的来电页和铃声；iOS 的来电通知、铃声、屏蔽页的“接听”和“拒接”）
- [ ] 群组：汪一下接推送（现在要等对方打开 App 才看到）、微信邀请卡片；iPhone 用户的狗度先不共享（苹果开发者协议 3.3.3(P)，2026-11-20 定），上架前再评估
- [ ] 犬种的正式美术（现在用变狗阶段的形象代替；两种稀有犬种 2026-11-26、四种节日限定犬种 2026-11-27 已定）
- [ ] 商业化（“开通会员”和“装扮商店”的入口 2026-11-20 先去掉了）

什么鬼天气：
- [ ] 确认和风天气商用授权和数据来源资质；接入真实推送通道
- [ ] 预警推送（新出现的黄色及以上预警推给用户）；定位（只取区县级）
- [ ] 关心群微信分享卡片
- [ ] 吐槽文案扩充到每格 10 条以上（必须人工写）
- [ ] 照片形象的正式穿戴和遭罪素材（现在是代码画的示意）

系列：
- [ ] 后端部署到公网，把阿里云短信的配置填进服务器的 `.env`（签名和验证码模板 2026-11-19 已审核通过，本机试过能收到验证码；服务器上用只给发短信权限的 RAM 子账号的 AccessKey）；微信登录（每个 app 单独的开放平台应用）
- [ ] 正式美术素材替换代码画的形象；标题字体换成已授权的圆体
