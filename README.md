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
- 用户可以把“再玩我是狗”的卡通形象**主动、一次性**导入其他 app（导出码方案，待做）；除此之外各 app 之间不传任何用户数据。
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

---

## 再玩我是狗

隐私：具体 app 名称只在安卓原生层用于计算，**不传给 Flutter，更不传给服务端**；服务端只接收每天的狗度、分钟数、犬种。狗度规则两处同步：`apps/zaiwan_gou/lib/core/dog_meter.dart`、`breeds.dart` ↔ `backends/zaiwan_gou_api/config/dog.php`、`app/Services/DogMeter.php`。

本 app 的接口：`GET daily-records?from=&to=`（历史）、`PUT daily-records/{YYYY-MM-DD}`（上报狗度，返回新解锁犬种）、`GET breeds`（图鉴）。

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

---

## 什么鬼天气

天气 App：官方数据 + 四张决策卡（带伞 / 秋裤 / 洗车 / 晾衣）+ 跟着天气遭罪的卡通形象 + 三档吐槽（正经 / 损友 / 毒舌）+ 家人关心群。

### 合规与规则

- 天气和预警只来自和风天气转发的气象部门官方数据；**预警原文照登**（标题、正文、发布单位、时间不改）。
- 吐槽文案人工撰写（`config/quips.php`），不用 AI 生成，不改写预报结论；黄色及以上预警进入**严肃模式**，吐槽暂停。
- 玩法结论都在服务端算（`app/Services/WeatherInterpreter.php`，阈值在 `config/weather.php`），App 只展示。
- 关心群防骚扰（`app/Services/CareService.php`）：只能选固定关心话；同一人每天最多提醒同一人 2 次；30 分钟内同话题合并成一条推送；被提醒者本地 22:00–07:00 发的延迟到 07:00（预警除外）；静音对发送者无感知；记录 30 天后删除；群里只显示城市名。

### 配置

`.env` 里填和风天气的 API Host 和 Key（控制台 → 项目 → 凭据）：

```
QWEATHER_HOST=xxxxxx.re.qweatherapi.com
QWEATHER_KEY=你的key
PUSH_DRIVER=log      # 推送先写日志，上线前接统一推送 / 厂商通道 / APNs
```

定时任务（`routes/console.php`）：`care:deliver` 每分钟推送到点的提醒；`weather:morning` 每分钟找到点的用户发早安播报；`care:prune` 每天删 30 天前的提醒记录。本地调试用 `php artisan schedule:work`。

### 本 app 的接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `cities/search?q=` | 城市搜索（不用登录） |
| GET | `weather/{locationId}?level=&adm=` | 天气 + 玩法结论 + 吐槽（不用登录；登录后按用户设置的档位） |
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
- [ ] 技术验证：iOS 屏幕使用时间接口；照片本地卡通化方案
- [ ] 形象创建：拍照 / 相册 → 卡通化 → 上传；结算卡保存与微信分享；每晚提醒推送
- [ ] P2：狗群、硬核模式；商业化

什么鬼天气：
- [ ] 确认和风天气商用授权和数据来源资质；接入真实推送通道
- [ ] 预警推送（新出现的黄色及以上预警推给用户）；定位（只取区县级）
- [ ] 从“再玩我是狗”一次性导入形象（导出码）；关心群微信分享卡片
- [ ] 吐槽文案扩充到每格 10 条以上；应用图标

系列：
- [ ] 短信服务商接入（阿里云 / 腾讯云）、微信登录（每个 app 单独的开放平台应用）
- [ ] 正式美术素材替换代码画的形象；标题字体换成已授权的圆体
