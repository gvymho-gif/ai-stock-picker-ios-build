#!/usr/bin/env python3
"""
蓝图极智AI选股 - 自动交易调度器
每个交易日在固定时间点自动执行对应策略，结果缓存供App秒开读取。
"""

import os
import sys
import json
import time
import asyncio
from datetime import datetime, timedelta
from pathlib import Path

# 配置
CACHE_DIR = os.environ.get("CACHE_DIR", "/root/backend/cache")
API_BASE = "http://127.0.0.1:8000"
AUTH_TOKEN = os.environ.get("AUTH_TOKEN", "blueprint_aistock_2026_123456")
HEADERS = {"Authorization": f"Bearer {AUTH_TOKEN}"}

# 2026年A股节假日
HOLIDAYS = {
    '2026-01-01',
    '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19',
    '2026-02-20', '2026-02-21', '2026-02-22',
    '2026-04-04', '2026-04-05', '2026-04-06',
    '2026-05-01', '2026-05-02', '2026-05-03', '2026-05-04', '2026-05-05',
    '2026-06-19', '2026-06-20', '2026-06-21',
    '2026-09-25', '2026-09-26', '2026-09-27',
    '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04',
    '2026-10-05', '2026-10-06', '2026-10-07',
}


def is_trading_day(dt: datetime) -> bool:
    """判断是否为A股交易日"""
    if dt.weekday() >= 5:  # 周末
        return False
    date_str = dt.strftime("%Y-%m-%d")
    return date_str not in HOLIDAYS


def log(msg: str):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


async def call_api(endpoint: str, timeout: int = 120) -> dict:
    """调用后端API获取数据"""
    import httpx
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            resp = await client.get(f"{API_BASE}{endpoint}", headers=HEADERS)
            if resp.status_code == 200:
                return resp.json()
            log(f"  API {endpoint} 返回 {resp.status_code}")
            return {}
        except Exception as e:
            log(f"  API {endpoint} 异常: {e}")
            return {}


def save_cache(name: str, data: dict):
    """保存缓存到文件"""
    os.makedirs(CACHE_DIR, exist_ok=True)
    data["cached_at"] = datetime.now().isoformat()
    data["cached_strategy"] = name
    path = os.path.join(CACHE_DIR, f"{name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    size = os.path.getsize(path)
    log(f"  [缓存] {name}.json ({size}B)")


async def run_strategy(strategy_id: str, cache_name: str):
    """执行单个策略并缓存结果"""
    log(f"▶ 执行 {cache_name}...")
    t0 = time.time()
    result = await call_api(f"/api/strategy/{strategy_id}", timeout=180)
    elapsed = time.time() - t0
    count = result.get("count", 0)
    log(f"  ✓ {cache_name} 完成 ({count}只, {elapsed:.1f}s)")
    if count > 0:
        save_cache(cache_name, result)


async def refresh_hot_track():
    """刷新热点追踪新闻"""
    log("▶ 刷新热点追踪...")
    result = await call_api("/api/hot-track/news", timeout=60)
    count = result.get("count", 0)
    log(f"  ✓ 热点追踪 完成 ({count}条)")
    if count > 0:
        save_cache("hot_track", result)


async def run_time_slot(slot_name: str):
    """执行一个时间段的策略组"""
    dt = datetime.now()
    if not is_trading_day(dt):
        log(f"✗ {slot_name} - 今日非交易日，跳过")
        return

    current_time = dt.strftime("%H:%M")
    log(f"═══ {slot_name} [{current_time}] ═══")

    tasks = get_tasks_for_slot(slot_name)
    for task in tasks:
        if isinstance(task, tuple):
            await run_strategy(task[0], task[1])
        else:
            await task()
    
    log(f"═══ {slot_name} 完成 ═══")


def get_tasks_for_slot(slot_name: str) -> list:
    """获取时间段对应的任务列表"""
    slots = {
        "open_prepare": [
            ("speed_assassin", "speed_assassin"),
            ("speed_assassin_b", "speed_assassin_b"),
        ],
        "open_hunt": [
            ("short_term_hunter", "short_term_hunter"),
            refresh_hot_track,
        ],
        "morning_pick": [
            ("koi_picker", "koi_picker"),
        ],
        "morning_growth": [
            ("growth_pioneer", "growth_pioneer"),
        ],
        "afternoon_open": [
            ("short_term_hunter", "short_term_hunter_afternoon"),
            refresh_hot_track,
        ],
        "afternoon_value": [
            ("stable_fortress", "stable_fortress"),
        ],
        "overnight_setup": [
            ("overnight_navigator", "overnight_navigator"),
        ],
        "close_eval": [
            ("koi_picker", "koi_picker_close"),
        ],
        "night_deep": [
            ("koi_picker_b", "koi_picker_b"),
        ],
    }
    return slots.get(slot_name, [])


async def main():
    """主入口 - 根据命令行参数执行对应时间段"""
    slot = sys.argv[1] if len(sys.argv) > 1 else "night_deep"
    
    try:
        await run_time_slot(slot)
    except Exception as e:
        log(f"✗ 调度异常: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())
