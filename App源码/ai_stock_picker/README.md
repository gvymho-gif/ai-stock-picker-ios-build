# 蓝图极智AI选股 (AI Stock Picker) v2.0.2

AI 自动选股系统 — 支持 A 股、港股、美股，智能规则引擎深度分析。

> ⚠️ **安全架构升级**: 核心选股策略已迁移至百度云后端，APK不再包含评分公式。
> AI 大模型 API Key 仍保留在 App 端，用户自由配置。

---

## 技术栈

| 层级 | 技术 | 版本 |
|---|---|---|
| **前端** | Flutter (Dart) | 3.0.0 / 2.17.0 |
| **后端** | FastAPI (Python 3.11) | 0.104+ |
| **平台** | Android | SDK 33 (min 21) |
| **构建** | Gradle + Kotlin | 7.1.2 / 1.7.10 |
| **HTTP** | `http` (Dart) / `httpx` (Python) | ^0.13.5 / ^0.25 |
| **图表** | `fl_chart` | ^0.62.0 |
| **持久化** | `shared_preferences` | ^2.0.18 |
| **后台任务** | `workmanager` / `flutter_background_service` | ^0.5.0 / ^2.4.6 |
| **云备份** | WebDAV (坚果云) / Gitee | — |
| **选股保护** | 百度云服务器（私有部署） | — |
| **数据源** | 新浪财经 / 东方财富 / 腾讯行情 | REST API |

---

## 架构说明

```
┌──────────────────────────────────────────────────┐
│              App (Flutter APK)                    │
│                                                    │
│  ✅ UI 展示 / 行情图表 / 投资日历                 │
│  ✅ AI 大模型调用（用户自行配置 API Key）         │
│  ✅ 坚果云 / Gitee 云备份                        │
│  ├─ 服务器地址配置 / Token 验证                  │
│  └─ HTTP 请求选股结果 ────────────┐              │
└──────────────────────────────────────────────────┘
                                     │
                                     ▼
┌──────────────────────────────────────────────────┐
│           百度云服务器 (Python FastAPI)            │
│                                                    │
│  🔒 8大选股策略（短炒猎手/成长先锋/稳健堡垒/      │
│       A股游资/A股游资B/隔夜导航/锦鲤选股/         │
│       锦鲤选股B）                                 │
│  🔒 一票否决库 / 评分公式 / 筛选阈值             │
│  🔒 行情数据抓取（新浪/东方财富/腾讯）            │
│  ✅ Token 认证保护                                │
│  ✅ 可选数据备份                                  │
└──────────────────────────────────────────────────┘
```

**安全优势**: APK 被反编译也只能看到 HTTP 调用地址，无法获取选股评分公式、一票否决规则、策略阈值等核心逻辑。

---

## 核心目录结构

```
source/
├── lib/
│   ├── main.dart                         # 应用入口
│   ├── models/                           # 数据模型 (13个)
│   ├── screens/                          # 页面 (20+)
│   │   ├── settings_screen.dart          # 设置（含服务器配置）
│   │   └── expert_screen.dart            # 专家选页（调用远程策略）
│   ├── services/                         # 业务层
│   │   ├── expert_stock_service.dart     # 选股 → 改为远程调用后端
│   │   ├── server_config_service.dart    # [新增] 服务器地址/Token管理
│   │   ├── ai_model_service.dart         # [保留] AI 模型调用
│   │   ├── jianguoyun_service.dart       # [保留] 坚果云备份
│   │   └── backup_service.dart           # [保留] Gitee备份
│   ├── widgets/                          # UI组件 (15+)
│   └── theme/                            # 深浅色双主题
├── android/                              # Android原生配置
├── assets/                               # 图片资源
└── backend/                              # ⬅️ FastAPI 后端源码
    ├── main.py                           # API入口 + Token认证
    ├── strategies/engine.py              # 8大选股策略Python实现
    ├── services/
    │   ├── sina_finance.py               # 新浪财经API
    │   ├── eastmoney.py                  # 东方财富F10数据
    │   └── tencent_quote.py              # 腾讯行情补充
    └── requirements.txt                  # Python依赖
```

---

## 三大投资模式

| 模式 | 特点 | 周期 |
|---|---|---|
| **极速投资** | T+1 快进快出，自动买入/卖出，6 只预选 | 每日 |
| **热点投资** | 追踪市场热点题材，AI 评级筛选 | 1-3 天 |
| **轻量投资** | 虚拟组合模拟，低风险学习 | 灵活 |

---

## 编译与部署

### 1. 部署后端到百度云

```bash
# 服务器端操作
cd backend
pip3 install -r requirements.txt
export AUTH_TOKEN="你的安全Token_必须修改"
python3 main.py
# 详见 backend/README.md
```

### 2. 编译 APK

```bash
# 环境要求: Flutter 3.0+, Dart 2.17+, JDK 17, Android SDK 33

cd source
flutter pub get
flutter build apk --release
# 输出: build/app/outputs/flutter-apk/app-release.apk
```

### 3. 配置 App

1. 安装 APK 到手机
2. 打开设置 → 选股服务器
3. 填写百度云服务器地址和 Token
4. （可选）在「极智问答」配置 AI 模型 API Key

---

## 版本历史

| 版本 | 日期 | 说明 |
|---|---|---|
| **2.0.2+24** | 2026-07-02 | **架构升级**: 选股策略迁移至百度云后端，新增服务器配置界面，AI Key保留在App端 |
| 2.0.1+23 | 2026-06-21 | 专家选股 UI 优化、投资日历组件 |
| 2.0.0+20 | — | 三大投资模式架构搭建 |

---

## License

Private — 仅供个人使用，未经授权不得分发。
