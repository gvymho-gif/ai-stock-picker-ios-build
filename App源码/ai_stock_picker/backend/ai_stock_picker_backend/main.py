"""
FastAPI 主入口 - 蓝图极智AI选股后端服务
"""
import json
import os
import hashlib
import hmac
import time
from datetime import datetime, timedelta
from typing import Optional

from fastapi import FastAPI, HTTPException, Depends, Header, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from services.sina_finance import SinaFinanceService
from services.tencent_quote import TencentQuoteService
from services.eastmoney import EastMoneyService
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
engine = StrategyEngine(sina, tencent, eastmoney)

# ============================================================
# 配置
# ============================================================

# 从环境变量读取，部署时务必设置
AUTH_TOKEN = os.environ.get("AUTH_TOKEN", "blueprint_ai_stock_default_token")
DISABLE_AUTH = os.environ.get("DISABLE_AUTH", "false").lower() in ("true", "1")


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
    # 支持 Token 比较（生产环境应使用HMAC或数据库）
    if token == AUTH_TOKEN:
        return True
    # 也支持用户设置的Token（环境变量配置）
    user_token = os.environ.get("USER_AUTH_TOKEN", "")
    if user_token and token == user_token:
        return True
    raise HTTPException(status_code=403, detail="Token验证失败")


# ============================================================
# API 端点
# ============================================================

@app.get("/")
async def root():
    return {"name": "蓝图极智AI选股后端", "version": "1.0.0", "status": "running"}

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


@app.get("/api/health")
async def health_check():
    """健康检查"""
    return {"status": "ok", "time": datetime.now().isoformat()}


# ============================================================
# 市场数据 API（辅助接口）
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
# 备份 API（可选）
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


# ============================================================
# 启动入口
# ============================================================

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    host = os.environ.get("HOST", "0.0.0.0")
    print(f"📈 蓝图极智AI选股后端启动: http://{host}:{port}")
    print(f"🔐 认证Token: {AUTH_TOKEN[:8]}... (请在环境变量AUTH_TOKEN中修改)")
    print(f"📊 策略数: 8")
    print(f"💾 备份目录: {os.environ.get('BACKUP_DIR', '/data/backups')}")
    uvicorn.run("main:app", host=host, port=port, reload=False)
