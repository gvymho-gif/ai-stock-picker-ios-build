# 蓝图极智AI选股 — 完整技术文档

> **版本**: v2.0.2 (build 24) | **日期**: 2026-07-03 | **作者**: 蓝图极智  
> **用途**: 本文档包含 App 和云端服务器的全部技术细节。按本文档操作，即使 App 源码删除、云服务器销毁，任何技术人员都可以 100% 重建整个系统。

---

## 目录

1. [系统架构总览](#1-系统架构总览)
2. [环境要求](#2-环境要求)
3. [目录结构](#3-目录结构)
4. [App 端技术详述](#4-app-端技术详述)
5. [服务端技术详述](#5-服务端技术详述)
6. [API 接口文档](#6-api-接口文档)
7. [定时任务与自动化](#7-定时任务与自动化)
8. [部署指南](#8-部署指南)
9. [常用运维命令](#9-常用运维命令)

---

## 1. 系统架构总览

```
┌─────────────────────────────────────────────────────┐
│                   用户手机 (Android)                   │
│  ┌──────────────────────────────────────────────────┐ │
│  │          Flutter App (蓝图极智AI选股)              │ │
│  │                                                   │ │
│  │  ├─ UI 层: 27个页面 (screens/)                    │ │
│  │  ├─ 服务层: 30+ 服务类 (services/)                │ │
│  │  ├─ 模型层: 11个数据模型 (models/)                │ │
│  │  └─ 本地存储: SharedPreferences                   │ │
│  │                                                   │ │
│  │  ★ 选股逻辑 → 云端调用 (不存本地)                  │ │
│  │  ★ AI模型API → 用户配置 (存本地)                  │ │
│  │  ★ 坚果云备份 → WebDAV (https://dav.jianguoyun.com)│ │
│  └──────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
                         │ HTTP (port 8000)
                         │ Token: Bearer xxx
                         ▼
┌─────────────────────────────────────────────────────┐
│              百度云服务器 (Ubuntu 24.04)               │
│  公网IP: 182.61.45.78    规格: 2C2G 1Mbps            │
│                                                      │
│  ┌── systemd: aistock-api ──────────────────────────┐│
│  │       FastAPI + Uvicorn (port 8000)              ││
│  │       /root/backend/main.py                      ││
│  │       ├─ 8个选股策略 (strategies/engine.py)      ││
│  │       ├─ 热点追踪新闻 (services/news_service.py) ││
│  │       ├─ 投资组合API                             ││
│  │       └─ 缓存API                                 ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  ┌── systemd: aistock-monitor ──────────────────────┐│
│  │       实时监控守护进程 (每3秒检查)                 ││
│  │       /root/backend/portfolio_monitor.py          ││
│  │       ├─ 止盈检查 (>+8%)                         ││
│  │       └─ 止损检查 (<-4%)                         ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  ┌── crontab: 定时调度 ─────────────────────────────┐│
│  │       策略执行 + 投资组合自动化                    ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  数据源: 东方财富 + 新浪财经 + 腾讯行情               │
└─────────────────────────────────────────────────────┘
```

### 安全策略

| 层级 | 措施 |
|------|------|
| **选股逻辑** | 全部在服务端 Python 代码中，APK 中无评分公式 |
| **热点新闻关键词** | 关键词列表仅在服务端 `news_service.py`，APK 反编译不可见 |
| **API 认证** | Bearer Token 认证，可在环境变量中自定义 |
| **AI 模型密钥** | 用户自行配置，存于手机本地 SharedPreferences，不上传服务器 |
| **坚果云备份** | 独立于服务器，通过 WebDAV 协议直连坚果云 |

---

## 2. 环境要求

### App 构建环境

| 组件 | 版本 | 说明 |
|------|------|------|
| Flutter SDK | 3.0.0 | 支持 Dart 2.17 ~ 3.0) |
| Dart | 2.17.0 | |
| Java (JDK) | 17 (Corretto 17.0.19) | 通过 sdkman 安装 |
| Android SDK | Platform 33, Build-tools 33.0.0 | |
| Gradle | 7.x (由 Flutter 管理) | |
| OS | Ubuntu 22.04 / macOS | 构建机器 |

### 服务端环境

| 组件 | 版本 | 说明 |
|------|------|------|
| Python | 3.12+ | Ubuntu 24.04 自带 |
| venv | 内置 | 必须使用虚拟环境 |
| Uvicorn | 0.24.0 | ASGI 服务器 |
| FastAPI | 0.104.1 | Web 框架 |
| httpx | 0.25.2 | 异步 HTTP 客户端 |
| pydantic | 2.5.2 | 数据校验 |
| OS | Ubuntu 24.04 (2C2G) | 百度云 |

---

## 3. 目录结构

### App 端 (`ai_stock_picker/`)

```
ai_stock_picker/
├── android/
│   ├── app/
│   │   ├── build.gradle              # compileSdk 33, minSdk 21
│   │   └── src/main/
│   │       ├── AndroidManifest.xml    # usesCleartextTraffic=true, 前台服务
│   │       └── res/xml/
│   │           └── network_security_config.xml  # 允许明文HTTP
│   └── gradle.properties             # JDK 17 路径
├── lib/
│   ├── main.dart                     # 应用入口, ThemeInheritedWidget
│   ├── models/                       # 11个数据模型
│   │   ├── stock_model.dart
│   │   ├── ai_model_config.dart
│   │   ├── hot_track_model.dart
│   │   ├── hot_investment_model.dart
│   │   ├── speed_investment_model.dart
│   │   ├── investment_calendar.dart
│   │   ├── trading_day_record.dart
│   │   └── ...
│   ├── screens/                      # 27个页面
│   │   ├── home_screen.dart          # 首页(板块网格+搜索+专家入口)
│   │   ├── settings_screen.dart      # 设置(服务器/AI/坚果云/备份)
│   │   ├── expert_screen.dart        # 专家选股(8个策略入口)
│   │   ├── hot_track_screen.dart     # 热点追踪(AI决策引擎)
│   │   ├── stock_analysis_screen.dart
│   │   ├── speed_investment_list_screen.dart
│   │   ├── speed_investment_detail_screen.dart
│   │   ├── hot_investment_list_screen.dart
│   │   ├── hot_investment_detail_screen.dart
│   │   ├── lite_investment_list_screen.dart
│   │   ├── lite_investment_detail_screen.dart
│   │   ├── portfolio_menu_screen.dart
│   │   ├── ai_model_config_screen.dart
│   │   ├── ai_qa_screen.dart
│   │   └── ...
│   ├── services/                     # 30+ 服务类
│   │   ├── expert_stock_service.dart     # ★ 选股策略远程调用
│   │   ├── hot_track_service.dart        # ★ 热点追踪(远程新闻+本地AI)
│   │   ├── server_config_service.dart    # 服务器地址/Token管理
│   │   ├── portfolio_sync_service.dart   # 投资组合同步
│   │   ├── jianguoyun_service.dart       # 坚果云WebDAV备份
│   │   ├── backup_service.dart           # 本地备份导入导出
│   │   ├── local_data_service.dart       # 市场数据(新浪/腾讯)
│   │   ├── speed_investment_service.dart # 极速投资业务逻辑
│   │   ├── hot_investment_service.dart   # 热点投资业务逻辑
│   │   ├── lite_investment_service.dart  # 轻量投资业务逻辑
│   │   ├── ai_model_service.dart         # AI模型配置管理
│   │   └── ...
│   ├── widgets/                     # 复用组件
│   ├── theme/                       # 主题(app_theme/colors/spacing/text)
│   └── utils/                       # 工具(交易日判断等)
├── pubspec.yaml                     # 项目依赖
└── assets/                          # logo图片
```

### 服务端 (`ai_stock_picker_backend/`)

```
ai_stock_picker_backend/
├── main.py                  # FastAPI 主入口 (14个API端点)
├── requirements.txt         # Python 依赖
├── strategies/
│   └── engine.py            # ★ 8个选股策略引擎 (1295行)
├── services/
│   ├── news_service.py      # 东方财富新闻 + 关键词初筛
│   ├── sina_finance.py      # 新浪财经 API (板块排行/涨幅榜)
│   ├── tencent_quote.py     # 腾讯行情 API (实时报价/PE/52周高低)
│   └── eastmoney.py         # 东方财富 F10 财务数据 (ROE/PEG/负债率)
├── scheduler.py             # 定时策略调度器
├── portfolio_manager.py     # 投资组合管理器 (激活/结算/止盈止损/选股)
└── portfolio_monitor.py     # ★ 实时监控守护进程 (每3秒)
```

---

## 4. App 端技术详述

### 4.1 技术栈

| 项目 | 值 |
|------|-----|
| 框架 | Flutter 3.0.0 / Dart 2.17.0 |
| 包名 | `com.aistockpicker.ai_stock_picker` |
| 版本 | 2.0.2+24 |
| 应用名 | 蓝图极智 |

### 4.2 依赖 (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.2
  http: ^0.13.5                # HTTP 请求
  shared_preferences: ^2.0.18  # 本地键值存储
  uuid: ^4.0.0                 # UUID 生成
  intl: ^0.18.0                # 国际化/日期格式化
  fl_chart: ^0.62.0            # 图表库
  workmanager: ^0.5.0          # 后台任务调度
  path_provider: ^2.0.11       # 文件路径
  path: ^1.8.0
  flutter_background_service: ^2.4.6  # 前台/后台服务
```

### 4.3 核心服务架构

#### 专家选股服务 (`expert_stock_service.dart`)

所有 8 个选股策略不再在 App 本地上执行，而是通过 HTTP GET 调用服务器：

```dart
// 远程调用核心方法
Future<Map<String, dynamic>> _callRemoteStrategy(
  String strategyId, String name, String desc,
) async {
  final serverUrl = await ServerConfigService.getServerUrl();
  final token = await ServerConfigService.getToken();
  final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
  final url = '$baseUrl/api/strategy/$strategyId';
  
  final response = await _client.get(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
  ).timeout(Duration(seconds: 30));
  
  if (response.statusCode == 200) {
    return json.decode(utf8.decode(response.bodyBytes));
  }
  // ... 错误处理
}
```

**8 个策略 ID 映射**：

| 策略ID | 中文名 | 说明 |
|--------|--------|------|
| `short_term_hunter` | 短炒猎手 | 短线爆发策略 |
| `growth_pioneer` | 成长先锋 | 成长股策略 |
| `stable_fortress` | 稳健堡垒 | 价值投资策略 |
| `speed_assassin` | A股游资 | T+1 极速博弈 |
| `speed_assassin_b` | A股游资B | 游资 + AI 精选 |
| `overnight_navigator` | 隔夜导航 | 盘后选股 + 早盘预埋 |
| `koi_picker` | 锦鲤选股 | 四因子融合选股 |
| `koi_picker_b` | 锦鲤选股B | 量化私募深度分析 |

**AI 增强层**：`speed_assassin_b`、`koi_picker`、`koi_picker_b` 在获取服务端结果后，还允许用户启用 AI 大模型进行二次增强分析。AI API 密钥存储在本地。

#### 热点追踪服务 (`hot_track_service.dart`)

数据流：东方财富新闻(服务端) → 关键词初筛(服务端) → AI决策(手机端) → 标的锁定

```dart
Future<List<Map<String, dynamic>>> fetchAndFilterNews() async {
  final serverUrl = await ServerConfigService.getServerUrl();
  final resp = await _client.get(
    Uri.parse('$baseUrl/api/hot-track/news'),
    headers: {'Authorization': 'Bearer $token'},
  ).timeout(Duration(seconds: 15));

  if (resp.statusCode == 200) {
    final data = json.decode(utf8.decode(resp.bodyBytes));
    return (data['news'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }
  return [];
}
```

#### 投资组合同步 (`portfolio_sync_service.dart`)

将本地 SharedPreferences 中的投资组合数据 POST 到服务器：

```dart
// 同步到服务器
static Future<String> _syncToServer(...) async {
  final url = Uri.parse('$baseUrl/api/portfolio/$type/sync');
  final body = json.encode(data);

  final resp = await _client.post(
    url,
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: utf8.encode(body),
  ).timeout(Duration(seconds: 15));

  if (resp.statusCode == 200) {
    return '已同步 $count 个组合';
  }
  return '服务器返回 ${resp.statusCode}';
}
```

#### 坚果云备份 (`jianguoyun_service.dart`)

通过 WebDAV 协议直接连接坚果云：

```
配置项: 应用名称 + 应用密码
WebDAV 地址: https://dav.jianguoyun.com/dav/蓝图极智AI选股/
备份文件:
  - expert_performance_backup.json   (收益统计)
  - hot_investment_backup.json       (热点投资)
  - lite_investment_backup.json      (轻量投资)
```

### 4.4 三大投资模块

| 模块 | 服务类 | 首建仓日 | 单只上限 | 止盈 | 止损 |
|------|--------|----------|----------|------|------|
| 极速投资 | `speed_investment_service.dart` | 6月15日 | ¥20,000 | 动态 | -4% |
| 热点投资 | `hot_investment_service.dart` | 6月15日 | ¥30,000 | +10% | -4% |
| 轻量投资 | `lite_investment_service.dart` | 6月22日 | ¥3,333 | +10% | -4% |

**交易规则**：
- T+1：今日买入，次日方可卖出
- 交易时段：9:30-11:30, 13:00-15:00
- 非交易时段新建组合 → 待激活状态，次交易日开盘自动激活

### 4.5 Android 配置要点

**AndroidManifest.xml 关键配置**：

```xml
<!-- 允许明文HTTP (Android 9+) -->
<application android:usesCleartextTraffic="true"
             android:networkSecurityConfig="@xml/network_security_config">

<!-- 前台服务声明 (Android 12+ 必需) -->
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="dataSync"
    tools:replace="android:enabled,android:exported,android:stopWithTask,android:foregroundServiceType" />
```

**network_security_config.xml**：允许所有明文 HTTP + 特定域名白名单

**build.gradle 关键配置**：
- `compileSdkVersion 33`
- `minSdkVersion 21`
- `targetSdkVersion 33`
- `applicationId "com.aistockpicker.ai_stock_picker"`

**gradle.properties**：
```properties
org.gradle.jvmargs=-Xmx1536M
android.useAndroidX=true
android.enableJetifier=true
org.gradle.java.home=/root/.sdkman/candidates/java/17.0.19-amzn
```

### 4.6 APK 构建命令

```bash
# 1. 确保 JDK 17
export JAVA_HOME=/root/.sdkman/candidates/java/17.0.19-amzn

# 2. 构建 release APK
cd ai_stock_picker
flutter clean
flutter build apk --release

# 3. 输出位置
# build/app/outputs/flutter-apk/app-release.apk
```

---

## 5. 服务端技术详述

### 5.1 技术栈

| 项目 | 值 |
|------|-----|
| 框架 | FastAPI 0.104.1 (Python) |
| ASGI 服务器 | Uvicorn 0.24.0 |
| Python 版本 | 3.12+ |
| 认证方式 | Bearer Token |
| 默认 Token | `blueprint_aistock_2026_123456` |
| 监听地址 | `0.0.0.0:8000` |

### 5.2 8个选股策略详情 (`strategies/engine.py`, 1295行)

| 策略 | 核心数据源 | 评分维度 | 股票数量 |
|------|-----------|----------|----------|
| **短炒猎手** | 新浪A股排行 | 涨幅×0.4 + 换手率×0.3 + 量比×0.2 + 振幅×0.1 | Top 40 |
| **成长先锋** | 东方财富F10 | ROE×0.3 + PEG×0.25 + 利润增长率×0.25 + 资产负债率×0.2 | Top 30 |
| **稳健堡垒** | 东方财富F10 + 腾讯行情 | PE分位×0.3 + 股息率×0.25 + 52周低位×0.25 + ROE×0.2 | Top 30 |
| **A股游资** | 新浪排行 + 腾讯行情 | 涨停板距离×0.35 + 封板强度×0.3 + 资金流向×0.2 + 板块热度×0.15 | Top 25 |
| **A股游资B** | (同A股游资) + AI增强 | 游资评分 + App端AI二次分析 | Top 20 |
| **隔夜导航** | 新浪排行 + 腾讯行情 | 收盘形态×0.3 + 次日预判×0.3 + 板块持续性×0.25 + 换手×0.15 | Top 20 |
| **锦鲤选股** | 四因子融合 | 动量因子×0.3 + 质量因子×0.25 + 价值因子×0.25 + 情绪因子×0.2 | Top 25 |
| **锦鲤选股B** | 四因子深度 + AI | 锦鲤评分 + 穿透式财务分析 + App端AI深度增强 | Top 15 |

**公共一票否决规则**：
- ST / \*ST 股票
- 北交所 (bj 前缀)
- 夕阳行业 (钢铁/煤炭/水泥/造纸/玻纤/氯碱/纯碱/PVC)
- 新股 (N开头且名称<6字)

### 5.3 数据源服务

| 服务文件 | 数据来源 | 获取内容 | 协议 |
|----------|----------|----------|------|
| `sina_finance.py` | 新浪财经 | 板块排行、A股涨幅榜 | HTTP |
| `tencent_quote.py` | 腾讯行情 `qt.gtimg.cn` | 实时股价、PE、52周高低 | HTTP |
| `eastmoney.py` | 东方财富 F10 | ROE、PEG、负债率、利润增长率 | HTTP |
| `news_service.py` | 东方财富新闻 API | 实时财经新闻 + 关键词筛选 | HTTP |

### 5.4 热点追踪新闻筛选 (`news_service.py`)

**关键词库 (66个)**：

```
政策类: 重大政策, 政策转向, 国务院, 发改委, 工信部, 商务部, 扶持, 补贴, 减免, 放宽, 准入
突发事件: 突发, 紧急, 限制出口, 禁止出口, 出口管制, 制裁, 断供, 禁令, 反制
新技术: 突破, 首创, 全球首, 国内首, 量产, 商业化, 落地, 重大进展, 关键突破
供需危机: 涨价, 紧缺, 缺货, 产能不足, 供给收缩, 需求暴增, 供不应求
重大事件: 重组, 并购, 注入, 借壳, 中标, 签约, 大单, 订单
市场异动: 涨停, 暴涨, 大爆发, 掀涨停潮
```

**降级策略**：如果关键词筛选后为空，返回原始前5条新闻。

### 5.5 投资组合自动管理 (`portfolio_manager.py`)

| 命令 | 触发时间 | 功能 |
|------|----------|------|
| `activate` | 9:30 | 激活 pending 状态的极速组合(开盘价买入) |
| `settle` | 15:00 | 结算到期组合(收盘价卖出) |
| `check` | 每3秒(monitor) | 检查所有持仓止盈止损 |
| `perf` | 19:30 | 计算并缓存收益统计数据 |
| `pick` | 20:00 | 自动提取锦鲤选股B + 隔夜导航推荐股 |

**止盈止损规则**：
- 止盈：涨幅超过 +8% → 触发卖出
- 止损：跌幅超过 -4% → 触发卖出

### 5.6 实时监控守护进程 (`portfolio_monitor.py`)

```
启动方式: systemd service (aistock-monitor)
检查间隔: 3 秒
检查范围: speed/hot/lite 三种投资组合
检查内容: 持仓股票当前价格 vs 买入价
          触发止盈/止损时自动标记状态并记录日志
仅在交易时段 (9:30-11:30, 13:00-15:00) 执行检查
非交易时段休眠
每 5 分钟自动刷新收益快照
```

---

## 6. API 接口文档

**Base URL**: `http://182.61.45.78:8000`  
**认证方式**: Header `Authorization: Bearer <token>`  
**默认 Token**: `blueprint_aistock_2026_123456`

### 6.1 通用接口

#### `GET /`
健康检查 + 版本信息

**响应**:
```json
{"name": "蓝图极智AI选股后端", "version": "1.0.0", "status": "running"}
```

#### `GET /api/health`
健康检查

**响应**:
```json
{"status": "ok", "time": "2026-07-03T13:00:00"}
```

#### `GET /api/strategies`
列出所有策略 (需认证)

**响应**:
```json
{
  "strategies": [
    {"id": "short_term_hunter", "name": "短炒猎手", "desc": "短线爆发策略"},
    ...
  ]
}
```

### 6.2 选股策略接口

#### `GET /api/strategy/{strategy_id}`
运行指定策略 (需认证)

**路径参数**: `strategy_id` = 策略ID (见 4.3 节 8个策略映射)

**响应**:
```json
{
  "strategy": "短炒猎手",
  "description": "短线爆发策略",
  "stocks": [
    {
      "code": "600xxx",
      "name": "股票名",
      "price": 12.34,
      "change_pct": 5.67,
      "score": 85.5,
      "turnover_rate": 3.2,
      "pe": 15.0,
      "market_cap": 120.5
    }
  ],
  "count": 40,
  "timestamp": "2026-07-03T10:00:00"
}
```

### 6.3 热点追踪接口

#### `GET /api/hot-track/news?page_size=20`
获取筛选后的热点新闻 (需认证)

**响应**:
```json
{
  "news": [
    {
      "title": "新闻标题",
      "code": "Art_Code",
      "time": "2026-07-03 12:00:00",
      "url": "https://..."
    }
  ],
  "count": 7,
  "raw_count": 20,
  "updated_at": "2026-07-03T12:00:00"
}
```

### 6.4 市场数据接口

#### `GET /api/market/hot-sectors`
今日热门板块 (需认证)

**响应**:
```json
{
  "sectors": [
    {"name": "板块名", "change_pct": 3.5}
  ],
  "count": 10
}
```

#### `GET /api/market/ranking?count=100`
A股涨幅排行 (需认证)

### 6.5 缓存接口

#### `GET /api/cache/list`
列出所有缓存文件 (需认证)

**响应**:
```json
{
  "caches": [
    {"name": "short_term_hunter", "cached_at": "2026-07-03T09:31:00", "count": 40, "file": "short_term_hunter.json"}
  ]
}
```

#### `GET /api/cache/{strategy_name}`
获取指定策略缓存数据 (需认证)

路径参数: `strategy_name` 如 `short_term_hunter`, `hot_track` 等

### 6.6 投资组合接口

#### `GET /api/portfolio/{ptype}`
获取投资组合数据 (需认证)

路径参数: `ptype` = `speed` / `hot` / `lite` 或 `speed_portfolios` / `hot_portfolios` / `lite_portfolios`

**响应**:
```json
{
  "type": "hot",
  "data": {"portfolios": [...]}
}
```

#### `POST /api/portfolio/{ptype}/sync`
同步投资组合到服务器 (需认证)

**请求体 (兼容两种格式)**:
```json
{"portfolios": [...]}
```
或
```json
{"data": {"portfolios": [...]}}
```

**响应**:
```json
{
  "ok": true,
  "type": "hot_portfolios",
  "synced_at": "2026-07-03T13:08:01",
  "size": 1234
}
```

#### `GET /api/portfolio/picks/latest`
获取最新每日选股结果 (需认证)

#### `GET /api/portfolio/performance`
获取收益统计 (需认证)

### 6.7 备份接口

#### `POST /api/backup/upload`
上传备份 (需认证)

请求体: `{"data": "<json字符串>", "filename": "backup.json"}`

#### `GET /api/backup/list`
列出备份文件 (需认证)

#### `GET /api/backup/download/{filename}`
下载备份文件 (需认证)

### 6.8 错误码

| 状态码 | 含义 |
|--------|------|
| 200 | 成功 |
| 400 | 参数错误 (无效策略ID/投资组合类型) |
| 401 | 缺少认证 Token |
| 403 | Token 验证失败 |
| 404 | 资源不存在 (缓存文件/备份文件) |
| 422 | 请求体格式错误 (JSON校验失败) |
| 500 | 服务器内部错误 |

---

## 7. 定时任务与自动化

### 7.1 Crontab 调度表

```
# ========== 选股策略调度 ==========
# 13:01 午盘开盘 - 执行短炒猎手 + 热点追踪刷新
1 13 * * 1-5  python scheduler.py afternoon_open

# 14:55 收盘前 - 执行隔夜导航
55 14 * * 1-5  python scheduler.py overnight_setup

# 15:05 收盘后 - 执行锦鲤选股
5 15 * * 1-5   python scheduler.py close_eval

# ========== 投资组合自动化 ==========
# 9:30 早盘 - 激活当日极速组合(买入)
30 9 * * 1-5   python portfolio_manager.py activate

# 15:00 收盘 - 结算到期极速组合(卖出)
0 15 * * 1-5   python portfolio_manager.py settle

# 19:30 晚间 - 收益统计
30 19 * * 1-5  python portfolio_manager.py perf

# 20:00 晚间 - 自动选股
0 20 * * 1-5   python portfolio_manager.py pick
```

### 7.2 Systemd 服务

#### `aistock-api.service` (API 服务)

```
[Unit]
Description=AI Stock Picker API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/backend
Environment=AUTH_TOKEN=blueprint_aistock_2026_123456
Environment=PORT=8000
ExecStart=/root/backend/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### `aistock-monitor.service` (实时监控)

```
[Unit]
Description=投资组合实时监控（止盈止损）
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/backend
ExecStart=/root/backend/venv/bin/python /root/backend/portfolio_monitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## 8. 部署指南

### 8.1 服务器初始化

```bash
# 1. 连接服务器
ssh root@182.61.45.78

# 2. 安装 Python (Ubuntu 24.04 自带 3.12)
python3 --version

# 3. 创建项目目录和虚拟环境
mkdir -p /root/backend
cd /root/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 8.2 部署服务端代码

将所有 `.py` 文件上传到 `/root/backend/`：

```bash
# 从本地上传 (在本地执行)
scp -r ai_stock_picker_backend/* root@182.61.45.78:/root/backend/

# 确保目录结构正确
# /root/backend/
#   ├── main.py
#   ├── scheduler.py
#   ├── portfolio_manager.py
#   ├── portfolio_monitor.py
#   ├── requirements.txt
#   ├── strategies/
#   │   └── engine.py
#   └── services/
#       ├── news_service.py
#       ├── sina_finance.py
#       ├── tencent_quote.py
#       └── eastmoney.py
```

### 8.3 创建 systemd 服务

```bash
# 创建 API 服务文件
cat > /etc/systemd/system/aistock-api.service << 'EOF'
[Unit]
Description=AI Stock Picker API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/backend
Environment=AUTH_TOKEN=蓝图极智你的自定义Token
Environment=PORT=8000
ExecStart=/root/backend/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 创建监控服务文件
cat > /etc/systemd/system/aistock-monitor.service << 'EOF'
[Unit]
Description=投资组合实时监控（止盈止损）
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/backend
ExecStart=/root/backend/venv/bin/python /root/backend/portfolio_monitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动
systemctl daemon-reload
systemctl enable aistock-api aistock-monitor
systemctl start aistock-api aistock-monitor
```

### 8.4 设置 Crontab

```bash
crontab -e
```

粘贴第 7.1 节中的 crontab 内容。

### 8.5 百度云安全组配置

在百度云控制台 → 安全组 → 添加入站规则：

| 协议 | 端口 | 来源 |
|------|------|------|
| TCP | 22 | 0.0.0.0/0 (SSH) |
| TCP | 8000 | 0.0.0.0/0 (API) |

### 8.6 构建 App APK

```bash
# 1. 安装 JDK 17
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 17.0.19-amzn

# 2. 安装 Android SDK
# cmdline-tools + platform 33 + build-tools 33.0.0

# 3. 修改 gradle.properties 中的 JDK 路径
echo "org.gradle.java.home=/root/.sdkman/candidates/java/17.0.19-amzn" >> android/gradle.properties

# 4. 构建
cd ai_stock_picker
flutter clean
flutter build apk --release

# 输出: build/app/outputs/flutter-apk/app-release.apk
```

### 8.7 用户侧配置

安装 APK 后，在 App 设置中配置：

| 配置项 | 值 |
|--------|-----|
| 服务器地址 | `http://182.61.45.78:8000` |
| Token | 与服务端 `AUTH_TOKEN` 一致 |
| AI 模型 | 用户自行填写 (baseUrl + API Key + model) |
| 坚果云 | 用户自行填写 (应用名称 + 应用密码) |

---

## 9. 常用运维命令

```bash
# === 服务管理 ===
systemctl status aistock-api          # 查看 API 状态
systemctl status aistock-monitor      # 查看监控状态
systemctl restart aistock-api         # 重启 API
systemctl restart aistock-monitor     # 重启监控
journalctl -u aistock-api -f          # 实时查看 API 日志
journalctl -u aistock-monitor -f      # 实时查看监控日志

# === 端口检查 ===
netstat -tlnp | grep 8000             # 检查 API 是否监听

# === 验证 API ===
curl http://127.0.0.1:8000/           # 健康检查
curl http://127.0.0.1:8000/api/hot-track/news \
  -H "Authorization: Bearer blueprint_aistock_2026_123456"

# === Crontab ===
crontab -l                            # 查看定时任务
tail -f /root/backend/scheduler.log   # 调度日志
tail -f /root/backend/portfolio.log   # 投资组合日志

# === 虚拟环境 ===
source /root/backend/venv/bin/activate  # 激活 venv
pip list                              # 查看已安装包
```

---

## 附录 A: 完整数据流图

```
                   App 端                              服务端
                   ══════                              ══════

用户打开 App
     │
     ├─ 首页 ──→ local_data_service.dart ──→ 新浪财经 API (板块/排行)
     │                                       腾讯行情 API (实时价格)
     │
     ├─ 专家选股 ──→ expert_stock_service.dart ──→ GET /api/strategy/{id}
     │                                              │
     │                                              ├─ strategies/engine.py
     │                                              │   ├─ sina_finance.py
     │                                              │   ├─ tencent_quote.py
     │                                              │   └─ eastmoney.py
     │                                              │
     │                                              └─ 返回: {stocks: [...], count: N}
     │
     ├─ 热点追踪 ──→ hot_track_service.dart
     │                   │
     │                   ├─ GET /api/hot-track/news
     │                   │   └─ services/news_service.py
     │                   │       ├─ fetch_latest_news() → 东方财富API
     │                   │       └─ filter_hot_news() → 关键词筛选
     │                   │
     │                   └─ AI 决策 (手机端本地调用用户配置的 AI)
     │
     ├─ 投资组合 ──→ {type}_investment_service.dart
     │                   │
     │                   ├─ 本地 SharedPreferences 存储
     │                   ├─ 止损止盈: aistock-monitor (每3秒)
     │                   └─ 同步: POST /api/portfolio/{type}/sync
     │
     └─ 备份 ──→ jianguoyun_service.dart
                      │
                      └─ WebDAV → 坚果云 (dav.jianguoyun.com)
                      └─ 本地导出 → JSON 文件
```

---

## 附录 B: 文件清单 (完整)

### App 端 (74个 .dart 文件)

**models/** (11个): stock_model, ai_model_config, ai_model_preset, ai_query_intent, chat_message, favorite_category, favorite_stock, filter_criteria, hot_investment_model, hot_track_model, investment_calendar, speed_investment_model, trading_day_record

**screens/** (27个): home_screen, splash_screen, settings_screen, expert_screen, hot_track_screen, stock_analysis_screen, stock_analysis_content, ai_model_config_screen, ai_qa_screen, favorite_screen, filter_screen, news_detail_screen, portfolio_menu_screen, sector_screen, sector_stocks_screen, speed_investment_list_screen, speed_investment_detail_screen, hot_investment_list_screen, hot_investment_detail_screen, lite_investment_list_screen, lite_investment_detail_screen, trading_day_records_screen, home/components/* (4个)

**services/** (30个): api_service, local_data_service, expert_stock_service, hot_track_service, server_config_service, portfolio_sync_service, jianguoyun_service, backup_service, speed_investment_service, hot_investment_service, lite_investment_service, ai_model_service, ai_qa_service, alert_service, background_service, chat_history_service, expert_performance_service, expert_performance_worker, favorite_service, financial_report_service, foreign_holder_service, market_overview_service, news_service, nlp_service, rag_service, report_generator_service, research_report_service, stock_compare_service, stock_deep_analysis_service, stock_filter_service, theme_service, trading_day_cloud_service, yahoo_finance_service

**widgets/** (11个): stock_card, filter_panel, hot_investment_card_widget, lite_investment_card_widget, speed_investment_card_widget, investment_calendar_widget, investment_return_calendar_widget, market_index_scroll_widget, market_overview_widget, expert_performance_widget, landscape_index_panel, landscape_performance_grid, ai_chart_bubble, styles, common/* (7个)

**theme/** (4个): app_theme, app_colors, app_spacing, app_text

**utils/** (1个): trading_day_utils

### 服务端 (7个 .py 文件)

main.py, scheduler.py, portfolio_manager.py, portfolio_monitor.py, strategies/engine.py, services/news_service.py, services/sina_finance.py, services/tencent_quote.py, services/eastmoney.py
