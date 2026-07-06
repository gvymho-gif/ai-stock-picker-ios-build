"""
腾讯行情API - 补充实时行情、PE、52周高低价等
"""
import re
from typing import Any

import httpx


class TencentQuoteService:
    """腾讯行情实时数据"""

    def __init__(self):
        self._client = httpx.AsyncClient(timeout=10.0)

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

    async def enrich_with_realtime(self, stocks: list[dict]) -> list[dict]:
        """批量补充实时行情（prev_close, 52周高低等）"""
        if not stocks:
            return stocks

        qq_codes = ",".join(s.get("symbol", "") for s in stocks if s.get("symbol"))
        if not qq_codes:
            return stocks

        try:
            resp = await self._client.get(
                f"https://qt.gtimg.cn/q={qq_codes}",
                headers={"User-Agent": "Mozilla/5.0"},
            )
            if resp.status_code != 200:
                return stocks

            text = resp.text
            lines = text.split(";")

            result = []
            for s in stocks:
                symbol = s.get("symbol", "")
                enriched = dict(s)
                for line in lines:
                    if f"{symbol}=" in line:
                        match = re.search(r'="([^"]*)"', line)
                        if match:
                            fields = match.group(1).split("~")
                            if len(fields) > 34:
                                enriched["price"] = self._safe_float(fields[3])
                                enriched["open"] = self._safe_float(fields[5])
                                enriched["high"] = self._safe_float(fields[33])
                                enriched["low"] = self._safe_float(fields[34])
                                enriched["prev_close"] = self._safe_float(fields[4])
                                enriched["volume"] = self._safe_float(fields[36])
                                enriched["amount"] = self._safe_float(fields[37]) * 10000
                                if len(fields) > 49:
                                    enriched["week52_high"] = self._safe_float(fields[48])
                                    enriched["week52_low"] = self._safe_float(fields[49])
                                if len(fields) > 39:
                                    enriched["pe_qq"] = self._safe_float(fields[39])
                        break
                result.append(enriched)
            return result
        except Exception:
            return stocks

    async def fetch_financial_data(self, code: str) -> dict:
        """获取PE等补充财务数据"""
        result = {}
        try:
            prefix = "sh" if (code.startswith("6") or code.startswith("9")) else "sz"
            resp = await self._client.get(
                f"https://qt.gtimg.cn/q={prefix}{code}",
                headers={"User-Agent": "Mozilla/5.0"},
            )
            if resp.status_code == 200:
                match = re.search(r'="([^"]*)"', resp.text)
                if match:
                    fields = match.group(1).split("~")
                    if len(fields) > 49:
                        result["pe"] = self._safe_float(fields[39])
                        result["pb"] = self._safe_float(fields[47])
                        result["price"] = self._safe_float(fields[3])
                    if len(fields) > 36:
                        result["amount"] = self._safe_float(fields[37]) * 10000
        except Exception:
            pass
        return result
