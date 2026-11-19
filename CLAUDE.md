# 梗名 App 系列（zwjsg）· 给 Claude 的项目说明

一个仓库放整个系列。核心是**好玩、能晒**，不是惩罚。

- **再玩我是狗**：手机刷得越多，用户的卡通形象越像狗；少刷一点才能“做回人”。
- **什么鬼天气**：准的天气 + 替你遭罪的嘴贫形象 + 四张决策卡 + 家人关心群。
- **再吃我是猪**：规划中（饮食，运动抵消，猪度减到 0 为止，不奖励过度运动）。

## 资料

再玩我是狗：
- 需求文档（PRD）：https://claude.ai/artifact/67H9TfC38JnbPFedXxqjEM
- UI 设计画布（10 个页面、设计规范、组件、应用图标）：https://claude.ai/artifact/Vi2AE2EKxVXYyBbhCSDptN
- 早期原型：https://claude.ai/artifact/P342V39mTammTcproaJhcE

什么鬼天气：
- 需求文档（含关心群）：https://claude.ai/artifact/5R6pwDreZrRfCoVX3T8vkZ
- UI 设计画布（首页、严肃模式、决策详情、城市、设置、推送、形象组件、关心群、发提醒、被提醒）：https://claude.ai/artifact/Ak4sFmUsm8yt5jr3kG9w2r

本地运行方法见 README.md。

## 仓库结构

```
packages/pop_ui  packages/avatar_engine  packages/series_core  packages/series_share   Flutter 共用包（path 依赖）
packages/php/series-auth                                         Laravel 共用包（composer path 仓库，命名空间 Series\Auth）
apps/zaiwan_gou        backends/zaiwan_gou_api                   再玩我是狗
apps/shenme_tianqi     backends/shenme_tianqi_api                什么鬼天气
```

## 已定的关键决策

- 技术栈：App 用 Flutter（安卓原生 Kotlin，iOS 原生 Swift），后端 Laravel 13 + Sanctum。
- 系列：各 app 独立上架；**每个 app 的后端单独部署、单独数据库，账号和用户数据不互通**；共用的只是代码。用户可主动从“再玩我是狗”一次性导入形象：狗 App 生成 8 位导出码（10 分钟内有效、只能用一次），天气后端带系列密钥（两个后端配同一个 `SERIES_EXPORT_KEY`）凭码向狗后端取一次卡通图；这是两个后端之间唯一的调用，导过去以后两边互不影响（2026-11-18）。
- 视觉：奶油底 + 黄黑波普（2026-11-19 从整页黄底改过来，整页亮黄太刺眼）。页面底色奶油 #FBF5E6、卡片白色；亮黄 #FFD23F 只用在按钮、阶段牌、进度条、选中态这些小面积的地方，原来整块黄的重点卡片用淡黄 #FFF4C2；墨色 #1B1B1F、3px 粗描边、不模糊的硬阴影；只做浅色。天气首页按天气换的底色也是浅一档的柔和色。应用图标还是亮黄底。
- 文案：损友吐槽语气；不拿身材、长相、成绩开玩笑。
- 形象：AI 只做一次卡通化，变化靠美术分层素材在本地叠加（成本约 1 张图/用户）。默认形象是代码画的示意（`packages/avatar_engine`）。照片卡通化的画风定为日漫（DCT-Net，手机本地跑）+ 平涂墨线，抠成白边黑描边的贴纸（2026-11-16）；以后可以换成美术定制的画风。拍照形象是 AI 生成的：第一次用照片前单独同意，导出的结算卡要带“AI生成”显式标识和 AIGC 元数据。

再玩我是狗：
- 平台：先安卓（能按 app 读使用时长），iOS 屏幕使用时间接口待技术验证。
- 狗度 = 当日使用时长 ÷ 每日目标（默认 3 小时）；阈值 30/60/90/120/150% 对应阶段 1–5；每天 0 点（用户本地时间）重置成人；狗度 < 30% 算“做人”。
- 犬种按**使用模式**判定，不按用量（避免鼓励多刷）；传说犬种“狼”= 连续 7 天做人，只由服务端判定。不做付费抽卡。
- App 时间锁是免费的基础功能（原规划的付费“硬核模式”）：苹果审核指南 4.10 不允许对屏幕使用时间相关的功能收费。iOS 用系统屏蔽，安卓用无障碍服务拦截。
- 底部导航：今天 / 狗群 / 图鉴 / 我的。结算卡 3:4。稀有度：普通黑框、稀有蓝框、传说金框。

什么鬼天气：
- 数据源：和风天气（请求头 `X-QW-Api-Key`，每个账号有自己的 API Host），服务端分接口缓存。
- 合规（《人工智能气象应用服务办法》）：天气和预警只用气象部门官方数据；预警原文照登并注明发布单位和时间；吐槽人工撰写，不用 AI 生成，不改写预报结论。
- 黄/橙/红预警进入严肃模式（吐槽暂停，形象举伞）；蓝色预警只显示横幅。
- 衣服档按体感温度（≥35 / 28 / 18 / 10 / 0 / 更低）；四张决策卡和形象状态的规则全部在服务端算，App 只展示。
- 吐槽三档：正经 / 损友（默认）/ 毒舌；同一天同一条件固定一句，7 天内不重复。
- 关心群：2–8 人，只显示常驻城市名；只能选固定关心话；同一人每天最多提醒同一人 2 次；30 分钟内同话题合并；被提醒者本地 22:00–07:00 延迟到 07:00（预警除外）；静音对发送者无感知；记录 30 天删除。
- 不登录也能看天气；关心群需要登录。首版手动选城市，以后接定位也只取区县级。

## 必须遵守的约定

1. **隐私**：原始照片不落盘、不上传，服务端只存卡通形象。狗 app 的具体 app 名称、图标和各 app 用时只在手机上用：可以交给 Flutter 显示（今日排行、时间锁选 app，2026-11-14 用户同意放宽），绝不传给服务端；iOS 的排行由系统报告扩展画，App 读不到。狗后端只接收狗度、分钟数、犬种（App 端 `test/ranking_test.dart` 和后端都有测试保证）。天气 app 不存定位轨迹，关心群只给城市名（和导入的卡通形象）。改了收集哪些数据，App 里的隐私政策页和 iOS 的隐私清单（狗 App `ios/Runner/PrivacyInfo.xcprivacy`）一起改；扩展里用到 UserDefaults 等要申报原因的接口时，给那个扩展也加隐私清单。
2. **规则两处同步**：狗度 `apps/zaiwan_gou/lib/core/dog_meter.dart`、`breeds.dart` ↔ `backends/zaiwan_gou_api/config/dog.php`、`app/Services/DogMeter.php`；天气的形象状态和衣服档 `packages/avatar_engine/lib/src/weather_avatar.dart` 的枚举 ↔ `backends/shenme_tianqi_api/config/weather.php`；天气的温度换算 `apps/shenme_tianqi/lib/core/temp_unit.dart` ↔ `backends/shenme_tianqi_api/app/Support/TempUnit.php`，秋裤阈值的说明文字 `lib/core/scene.dart` 的 `longJohnsFeelsBelow` ↔ `config/weather.php`；天气桌面小组件：决策卡短名字 `WeatherController::WIDGET_TITLES` ↔ 天气卡 `WeatherCard.shortTitles`，预警颜色 `lib/core/scene.dart` 的 `warningColor` ↔ 小组件两端（`ios/WeatherWidget/WeatherWidget.swift`、安卓 `widget/WeatherWidget.kt`），形象图文件名 `HomeWidgetSync.fileName` ↔ 小组件两端；狗桌面小组件：狗度的算法（`DogMeter.percentFor`、`stageFor`、`minutesToNextStage`、`formatMinutes`）↔ `ios/GouWidget/GouWidget.swift`、安卓 `widget/DogWidget.kt`（阈值和文案由 App 交过去，不用改），监控扩展的存储键名 `ScreenTimeStore` ↔ `ios/GouWidget/GouWidgetShared.swift`；配色 `packages/pop_ui` 的 `Pop`（奶油底、亮黄、墨色、暖灰）↔ 原生代码里各抄的一份（两个 App 的桌面小组件 iOS、安卓，狗 App 的 iOS 屏蔽页 `ShieldConfig`、排行报告扩展 `ScreenTimeReport`、安卓拦截页 `LockedActivity`）。
3. 服务端不信任客户端：狗的阶段一律按狗度重算；天气结论只在服务端算。
4. 改了玩法或接口，同步更新对应 app 的需求文档章节。
5. 改了 `packages/` 里的东西，所有 app 都要跑测试。

## 当前状态

- 再玩我是狗：两端工程骨架、主流程页面、安卓使用时长插件、后端登录/设置/形象/每日记录/图鉴/注销接口及测试、应用图标。iOS 已用付费开发者团队签名，“今天”页接上屏幕使用时间（只拿得到阶段，准确度待真机核对）；结算卡保存与系统分享、每晚本地提醒、昵称、隐私政策页和首次打开的同意弹窗、今日 App 排行、App 时间锁（含紧急解锁）、历史记录已做（时间锁、排行、历史还没在安卓真机上测过）。“今天”页 2026-11-16 改版：底部“提前看今晚的结算卡”按钮换成头部“晒一下”，排行和历史两个入口换成直接露数据的卡片（前三名 + 吐槽；这周 7 天 + 连续做人进度），iOS 的前三名用报告扩展的精简版（已在 iPhone 上确认能显示；安卓真机还没测）。新犬种解锁动画 2026-11-17 已做（服务端返回的新解锁先存手机上，在哪个 Tab 都会弹；iOS 不上报，所以还拿不到解锁）。拍照形象 2026-11-16 接进形象创建（iOS）：自拍或从相册选 → 本地卡通化（DCT-Net 转 Core ML，3 MB，一张约 28 ms，见 `apps/zaiwan_gou/tools/cartoon/README.md`）→ 日漫 + 平涂墨线贴纸（`packages/avatar_engine` 的 `PhotoSticker`，纯 Dart，两端共用）→ 预览确认；人脸单独同意、贴纸存本机、登录后上传和换手机下载、各处显示（`MyAvatar`）、结算卡 AI 标识都已做，测试通过、iOS 能编译，还没在 iPhone 上实际拍过。变狗图层阶段 3–5 先用代码画的示意；安卓的卡通化和捏脸还没做（安卓先用默认形象）。2026-11-18 能把拍照形象导出给“什么鬼天气”（“我的 › 形象”生成导出码，要先登录）；形象存储（`AvatarStore`）和上传、下载接口挪到了共用包。同天做了桌面小组件（P1，iOS 和安卓都有小号、中号）：狗度只在手机上算，安卓小组件自己按当天的使用时长算、约 30 分钟更新，iOS 读监控扩展记下的阶段、到了新阶段马上刷新，0 点变回人；形象图（阶段 0–5）由 App 预先画好。iOS 在模拟器上用写进去的测试阶段看过两种尺寸；安卓能编译，还没在设备上看过。
- 什么鬼天气：后端（和风天气代理与缓存、解释器、吐槽、城市、关心群与提醒、早安推送命令）及测试；App（引导、选城市、首页多城市、严肃模式、决策详情、城市管理、设置、登录、关心群、发提醒、收到的提醒）。2026-11-17 补了首次打开的隐私政策同意页和隐私政策页，设置页加了推送选项（早安播报开关和工作日、周末时间，预警推送开关，登录后才能设，存服务端；推送通道还没接）。2026-11-18 加了温度单位（摄氏度 / 华氏度；数字都按摄氏度存和算，App 换算显示，服务端拼的句子按用户选的单位写）和应用图标（翻白眼的云，`apps/shenme_tianqi/assets/icon/`；iOS 主屏名字改成“什么鬼天气”）。同天做了从“再玩我是狗”导入形象：引导页和设置页填导出码，不登录也能导，登录后存服务端、换手机能找回；首页、严肃模式、设置和关心群用 `PhotoWeatherAvatar`（贴纸 + 穿戴和天气图层，代码画的示意），可以用回默认形象。导入功能要两个后端都配好 `SERIES_EXPORT_KEY`、天气后端配 `GOU_API_BASE` 才能用，还没在真机上走过一遍。天气卡分享（P1）也做了：首页右上角“晒一下”，3:4 卡片能存相册、系统分享，预警期间不生成；用了照片形象时带 AI 标识。还没在真机上存过、分享过。桌面小组件（P1）同天做了，iOS 和安卓都有小号、中号：小组件约每 30 分钟自己取 `GET widget/{locationId}`（不登录、不带吐槽，温度和句子服务端按单位写好），App 把常驻城市和单位交给它，并预先画好 61 张形象图放进共享目录；预警期间只照登预警标题、发布单位和时间。iOS 在模拟器上看过平常和预警两种样子；安卓能编译、小组件已注册进安装包，但本机没有安卓模拟器，还没在设备上看过。为了在 Xcode 27 / iOS 27 上能编译运行，天气 App 的 iOS 最低版本改成 15，并改用 UIScene 生命周期（和狗 App 一样）。关心群邀请也改了：弹手机系统的分享面板发一段带邀请码的话（`series_share` 的 `TextSharer`），群页面上能看到、复制邀请码，群满了不再显示邀请；模拟器上看过分享面板，微信邀请卡片还要等微信开放平台账号。
- 系列仓库已拆出共用包（pop_ui / avatar_engine / series_core / series_share / series-auth）。series_share 是 2026-11-18 从狗 App 拆出来的分享卡片（截图、存相册、系统分享、AI 生成标识），结算卡和天气卡共用；同天加了用系统分享面板发文字的 `TextSharer`，关心群邀请在用。
- 代码都在没有 Flutter SDK、composer 也下不了包的环境里写成，第一次本地编译可能有小错误，以本地 `flutter analyze`、`flutter test`、`php artisan test` 为准。

## 下一步（按优先级）

1. 本地跑通两个后端的测试和两个 App；在安卓真机上核对狗 app 的使用时长和系统“数字健康”是否一致。
2. 什么鬼天气：申请和风天气 Key 并确认商用授权；真机看首页、严肃模式、关心群流程；扩充吐槽文案。
3. 技术验证：iOS 屏幕使用时间接口（阈值准确度待核对）；照片本地卡通化 iOS 已通过并接进形象创建，安卓待做（方案未定：TFLite + ML Kit 打包版，或只用 TFLite + 小模型，体积差约 10 MB）。
4. 推送通道（统一推送 / 厂商 / APNs）：天气的早安播报和预警、关心群提醒。狗的每晚结算提醒已改用手机本地通知，不需要推送。
5. 形象：安卓拍照形象、捏脸、正式的变狗图层素材和照片形象的天气穿戴素材。
6. 接入短信服务商和微信登录；正式美术素材和授权圆体字体。
7. 内测看分享率和留存，再做 P2 和商业化。
