"""
新浪财经行情数据获取服务
"""
import json
import re
from typing import Any, Optional

import httpx


class SinaFinanceService:
    """新浪财经行情数据获取"""

    def __init__(self):
        self._client = httpx.AsyncClient(timeout=20.0)
        self._headers = {
            "Referer": "https://finance.sina.com.cn",
            "User-Agent": "Mozilla/5.0 (Linux; Android 12)",
        }

    async def close(self):
        await self._client.aclose()

    @staticmethod
    def _safe_float(v: Any) -> float:
        if v is None:
            return 0.0
        try:
            return float(v)
        except (ValueError, TypeError):
            return 0.0

    async def fetch_sina_ranking(self, count: int = 200, sort_by: str = "changepercent") -> list[dict]:
        """获取A股涨幅排行"""
        url = (
            f"https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/"
            f"Market_Center.getHQNodeData?page=1&num={count}&sort={sort_by}&asc=0&node=hs_a"
        )
        try:
            resp = await self._client.get(url, headers=self._headers)
            if resp.status_code != 200 or not resp.text:
                return []
            data = resp.json()
            if not isinstance(data, list):
                return []

            result = []
            for item in data:
                sym = str(item.get("symbol", ""))
                code = sym.replace("sh", "").replace("sz", "")
                result.append({
                    "code": code,
                    "symbol": sym,
                    "name": str(item.get("name", "")),
                    "price": self._safe_float(item.get("trade")),
                    "change_pct": self._safe_float(item.get("changepercent")),
                    "volume": self._safe_float(item.get("volume")),
                    "amount": self._safe_float(item.get("turnover")),
                    "high": self._safe_float(item.get("high")),
                    "low": self._safe_float(item.get("low")),
                    "open": self._safe_float(item.get("open")),
                    "prev_close": self._safe_float(item.get("settlement")),
                    "turnoverratio": self._safe_float(item.get("turnoverratio")),
                    "mktcap": self._safe_float(item.get("mktcap")),
                    "nmc": self._safe_float(item.get("nmc")),
                    "per": self._safe_float(item.get("per")),
                })
            return [s for s in result if s["code"]]
        except Exception:
            return []

    async def fetch_sina_sector_stocks(self, node_code: str, limit: int = 40) -> list[dict]:
        """获取指定板块的股票列表"""
        url = (
            f"https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/"
            f"Market_Center.getHQNodeData?page=1&num={limit}&sort=changepercent&asc=0&node={node_code}"
        )
        try:
            resp = await self._client.get(url, headers=self._headers)
            if resp.status_code != 200 or not resp.text:
                return []
            data = resp.json()
            if not isinstance(data, list):
                return []
            result = []
            for item in data:
                sym = str(item.get("symbol", ""))
                code = sym.replace("sh", "").replace("sz", "")
                prefix = "SH" if sym.startswith("sh") else "SZ"
                result.append({
                    "code": code,
                    "symbol": sym,
                    "name": str(item.get("name", "")),
                    "price": self._safe_float(item.get("trade")),
                    "change_pct": self._safe_float(item.get("changepercent")),
                    "volume": self._safe_float(item.get("volume")),
                    "amount": self._safe_float(item.get("turnover")),
                    "high": self._safe_float(item.get("high")),
                    "low": self._safe_float(item.get("low")),
                    "open": self._safe_float(item.get("open")),
                    "prev_close": self._safe_float(item.get("settlement")),
                    "turnoverratio": self._safe_float(item.get("turnoverratio")),
                    "mktcap": self._safe_float(item.get("mktcap")),
                    "nmc": self._safe_float(item.get("nmc")),
                    "per": self._safe_float(item.get("per")),
                    "suffix": prefix,
                })
            return [s for s in result if s["code"]]
        except Exception:
            return []

    async def fetch_hot_sectors(self) -> list[dict]:
        """获取今日热门板块（涨幅排行）"""
        url = (
            "https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/"
            "Market_Center.getHQNodeData?page=1&num=30&sort=changepercent&asc=0&node=new_hy"
        )
        try:
            resp = await self._client.get(url, headers=self._headers)
            if resp.status_code != 200 or not resp.text:
                return []
            data = resp.json()
            if not isinstance(data, list):
                return []
            return [
                {"name": str(item.get("name", "")), "change_pct": self._safe_float(item.get("changepercent"))}
                for item in data
            ]
        except Exception:
            return []
