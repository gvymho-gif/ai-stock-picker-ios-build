"""
东方财富F10财务数据服务
"""
from typing import Any

import httpx


class EastMoneyService:
    """东方财富F10财务数据接口"""

    def __init__(self):
        self._client = httpx.AsyncClient(timeout=15.0)

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

    async def fetch_financial_data(self, code: str) -> dict:
        """获取F10核心财务指标"""
        result = {
            "pe": 0.0, "peg": 999.0, "roe": 0.0, "gross_margin": 0.0,
            "debt_ratio": 100.0, "eps": 0.0, "revenue_growth": 0.0,
            "profit_growth": 0.0, "dividend_yield": 0.0, "interest_coverage": 0.0,
            "deduct_profit": 0.0, "deduct_profit_growth": 0.0,
        }

        headers = {"User-Agent": "Mozilla/5.0 (Linux; Android 12)"}

        # 主财务数据
        try:
            url = (
                f"https://datacenter.eastmoney.com/securities/api/data/get"
                f"?type=RPT_F10_FINANCE_MAINFINADATA"
                f"&sty=SECURITY_CODE,ROEJQ,BPS,EPSJB,TOTALOPERATEREVETZ,PARENTNETPROFITTZ,XSMLL,ZCFZL,KCFJCXSYJLR,DJD_DEDUCTDPNP_YOY"
                f"&filter=(SECURITY_CODE=%22{code}%22)&p=1&ps=1&sr=-1&st=REPORT_DATE&source=HSF10&client=PC"
            )
            resp = await self._client.get(url, headers=headers)
            if resp.status_code == 200 and resp.text:
                raw = resp.json()
                if isinstance(raw, dict) and raw.get("success") is True:
                    result_data = raw.get("result")
                    if isinstance(result_data, dict):
                        data_list = result_data.get("data")
                        if isinstance(data_list, list) and data_list:
                            item = data_list[0]
                            result["roe"] = self._safe_float(item.get("ROEJQ"))
                            result["eps"] = self._safe_float(item.get("EPSJB"))
                            result["revenue_growth"] = self._safe_float(item.get("TOTALOPERATEREVETZ"))
                            result["profit_growth"] = self._safe_float(item.get("PARENTNETPROFITTZ"))
                            result["gross_margin"] = self._safe_float(item.get("XSMLL"))
                            result["debt_ratio"] = self._safe_float(item.get("ZCFZL"))

                            deduct_yuan = self._safe_float(item.get("KCFJCXSYJLR"))
                            if deduct_yuan != 0:
                                result["deduct_profit"] = deduct_yuan / 10000
                            deduct_growth = self._safe_float(item.get("DJD_DEDUCTDPNP_YOY"))
                            if deduct_growth != 0:
                                result["deduct_profit_growth"] = deduct_growth

                            bps = self._safe_float(item.get("BPS"))
                            if bps > 0:
                                result["bps"] = bps
        except Exception:
            pass

        # 股息率
        try:
            div_url = (
                f"https://datacenter.eastmoney.com/securities/api/data/v1/get"
                f"?reportName=RPT_LICO_FN_CPD"
                f"&columns=SECURITY_CODE,ZXGXL"
                f"&filter=(SECURITY_CODE=%22{code}%22)"
                f"&pageSize=1&sortColumns=UPDATE_DATE&sortTypes=-1&source=HSF10&client=PC"
            )
            div_resp = await self._client.get(div_url, headers=headers)
            if div_resp.status_code == 200 and div_resp.text:
                div_raw = div_resp.json()
                if isinstance(div_raw, dict) and div_raw.get("success") is True:
                    div_result = div_raw.get("result")
                    if isinstance(div_result, dict):
                        div_data = div_result.get("data")
                        if isinstance(div_data, list) and div_data:
                            zxgxl = self._safe_float(div_data[0].get("ZXGXL"))
                            if zxgxl > 0:
                                result["dividend_yield"] = zxgxl
        except Exception:
            pass

        # 计算PEG
        pe = result["pe"]
        pg = result["profit_growth"]
        if pg > 0 and pe > 0:
            result["peg"] = pe / pg

        return result
