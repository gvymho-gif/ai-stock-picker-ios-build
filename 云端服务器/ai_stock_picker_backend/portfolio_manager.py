#!/usr/bin/env python3
"""
投资组合自动管理引擎

涵盖:
1. 极速投资 - T+1买入卖出
2. 热点投资 - 止盈止损  
3. 轻量投资 - 虚拟组合
4. 收益统计

数据存储在 /root/backend/portfolios/ 目录下JSON文件
"""

import os
import json
import asyncio
import httpx
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

PORTFOLIO_DIR = Path("/root/backend/portfolios")
API_BASE = os.environ.get("API_BASE", "http://127.0.0.1:8000")
AUTH_TOKEN = os.environ.get("AUTH_TOKEN", "blueprint_ai_stock_2026_123456")

# === 交易日判断 ===
HOLIDAYS_2026 = {
    '2026-01-01', '2026-02-16','2026-02-17','2026-02-18','2026-02-19','2026-02-20','2026-02-21','2026-02-22',
    '2026-04-04','2026-04-05','2026-04-06',
    '2026-05-01','2026-05-02','2026-05-03','2026-05-04','2026-05-05',
    '2026-06-19','2026-06-20','2026-06-21',
    '2026-09-25','2026-09-26','2026-09-27',
    '2026-10-01','2026-10-02','2026-10-03','2026-10-04','2026-10-05','2026-10-06','2026-10-07',
}

def is_trading_day(dt: datetime = None) -> bool:
    if dt is None:
        dt = datetime.now()
    if dt.weekday() >= 5:
        return False
    return dt.strftime("%Y-%m-%d") not in HOLIDAYS_2026

def is_trading_time() -> bool:
    now = datetime.now()
    if not is_trading_day(now):
        return False
    mins = now.hour * 60 + now.minute
    return (570 <= mins <= 690) or (780 <= mins <= 900)  # 9:30-11:30, 13:00-15:00

def today_str() -> str:
    return datetime.now().strftime("%Y-%m-%d")

def log(msg: str):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


class PortfolioManager:
    """投资组合管理器"""
    
    def __init__(self):
        PORTFOLIO_DIR.mkdir(parents=True, exist_ok=True)
        self._client = None
        
    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=30)
        return self._client

    def _load(self, name: str) -> dict:
        p = PORTFOLIO_DIR / f"{name}.json"
        if p.exists():
            return json.loads(p.read_text(encoding="utf-8"))
        return {}
    
    def _save(self, name: str, data: dict):
        PORTFOLIO_DIR.mkdir(parents=True, exist_ok=True)
        with open(PORTFOLIO_DIR / f"{name}.json", "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2, default=str)

    # === 行情获取 ===
    async def get_realtime_price(self, code: str) -> Optional[dict]:
        """获取单只股票实时行情"""
        try:
            client = await self._get_client()
            prefix = "sh" if (code.startswith("6") or code.startswith("9")) else "sz"
            resp = await client.get(f"https://qt.gtimg.cn/q={prefix}{code}", headers={"User-Agent": "Mozilla/5.0"})
            if resp.status_code != 200: return None
            
            import re
            match = re.search(r'="([^"]*)"', resp.text)
            if not match: return None
            
            fields = match.group(1).split("~")
            if len(fields) < 40: return None
            
            return {
                "code": code,
                "name": fields[1],
                "price": float(fields[3]) if fields[3] else 0,
                "prev_close": float(fields[4]) if fields[4] else 0,
                "open": float(fields[5]) if fields[5] else 0,
                "high": float(fields[33]) if len(fields) > 33 and fields[33] else 0,
                "low": float(fields[34]) if len(fields) > 34 and fields[34] else 0,
                "change_pct": 0,
            }
        except Exception as e:
            return None

    async def get_batch_prices(self, codes: list) -> dict:
        """批量获取行情"""
        if not codes: return {}
        qq_codes = ",".join(f"{'sh' if (c.startswith('6') or c.startswith('9')) else 'sz'}{c}" for c in codes)
        try:
            client = await self._get_client()
            resp = await client.get(f"https://qt.gtimg.cn/q={qq_codes}", headers={"User-Agent": "Mozilla/5.0"})
            if resp.status_code != 200: return {}
            
            import re
            result = {}
            for line in resp.text.split(";"):
                if "=" not in line: continue
                match = re.search(r'="([^"]*)"', line)
                if not match: continue
                fields = match.group(1).split("~")
                if len(fields) < 40: continue
                
                code_raw = line.split("=")[0].split("_")[-1]
                code = code_raw[2:] if code_raw.startswith("sh") or code_raw.startswith("sz") else code_raw
                
                price = float(fields[3]) if fields[3] else 0
                prev = float(fields[4]) if fields[4] else 0
                chg = ((price - prev) / prev * 100) if prev > 0 and price > 0 else 0
                
                result[code] = {
                    "code": code,
                    "name": fields[1],
                    "price": price,
                    "prev_close": prev,
                    "open": float(fields[5]) if fields[5] else 0,
                    "change_pct": round(chg, 2),
                    "high": float(fields[33]) if len(fields) > 33 and fields[33] else 0,
                    "low": float(fields[34]) if len(fields) > 34 and fields[34] else 0,
                }
            return result
        except Exception as e:
            return {}

    # === 极速投资 ===
    async def speed_activate_portfolios(self):
        """9:30 激活所有pending极速组合"""
        data = self._load("speed_portfolios")
        now = datetime.now()
        changed = False

        for pf in data.get("portfolios", []):
            if pf.get("status") != "pending": continue
            if pf.get("buyDate") != today_str(): continue
            
            # 获取开盘价
            codes = [p["stockCode"] for p in pf.get("positions", [])]
            prices = await self.get_batch_prices(codes)
            
            for pos in pf["positions"]:
                code = pos["stockCode"]
                quote = prices.get(code, {})
                buy_price = quote.get("open", quote.get("price", 0))
                
                if buy_price <= 0: 
                    log(f"  极速 {code} 开盘价缺失，跳过")
                    continue
                
                planned = pos.get("plannedAmount", 20000)
                shares = int(planned / buy_price / 100) * 100
                if shares < 100: shares = 100
                
                pos["buyPrice"] = buy_price
                pos["buyTime"] = now.isoformat()
                pos["shares"] = shares
                pos["investedAmount"] = round(buy_price * shares, 2)
                pos["status"] = "holding"
                log(f"  极速买入 {pos['stockName']}({code}) @{buy_price:.2f} x{shares}股")
            
            pf["status"] = "active"
            changed = True

        if changed:
            self._save("speed_portfolios", data)
            log("✅ 极速组合激活完成")

    async def speed_settle_portfolios(self):
        """15:05 结算当日到期极速组合"""
        data = self._load("speed_portfolios")
        now = datetime.now()
        changed = False
        
        for pf in data.get("portfolios", []):
            if pf.get("status") != "active": continue
            if pf.get("sellDate") != today_str(): continue
            
            codes = [p["stockCode"] for p in pf.get("positions", []) if p.get("status") == "holding"]
            prices = await self.get_batch_prices(codes)
            
            total_return = 0
            for pos in pf["positions"]:
                if pos.get("status") != "holding": continue
                code = pos["stockCode"]
                quote = prices.get(code, {})
                sell_price = quote.get("price", 0)
                
                if sell_price <= 0:
                    sell_price = pos.get("buyPrice", 0)
                
                invested = pos.get("investedAmount", 0)
                shares = pos.get("shares", 0)
                sell_total = round(sell_price * shares, 2)
                profit = round(sell_total - invested, 2)
                return_rate = round(profit / invested, 4) if invested > 0 else 0
                
                pos["sellPrice"] = sell_price
                pos["sellTime"] = now.isoformat()
                pos["returnAmount"] = profit  # ★ 修复：returnAmount 是利润，不是总金额
                pos["returnRate"] = return_rate
                pos["status"] = "settled"
                total_return += profit
                log(f"  极速卖出 {pos['stockName']}({code}) @{sell_price:.2f} 利润:¥{profit:.2f} ({return_rate*100:.2f}%)")
            
            pf["status"] = "settled"
            pf["totalReturn"] = round(total_return, 2)
            pf["returnRate"] = round(total_return / max(pf.get("totalInvested", total_return), 1), 4)
            changed = True
        
        if changed:
            self._save("speed_portfolios", data)
            log("✅ 极速组合结算完成")

    # === 止盈止损检查 ===
    async def check_stop_loss(self, portfolio_type: str):
        """检查止盈止损"""
        data = self._load(f"{portfolio_type}_portfolios")
        triggers = []
        
        for pf in data.get("portfolios", []):
            if pf.get("status") not in ("active", "holding"): continue
            
            codes = [p["stockCode"] for p in pf.get("positions", []) if p.get("status") == "holding"]
            prices = await self.get_batch_prices(codes)
            
            for pos in pf.get("positions", []):
                if pos.get("status") != "holding": continue
                code = pos["stockCode"]
                quote = prices.get(code, {})
                current_price = quote.get("price", 0)
                if current_price <= 0: continue
                
                buy_price = pos.get("buyPrice", 0)
                if buy_price <= 0: continue
                
                change_pct = (current_price - buy_price) / buy_price
                pos["currentPrice"] = current_price
                pos["changePct"] = round(change_pct * 100, 2)
                
                # 止盈：涨超8%
                stop_profit = pos.get("stopProfit", 0.08)
                if change_pct >= stop_profit:
                    log(f"  🟢 止盈触发 {pos['stockName']}({code}) +{change_pct*100:.1f}%")
                    pos["status"] = "take_profit"
                    pos["sellPrice"] = current_price
                    triggers.append(f"{portfolio_type}:{code}:止盈")
                    continue
                
                # 止损：跌破4%
                stop_loss = -abs(pos.get("stopLoss", 0.04))
                if change_pct <= stop_loss:
                    log(f"  🔴 止损触发 {pos['stockName']}({code}) {change_pct*100:.1f}%")
                    pos["status"] = "stop_loss"
                    pos["sellPrice"] = current_price
                    triggers.append(f"{portfolio_type}:{code}:止损")
        
        if triggers:
            self._save(f"{portfolio_type}_portfolios", data)
            log(f"⚠️ 止盈止损触发: {', '.join(triggers)}")
        
        return triggers

    # === 收益统计 ===
    async def calculate_performance(self):
        """计算并缓存收益统计数据"""
        perf = self._load("performance")
        today = today_str()
        
        if not is_trading_day():
            log("  今日非交易日，跳过收益计算")
            return
        
        # 汇总三种投资组合收益
        total_invested = 0
        total_current = 0
        total_return = 0
        
        for ptype in ["speed", "hot", "lite"]:
            data = self._load(f"{ptype}_portfolios")
            for pf in data.get("portfolios", []):
                if pf.get("status") == "settled":
                    total_return += pf.get("totalReturn", 0)
                elif pf.get("status") in ("active", "holding"):
                    total_invested += pf.get("totalInvested", 0)
                    # Get current values
                    current = pf.get("totalCurrentValue", 0)
                    if current == 0:
                        # Calculate from positions
                        current = sum(p.get("currentPrice", 0) * p.get("shares", 0) for p in pf.get("positions", []))
                    total_current += current
        
        perf[today] = {
            "date": today,
            "totalInvested": round(total_invested, 2),
            "totalCurrentValue": round(total_current, 2),
            "totalReturn": round(total_return, 2),
            "updatedAt": datetime.now().isoformat(),
        }
        
        self._save("performance", perf)
        log(f"  📊 收益统计: 投入{total_invested:.0f} 市值{total_current:.0f} 已结算{total_return:.0f}")
        return perf[today]

    # === 20:00 自动选股 ===
    async def auto_pick_stocks(self):
        """20:00 从策略结果中提取推荐股票"""
        log("🔍 20:00 自动提取选股结果...")
        
        picks = []
        # 运行锦鲤选股B获取深度分析结果
        try:
            client = await self._get_client()
            resp = await client.get(f"{API_BASE}/api/strategy/koi_picker_b", 
                headers={"Authorization": f"Bearer {AUTH_TOKEN}"}, timeout=180)
            if resp.status_code == 200:
                data = resp.json()
                for s in data.get("stocks", []):
                    picks.append({
                        "code": s.get("code"),
                        "name": s.get("name"),
                        "price": s.get("price", 0),
                        "change_pct": s.get("change_pct", 0),
                        "score": s.get("strategy_score", 0),
                        "source": "锦鲤选股B",
                    })
                log(f"  锦鲤选股B: {len(picks)}只")
        except Exception as e:
            log(f"  锦鲤选股B异常: {e}")
        
        # 也拉隔夜导航
        try:
            resp = await client.get(f"{API_BASE}/api/strategy/overnight_navigator",
                headers={"Authorization": f"Bearer {AUTH_TOKEN}"}, timeout=180)
            if resp.status_code == 200:
                data = resp.json()
                for s in data.get("stocks", [])[:3]:
                    picks.append({
                        "code": s.get("code"),
                        "name": s.get("name"),
                        "price": s.get("price", 0),
                        "change_pct": s.get("change_pct", 0),
                        "score": s.get("strategy_score", 0),
                        "source": "隔夜导航",
                    })
        except Exception as e:
            log(f"  隔夜导航异常: {e}")
        
        today_picks = {
            "date": today_str(),
            "picks": picks,
            "count": len(picks),
            "pickedAt": datetime.now().isoformat(),
        }
        self._save("daily_picks", today_picks)
        log(f"✅ 每日选股完成: {len(picks)}只")
        return today_picks


# === 命令行入口 ===
async def main():
    pm = PortfolioManager()
    import sys
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    
    if cmd == "activate":
        log("▶ 激活极速组合(buy)")
        await pm.speed_activate_portfolios()
    elif cmd == "settle":
        log("▶ 结算极速组合(sell)")
        await pm.speed_settle_portfolios()
    elif cmd == "check":
        log("▶ 止盈止损检查")
        await pm.check_stop_loss("hot")
        await pm.check_stop_loss("lite")
        await pm.check_stop_loss("speed")
    elif cmd == "perf":
        log("▶ 收益统计")
        await pm.calculate_performance()
    elif cmd == "pick":
        log("▶ 自动选股")
        await pm.auto_pick_stocks()
    elif cmd == "all":
        log("▶ 完整周期")
        if is_trading_time():
            await pm.check_stop_loss("hot")
            await pm.check_stop_loss("lite")
            await pm.check_stop_loss("speed")
            await pm.calculate_performance()
        else:
            log("  非交易时段，跳过止盈止损")
            await pm.calculate_performance()
    else:
        log("用法: python portfolio_manager.py [activate|settle|check|perf|pick|all]")

if __name__ == "__main__":
    asyncio.run(main())
