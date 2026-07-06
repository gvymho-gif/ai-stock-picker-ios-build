#!/usr/bin/env python3
"""
投资组合实时监控守护进程

交易时段 (9:30-11:30, 13:00-15:00) 每3秒检查：
1. 极速投资止盈止损
2. 热点投资止盈止损
3. 轻量投资止盈止损
4. 实时价格更新

非交易日自动休眠。
"""

import os
import sys
import json
import asyncio
import httpx
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

PORTFOLIO_DIR = Path("/root/backend/portfolios")
CHECK_INTERVAL = 3  # 秒

HOLIDAYS = {
    '2026-01-01','2026-02-16','2026-02-17','2026-02-18','2026-02-19','2026-02-20','2026-02-21','2026-02-22',
    '2026-04-04','2026-04-05','2026-04-06',
    '2026-05-01','2026-05-02','2026-05-03','2026-05-04','2026-05-05',
    '2026-06-19','2026-06-20','2026-06-21',
    '2026-09-25','2026-09-26','2026-09-27',
    '2026-10-01','2026-10-02','2026-10-03','2026-10-04','2026-10-05','2026-10-06','2026-10-07',
}

def is_trading_day(dt=None):
    if dt is None: dt = datetime.now()
    if dt.weekday() >= 5: return False
    return dt.strftime("%Y-%m-%d") not in HOLIDAYS

def is_trading_time():
    now = datetime.now()
    if not is_trading_day(now): return False
    mins = now.hour * 60 + now.minute
    return (570 <= mins <= 690) or (780 <= mins <= 900)  # 9:30-11:30, 13:00-15:00

def log(msg: str):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


class RealTimeMonitor:
    """实时价格监控与止盈止损引擎"""

    def __init__(self):
        PORTFOLIO_DIR.mkdir(parents=True, exist_ok=True)
        self._client = None
        self._last_perf_time = 0

    async def _get_client(self):
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=10)
        return self._client

    def _load(self, name: str) -> dict:
        p = PORTFOLIO_DIR / f"{name}_portfolios.json"
        if p.exists():
            try:
                return json.loads(p.read_text(encoding="utf-8"))
            except: pass
        return {"portfolios": []}

    def _save(self, name: str, data: dict):
        PORTFOLIO_DIR.mkdir(parents=True, exist_ok=True)
        with open(PORTFOLIO_DIR / f"{name}_portfolios.json", "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2, default=str)

    async def get_batch_prices(self, codes: list) -> dict:
        """批量获取实时行情"""
        if not codes: return {}
        unique_codes = list(dict.fromkeys(codes))
        batches = [unique_codes[i:i+40] for i in range(0, len(unique_codes), 40)]
        
        all_results = {}
        for batch in batches:
            qq_codes = ",".join(
                f"{'sh' if (c.startswith('6') or c.startswith('9')) else 'sz'}{c}" 
                for c in batch
            )
            try:
                client = await self._get_client()
                resp = await client.get(
                    f"https://qt.gtimg.cn/q={qq_codes}",
                    headers={"User-Agent": "Mozilla/5.0"}
                )
                if resp.status_code != 200: continue
                
                for line in resp.text.split(";"):
                    if "=" not in line: continue
                    m = re.search(r'="([^"]*)"', line)
                    if not m: continue
                    fields = m.group(1).split("~")
                    if len(fields) < 40: continue
                    
                    code_raw = line.split("=")[0].split("_")[-1]
                    code = code_raw[2:] if (code_raw.startswith("sh") or code_raw.startswith("sz")) else code_raw
                    
                    price = float(fields[3]) if fields[3] else 0
                    prev = float(fields[4]) if fields[4] else 0
                    high = float(fields[33]) if len(fields) > 33 and fields[33] else 0
                    low = float(fields[34]) if len(fields) > 34 and fields[34] else 0
                    chg = round((price - prev) / prev * 100, 2) if prev > 0 and price > 0 else 0
                    
                    all_results[code] = {
                        "code": code,
                        "name": fields[1],
                        "price": price,
                        "prev_close": prev,
                        "high": high,
                        "low": low,
                        "change_pct": chg,
                        "updated_at": datetime.now().isoformat(),
                    }
            except Exception as e:
                continue
        
        return all_results

    async def check_portfolio(self, ptype: str):
        """检查单个投资组合的止盈止损"""
        data = self._load(ptype)
        triggers = []
        codes_to_check = set()
        
        for pf in data.get("portfolios", []):
            if pf.get("status") not in ("active", "holding"): continue
            for pos in pf.get("positions", []):
                if pos.get("status") == "holding":
                    codes_to_check.add(pos["stockCode"])
        
        if not codes_to_check: return []
        
        prices = await self.get_batch_prices(list(codes_to_check))
        
        for pf in data.get("portfolios", []):
            if pf.get("status") not in ("active", "holding"): continue
            changed = False
            total_current = 0
            
            for pos in pf.get("positions", []):
                if pos.get("status") != "holding": continue
                code = pos["stockCode"]
                quote = prices.get(code, {})
                current_price = quote.get("price", 0)
                
                if current_price > 0:
                    pos["currentPrice"] = current_price
                    pos["changePct"] = quote.get("change_pct", 0)
                    pos["high"] = quote.get("high", 0)
                    pos["low"] = quote.get("low", 0)
                    total_current += current_price * pos.get("shares", 0)
                    changed = True
                
                buy_price = pos.get("buyPrice", 0)
                if buy_price <= 0 or current_price <= 0: continue
                
                change_pct = (current_price - buy_price) / buy_price
                
                # 止盈 (默认8%)
                stop_profit = pos.get("stopProfit", 0.08)
                if change_pct >= stop_profit:
                    pos["status"] = "take_profit"
                    pos["sellPrice"] = current_price
                    pos["sellTime"] = datetime.now().isoformat()
                    if "investedAmount" in pos and pos["investedAmount"] > 0:
                        pos["returnAmount"] = current_price * pos.get("shares", 0)
                        pos["returnRate"] = round(change_pct, 4)
                    triggers.append(f"🟢{ptype}:{pos['stockName']}({code})止盈+{change_pct*100:.1f}%")
                    changed = True
                    continue
                
                # 止损 (默认4%)
                stop_loss = -abs(pos.get("stopLoss", 0.04))
                if change_pct <= stop_loss:
                    pos["status"] = "stop_loss"
                    pos["sellPrice"] = current_price
                    pos["sellTime"] = datetime.now().isoformat()
                    if "investedAmount" in pos and pos["investedAmount"] > 0:
                        pos["returnAmount"] = current_price * pos.get("shares", 0)
                        pos["returnRate"] = round(change_pct, 4)
                    triggers.append(f"🔴{ptype}:{pos['stockName']}({code})止损{change_pct*100:.1f}%")
                    changed = True
            
            if changed:
                pf["totalCurrentValue"] = round(total_current, 2)
        
        if triggers or any(
            pf.get("status") in ("active", "holding") and any(
                pos.get("status") == "holding" and pos.get("changePct", 0) != 0
                for pos in pf.get("positions", [])
            )
            for pf in data.get("portfolios", [])
        ):
            self._save(ptype, data)
        
        return triggers

    async def run_cycle(self):
        """单次检查循环"""
        all_triggers = []
        
        for ptype in ["speed", "hot", "lite"]:
            try:
                triggers = await self.check_portfolio(ptype)
                all_triggers.extend(triggers)
            except Exception as e:
                log(f"  ⚠ {ptype}检查异常: {e}")
        
        if all_triggers:
            log(f"⚠️ 止盈止损触发: {'; '.join(all_triggers)}")
        
        # 每5分钟更新一次收益快照
        now = time.time()
        if now - self._last_perf_time > 300:
            self._last_perf_time = now
            try:
                await self._update_performance()
            except: pass
        
        return all_triggers

    async def _update_performance(self):
        """更新收益快照"""
        perf = {}
        today = datetime.now().strftime("%Y-%m-%d")
        
        total_invested = total_current = total_return = 0
        
        for ptype in ["speed", "hot", "lite"]:
            data = self._load(ptype)
            for pf in data.get("portfolios", []):
                if pf.get("status") == "settled":
                    total_return += pf.get("totalReturn", 0)
                elif pf.get("status") in ("active", "holding"):
                    total_invested += pf.get("totalInvested", 0)
                    cv = sum(
                        pos.get("currentPrice", 0) * pos.get("shares", 0)
                        for pos in pf.get("positions", [])
                        if pos.get("status") == "holding"
                    )
                    total_current += cv
        
        perf[today] = {
            "date": today,
            "totalInvested": round(total_invested, 2),
            "totalCurrentValue": round(total_current, 2),
            "totalSettledReturn": round(total_return, 2),
            "updatedAt": datetime.now().isoformat(),
        }
        
        p = PORTFOLIO_DIR / "performance.json"
        old = {}
        if p.exists():
            try: old = json.loads(p.read_text(encoding="utf-8"))
            except: pass
        old.update(perf)
        p.write_text(json.dumps(old, ensure_ascii=False, indent=2), encoding="utf-8")

    async def run(self):
        """主循环"""
        log("🚀 实时监控守护进程启动")
        log(f"   检查间隔: {CHECK_INTERVAL}秒")
        log(f"   数据目录: {PORTFOLIO_DIR}")
        
        cycle = 0
        while True:
            try:
                if is_trading_time():
                    if cycle % 20 == 0:
                        log(f"  📊 正在监控... (第{cycle}轮)")
                    
                    triggers = await self.run_cycle()
                    if triggers:
                        for t in triggers:
                            log(f"    {t}")
                else:
                    if cycle % 600 == 0:  # 每30分钟报一次
                        log(f"  💤 非交易时段，休眠中...")
                
                cycle += 1
                await asyncio.sleep(CHECK_INTERVAL)
                
            except Exception as e:
                log(f"  ❌ 循环异常: {e}")
                await asyncio.sleep(10)


async def main():
    monitor = RealTimeMonitor()
    await monitor.run()

if __name__ == "__main__":
    asyncio.run(main())
