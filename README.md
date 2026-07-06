# 蓝图极智 AI 选股 — iOS + Android 完整交付包

> 版本: v2.0.2+24 | 构建日期: 2026-07-06

---

## 🍎 如何获得 iOS IPA？（两种方案）

### 方案一：Codemagic 免费云构建 ⭐推荐（无需 Mac！）

[**Codemagic**](https://codemagic.io) 是 Flutter 官方推荐的 CI/CD 平台，**提供免费 macOS 构建环境（500分钟/月）**，可以直接在云端生成 IPA！

**步骤：**

1. **注册 Codemagic 账号**（用 GitHub/GitLab/邮箱）
   → https://codemagic.io/signup

2. **上传项目到 Git 仓库**（如果还没有）
   ```bash
   # 在项目根目录
   git init
   git add .
   git commit -m "蓝图极智 v2.0.2"
   # 推送到 GitHub / GitLab / Bitbucket
   ```

3. **在 Codemagic 中创建新 App**
   - 选择你的 Git 仓库
   - 项目类型选择 **Flutter App (via Workflow Editor)**
   - Flutter 版本选 **3.0.0**
   - Xcode 版本选 **15.2**

4. **构建并下载 IPA**
   - 点击 "Start new build"
   - 等待 10-15 分钟
   - 构建完成后，IPA 会出现在 **Artifacts** 中
   - 点击下载即可

**已包含的配置文件**: `codemagic.yaml`（可直接导入 Codemagic）

---

### 方案二：在自己 Mac 上构建

```bash
cd App源码/ai_stock_picker
chmod +x build_ios.sh && ./build_ios.sh
```

构建完成后 IPA: `build/ios/蓝图极智-v2.0.2.ipa`

---

## 📦 目录结构

```
蓝图极智-完整交付包/
├── README.md                       # 本文件
├── codemagic.yaml                  # Codemagic 云构建配置
├── 蓝图极智-v2.0.2.apk            # Android APK (已构建, 25MB)
├── build_ios.sh                    # iOS IPA 一键构建脚本 (Mac用)
├── 技术文档_完整版.md              # 云端部署+App架构+API文档
│
├── 云端服务器/
│   ├── deploy.sh
│   └── ai_stock_picker_backend/
│       ├── main.py                 # FastAPI 主入口 (14个API端点)
│       ├── portfolio_manager.py    # 投资组合管理 (自动买卖)
│       ├── portfolio_monitor.py    # 实时监控 (止盈止损)
│       ├── scheduler.py            # 定时调度 (crontab)
│       ├── requirements.txt
│       ├── strategies/
│       │   └── engine.py           # 8个选股策略 (1295行)
│       └── services/
│           ├── eastmoney.py        # 东方财富 F10
│           ├── sina_finance.py     # 新浪财经排行
│           ├── tencent_quote.py    # 腾讯实时行情
│           └── news_service.py     # 热点新闻筛选
│
└── App源码/
    └── ai_stock_picker/            # Flutter 3.0.0 完整项目
        ├── lib/main.dart           # APP 入口
        ├── lib/models/             # 13 个数据模型
        ├── lib/screens/            # 28 个页面
        ├── lib/services/           # 34 个服务
        ├── lib/widgets/            # 18+ 组件
        ├── ios/                    # ✅ iOS 平台已配置
        └── build_ios.sh            # iOS 构建脚本
```

---

## ☁️ 云端服务器部署

服务器: 百度云 Ubuntu 24.04 | IP: `182.61.45.78`

```bash
cd 云端服务器 && chmod +x deploy.sh && ./deploy.sh
```

涉及的 systemd 服务（2个）和 crontab 定时任务（7个）详见 `技术文档_完整版.md`。

---

## 🔧 App 首次配置

| 配置项 | 值 | 设置位置 |
|--------|-----|----------|
| 服务器地址 | `http://182.61.45.78:8000` | 设置 → 服务器配置 |
| Token | `blueprint_aistock_2026_123456` | 设置 → 服务器配置 |
| AI模型地址 | 用户自行填写 | AI模型配置 |

---

## 📱 核心功能

| 模块 | 单只上限 | 组合上限 | 周期 |
|------|---------|---------|------|
| 极速投资 | ¥20,000 | ¥120,000 (6只) | T买入/T+1卖出 |
| 热点投资 | ¥30,000 | ¥90,000 (3只) | ≤5交易日 |
| 轻量投资 | ¥3,333 | ¥10,000 (3只) | ≤5交易日 |

8 大选股策略：短炒猎手 / 成长先锋 / 稳健堡垒 / A股游资 / 隔夜导航 / 锦鲤选股等

---

## 🛠 技术栈

| 层面 | 技术 |
|------|------|
| 前端 | Flutter 3.0.0 / Dart 2.17.0 |
| 后端 | Python 3.12 / FastAPI / Uvicorn |
| 数据源 | 东方财富、新浪财经、腾讯行情 |
| 备份 | 坚果云 WebDAV / Gitee API |
| 后台 | WorkManager (Android) / BGTaskScheduler (iOS) |
