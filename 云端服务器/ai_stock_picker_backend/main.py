"""
FastAPI 主入口 - 蓝图极智AI选股后端服务
"""
import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Depends, Header, Body, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from services.sina_finance import SinaFinanceService
from services.tencent_quote import TencentQuoteService
from services.eastmoney import EastMoneyService
from services.news_service import NewsService
from strategies.engine import StrategyEngine

# ============================================================
# 初始化
# ============================================================

app = FastAPI(
    title="蓝图极智AI选股后端",
    description="选股策略引擎 API - 保护核心算法",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 服务实例
sina = SinaFinanceService()
tencent = TencentQuoteService()
eastmoney = EastMoneyService()
news_svc = NewsService()
engine = StrategyEngine(sina, tencent, eastmoney)

# ============================================================
# 配置
# ============================================================

AUTH_TOKEN = os.environ.get("AUTH_TOKEN", "blueprint_aistock_2026_123456")
DISABLE_AUTH = os.environ.get("DISABLE_AUTH", "false").lower() in ("true", "1")

CACHE_DIR = os.environ.get("CACHE_DIR", "/root/backend/cache")
PORTFOLIO_DIR = os.environ.get("PORTFOLIO_DIR", "/root/backend/portfolios")


async def verify_token(authorization: Optional[str] = Header(None)):
    """Token 认证中间件"""
    if DISABLE_AUTH:
        return True
    if not authorization:
        raise HTTPException(status_code=401, detail="缺少认证Token")
    if authorization.startswith("Bearer "):
        token = authorization[7:]
    else:
        token = authorization
    if token == AUTH_TOKEN:
        return True
    user_token = os.environ.get("USER_AUTH_TOKEN", "")
    if user_token and token == user_token:
        return True
    raise HTTPException(status_code=403, detail="Token验证失败")


# ============================================================
# 通用 API
# ============================================================

@app.get("/")
async def root():
    return {"name": "蓝图极智AI选股后端", "version": "1.0.0", "status": "running"}


@app.get("/api/health")
async def health_check():
    return {"status": "ok", "time": datetime.now().isoformat()}


# ============================================================
# 策略 API
# ============================================================

@app.get("/api/strategies")
async def list_strategies(_=Depends(verify_token)):
    """列出所有可用策略"""
    return {
        "strategies": [
            {"id": "short_term_hunter", "name": "短炒猎手", "desc": "短线爆发策略"},
            {"id": "growth_pioneer", "name": "成长先锋", "desc": "成长股策略"},
            {"id": "stable_fortress", "name": "稳健堡垒", "desc": "价值投资策略"},
            {"id": "speed_assassin", "name": "A股游资", "desc": "T+1极速博弈与情绪接力"},
            {"id": "speed_assassin_b", "name": "A股游资B", "desc": "游资策略+AI精选"},
            {"id": "overnight_navigator", "name": "隔夜导航", "desc": "盘后选股+早盘预埋策略"},
            {"id": "koi_picker", "name": "锦鲤选股", "desc": "四因子融合选股"},
            {"id": "koi_picker_b", "name": "锦鲤选股B", "desc": "量化私募极智穿透分析"},
        ]
    }


@app.get("/api/strategy/{strategy_id}")
async def run_strategy(strategy_id: str, _=Depends(verify_token)):
    """运行指定选股策略"""
    valid_ids = [
        "short_term_hunter", "growth_pioneer", "stable_fortress",
        "speed_assassin", "speed_assassin_b", "overnight_navigator",
        "koi_picker", "koi_picker_b",
    ]
    if strategy_id not in valid_ids:
        raise HTTPException(status_code=400, detail=f"无效策略ID: {strategy_id}")
    result = await engine.run_strategy(strategy_id)
    return result


# ============================================================
# 热点追踪 API
# ============================================================

@app.get("/api/hot-track/news")
async def hot_track_news(page_size: int = 20, _=Depends(verify_token)):
    """获取并筛选热点追踪新闻"""
    try:
        raw_news = await news_svc.fetch_latest_news(page_size)
        filtered = news_svc.filter_hot_news(raw_news)
        return {
            "news": filtered,
            "count": len(filtered),
            "raw_count": len(raw_news),
            "updated_at": datetime.now().isoformat(),
        }
    except Exception as e:
        return {"news": [], "count": 0, "error": str(e)}


# ============================================================
# 缓存 API
# ============================================================

@app.get("/api/cache/list")
async def cache_list(_=Depends(verify_token)):
    """列出所有缓存的策略结果"""
    if not os.path.exists(CACHE_DIR):
        return {"caches": []}
    items = []
    for fname in os.listdir(CACHE_DIR):
        if fname.endswith(".json"):
            fpath = os.path.join(CACHE_DIR, fname)
            try:
                with open(fpath, "r", encoding="utf-8") as f:
                    data = json.load(f)
                items.append({
                    "name": fname.replace(".json", ""),
                    "cached_at": data.get("cached_at", ""),
                    "count": data.get("count", 0),
                    "file": fname,
                })
            except Exception:
                pass
    items.sort(key=lambda x: x.get("cached_at", ""), reverse=True)
    return {"caches": items}


@app.get("/api/cache/{strategy_name}")
async def get_cache(strategy_name: str, _=Depends(verify_token)):
    """获取指定策略的缓存结果"""
    fpath = os.path.join(CACHE_DIR, f"{strategy_name}.json")
    if not os.path.exists(fpath):
        raise HTTPException(status_code=404, detail=f"缓存不存在: {strategy_name}")
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 投资组合 API
# ============================================================

def _load_portfolio(typename: str) -> dict:
    """读取投资组合JSON"""
    fpath = os.path.join(PORTFOLIO_DIR, f"{typename}.json")
    if os.path.exists(fpath):
        with open(fpath, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def _save_portfolio(typename: str, data: dict):
    """保存投资组合JSON"""
    os.makedirs(PORTFOLIO_DIR, exist_ok=True)
    fpath = os.path.join(PORTFOLIO_DIR, f"{typename}.json")
    with open(fpath, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, default=str)


def _load_raw(typename: str) -> str:
    """读取原始内容（字符串存储）"""
    fpath = os.path.join(PORTFOLIO_DIR, f"{typename}.json")
    if os.path.exists(fpath):
        with open(fpath, "r", encoding="utf-8") as f:
            return f.read()
    return ""


def _save_raw(typename: str, content: str):
    """保存原始内容（字符串存储）"""
    os.makedirs(PORTFOLIO_DIR, exist_ok=True)
    fpath = os.path.join(PORTFOLIO_DIR, f"{typename}.json")
    with open(fpath, "w", encoding="utf-8") as f:
        f.write(content)


@app.get("/api/portfolio/{ptype}")
async def get_portfolio(ptype: str, _=Depends(verify_token)):
    """获取投资组合/收益统计/交易记录"""
    valid_types = ["speed", "hot", "lite", "speed_portfolios", "hot_portfolios", "lite_portfolios",
                   "performance", "trading_day_records"]
    if ptype not in valid_types:
        raise HTTPException(status_code=400, detail=f"无效类型: {ptype}")

    if ptype.endswith("_portfolios"):
        data = _load_portfolio(ptype)
    elif ptype == "trading_day_records":
        data = _load_raw("trading_day_records")  # 存储的是原始JSON字符串
    elif ptype == "performance":
        # 返回 performance.json 的原始数据
        data = _load_portfolio("performance")
    else:
        data = _load_portfolio(f"{ptype}_portfolios")
    return {"type": ptype, "data": data if data else {}}


@app.post("/api/portfolio/{ptype}/sync")
async def sync_portfolio(ptype: str, request: Request, _=Depends(verify_token)):
    """同步数据到服务器（支持投资组合/收益统计/交易记录）"""
    valid_types = ["speed", "hot", "lite", "performance", "trading_day_records"]
    if ptype not in valid_types:
        raise HTTPException(status_code=400, detail=f"无效类型: {ptype}")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="请求体不是有效JSON")

    if ptype == "performance":
        # 收益统计：App 发送 {"data": "<JSON字符串>"}
        raw_str = body.get("data", "")
        if not raw_str:
            raise HTTPException(status_code=400, detail="缺少data字段")
        try:
            data = json.loads(raw_str) if isinstance(raw_str, str) else raw_str
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="data不是有效JSON")
        _save_portfolio("performance", data)
        return {"ok": True, "type": "performance", "synced_at": datetime.now().isoformat()}

    elif ptype == "trading_day_records":
        # 交易日记录：App 发送 {"data": "<JSON字符串>"}
        raw_str = body.get("data", "")
        if not raw_str:
            raise HTTPException(status_code=400, detail="缺少data字段")
        _save_raw("trading_day_records", raw_str if isinstance(raw_str, str) else json.dumps(raw_str))
        return {"ok": True, "type": "trading_day_records", "synced_at": datetime.now().isoformat()}

    else:
        # 投资组合
        data = body.get("data", body) if isinstance(body, dict) else body
        typename = f"{ptype}_portfolios"
        _save_portfolio(typename, data)
        return {
            "ok": True,
            "type": typename,
            "synced_at": datetime.now().isoformat(),
            "size": len(json.dumps(data, ensure_ascii=False)),
        }


@app.get("/api/portfolio/picks/latest")
async def latest_picks(_=Depends(verify_token)):
    """获取最新每日选股结果"""
    data = _load_portfolio("daily_picks")
    return {"picks": data}


@app.get("/api/portfolio/performance")
async def portfolio_performance(_=Depends(verify_token)):
    """获取收益统计"""
    data = _load_portfolio("performance")
    # 返回最近的统计数据
    sorted_keys = sorted(data.keys(), reverse=True)
    recent = {k: data[k] for k in sorted_keys[:30]}
    return {"performance": recent, "latest": data.get(sorted_keys[0]) if sorted_keys else None}


# ============================================================
# 市场数据 API
# ============================================================

@app.get("/api/market/hot-sectors")
async def hot_sectors(_=Depends(verify_token)):
    """今日热门板块"""
    sectors = await sina.fetch_hot_sectors()
    return {"sectors": sectors[:10], "count": min(len(sectors), 10)}


@app.get("/api/market/ranking")
async def market_ranking(count: int = 100, _=Depends(verify_token)):
    """A股涨幅排行"""
    stocks = await sina.fetch_sina_ranking(min(count, 500), "changepercent")
    return {"stocks": stocks, "count": len(stocks)}


# ============================================================
# 备份 API
# ============================================================

@app.post("/api/backup/upload")
async def backup_upload(
    data: str = Body(..., embed=True),
    filename: str = Body("backup.json", embed=True),
    _=Depends(verify_token),
):
    """上传备份数据到服务器"""
    backup_dir = os.environ.get("BACKUP_DIR", "/data/backups")
    os.makedirs(backup_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = os.path.join(backup_dir, f"{timestamp}_{filename}")
    try:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(data)
        return {"ok": True, "path": filepath, "size": len(data)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/backup/list")
async def backup_list(_=Depends(verify_token)):
    """列出服务器上的备份文件"""
    backup_dir = os.environ.get("BACKUP_DIR", "/data/backups")
    if not os.path.exists(backup_dir):
        return {"files": []}
    files = []
    for f in os.listdir(backup_dir):
        fpath = os.path.join(backup_dir, f)
        files.append({
            "name": f,
            "size": os.path.getsize(fpath),
            "mtime": datetime.fromtimestamp(os.path.getmtime(fpath)).isoformat(),
        })
    files.sort(key=lambda x: x["mtime"], reverse=True)
    return {"files": files}


@app.get("/api/backup/download/{filename}")
async def backup_download(filename: str, _=Depends(verify_token)):
    """下载备份文件"""
    backup_dir = os.environ.get("BACKUP_DIR", "/data/backups")
    filepath = os.path.join(backup_dir, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="文件不存在")
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
        return {"ok": True, "content": content, "filename": filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 事件钩子
# ============================================================

@app.on_event("shutdown")
async def shutdown():
    await sina.close()
    await tencent.close()
    await eastmoney.close()
    await news_svc.close()


# ============================================================
# 启动入口
# ============================================================

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    host = os.environ.get("HOST", "0.0.0.0")
    print(f"📈 蓝图极智AI选股后端启动: http://{host}:{port}")
    print(f"🔐 认证Token: {AUTH_TOKEN[:8]}...")
    print(f"📊 策略数: 8")
    print(f"📰 热点追踪: 已启用")
    print(f"💾 备份目录: {os.environ.get('BACKUP_DIR', '/data/backups')}")
    uvicorn.run("main:app", host=host, port=port, reload=False)
