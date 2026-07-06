"""
选股策略引擎 - 全部8个策略的Python实现
"""
import math
from typing import Any

from services.sina_finance import SinaFinanceService
from services.tencent_quote import TencentQuoteService
from services.eastmoney import EastMoneyService


class StrategyEngine:
    """选股策略引擎"""

    def __init__(self, sina: SinaFinanceService, tencent: TencentQuoteService, eastmoney: EastMoneyService):
        self.sina = sina
        self.tencent = tencent
        self.eastmoney = eastmoney

    @staticmethod
    def _sf(v: Any) -> float:
        if v is None:
            return 0.0
        try:
            return float(v)
        except (ValueError, TypeError):
            return 0.0

    # ============================================================
    # 运行策略
    # ============================================================

    async def run_strategy(self, strategy_name: str) -> dict:
        """运行指定策略"""
        strategy_map = {
            "short_term_hunter": ("短炒猎手", "短线爆发策略", self._fetch_short_term_candidates),
            "growth_pioneer": ("成长先锋", "成长股策略", self._fetch_growth_candidates),
            "stable_fortress": ("稳健堡垒", "价值投资策略", self._fetch_stable_candidates),
            "speed_assassin": ("A股游资", "T+1极速博弈与情绪接力", self._fetch_hot_money_candidates),
            "speed_assassin_b": ("A股游资B", "游资策略+AI精选", self._fetch_hot_money_b_candidates),
            "overnight_navigator": ("隔夜导航", "盘后选股+早盘预埋策略", self._fetch_overnight_candidates),
            "koi_picker": ("锦鲤选股", "四因子融合选股", self._fetch_koi_candidates),
            "koi_picker_b": ("锦鲤选股B", "量化私募极智穿透分析", self._fetch_koi_b_candidates),
        }
        if strategy_name not in strategy_map:
            return {"strategy": strategy_name, "error": f"未知策略: {strategy_name}", "stocks": [], "count": 0}

        name, desc, fetcher = strategy_map[strategy_name]
        try:
            stocks = await fetcher()
            return {
                "strategy": name,
                "description": desc,
                "stocks": stocks,
                "count": len(stocks),
                "timestamp": __import__("datetime").datetime.now().isoformat(),
            }
        except Exception as e:
            return {
                "strategy": name, "description": desc,
                "stocks": [], "count": 0, "error": str(e),
            }

    # ============================================================
    # 一票否决库
    # ============================================================

    def _is_vetoed(self, stock: dict, fin: dict) -> bool:
        name = stock.get("name", "")
        sym = stock.get("symbol", "")
        if "ST" in name or "*ST" in name:
            return True
        if name.startswith("N") and len(name) < 6:
            return True
        if sym.startswith("bj"):
            return True
        sunset = ["钢铁", "煤炭", "水泥", "造纸", "玻纤", "氯碱", "纯碱", "PVC"]
        if any(kw in name for kw in sunset):
            return True
        price = self._sf(stock.get("price"))
        if 0 < price < 2.0:
            return True
        debt = self._sf(fin.get("debt_ratio"))
        if debt > 80:
            return True
        gm = self._sf(fin.get("gross_margin"))
        pg = self._sf(fin.get("profit_growth"))
        if gm > 0 and gm < 10 and pg < -30:
            return True
        return False

    # ============================================================
    # 策略一：短炒猎手
    # ============================================================

    async def _fetch_short_term_candidates(self) -> list[dict]:
        top = await self.sina.fetch_sina_ranking(200, "changepercent")
        if not top:
            return []

        # 预过滤
        candidates = []
        for s in top:
            sym = s.get("symbol", "")
            name = s.get("name", "")
            p = self._sf(s.get("price"))
            if "ST" in name or "*ST" in name:
                continue
            if name.startswith("N") and len(name) < 6:
                continue
            if sym.startswith("bj"):
                continue
            if 0 < p < 2:
                continue
            candidates.append(s)

        if not candidates:
            return []

        enriched = await self.tencent.enrich_with_realtime(candidates[:80])
        scored = []
        for s in enriched:
            score = self._score_short_term(s)
            if score > 0:
                s["strategy_score"] = score
                scored.append(s)
        scored.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        return scored[:10]

    def _score_short_term(self, d: dict) -> float:
        name = d.get("name", "")
        if "ST" in name or "*ST" in name:
            return 0
        if name.startswith("N"):
            return 0

        score = 0.0
        chg = self._sf(d.get("change_pct"))
        if chg > 9:
            score += 30
        elif chg > 7:
            score += 28
        elif chg > 5:
            score += 24
        elif chg > 3:
            score += 20
        elif chg > 2:
            score += 16
        elif chg > 1:
            score += 12
        elif chg > 0:
            score += 8

        amount = self._sf(d.get("amount"))
        if amount > 50e8:
            score += 25
        elif amount > 20e8:
            score += 22
        elif amount > 10e8:
            score += 18
        elif amount > 5e8:
            score += 14
        elif amount > 1e8:
            score += 8

        price = self._sf(d.get("price"))
        low = self._sf(d.get("low"))
        high = self._sf(d.get("high"))
        if low > 0 and high > low and price > 0:
            pos = (price - low) / (high - low)
            if 0.7 <= pos <= 0.98:
                score += 20
            elif pos >= 0.5:
                score += 14
            elif pos >= 0.3:
                score += 8

        if chg > 0:
            open_p = self._sf(d.get("open"))
            if open_p > 0 and price > open_p:
                body = (price - open_p) / open_p
                if body > 0.05:
                    score += 15
                elif body > 0.03:
                    score += 12
                elif body > 0.01:
                    score += 8
                else:
                    score += 4
            else:
                score += 4

        score += 10
        return score

    # ============================================================
    # 策略二：成长先锋
    # ============================================================

    async def _fetch_growth_candidates(self) -> list[dict]:
        sectors = ["new_dzxx", "new_swzz", "new_ylqx", "new_jxhy", "new_hghy"]
        futures = [self.sina.fetch_sina_sector_stocks(s) for s in sectors]
        results = await __import__("asyncio").gather(*futures, return_exceptions=True)
        all_stocks = []
        for r in results:
            if isinstance(r, list):
                all_stocks.extend(r)

        if not all_stocks:
            return []
        all_stocks.sort(key=lambda x: -self._sf(x.get("change_pct")))
        candidates = all_stocks[:60]

        scored = []
        for s in candidates:
            code = s.get("code", "")
            if not code:
                continue
            try:
                fin = await self.eastmoney.fetch_financial_data(code)
                score = self._score_growth(s, fin)
                if score > 0:
                    s["strategy_score"] = score
                    s.update({k: fin.get(k) for k in ("pe", "peg", "revenue_growth", "profit_growth",
                                                       "gross_margin", "debt_ratio", "roe")})
                    s["growth_logic"] = self._build_growth_logic(fin)
                    scored.append(s)
            except Exception:
                continue

        scored.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        return scored[:10]

    def _score_growth(self, stock: dict, fin: dict) -> float:
        name = stock.get("name", "")
        if "ST" in name or "*ST" in name:
            return 0
        score = 0.0
        peg = self._sf(fin.get("peg"))
        if 0 < peg < 0.5:
            score += 30
        elif 0.5 <= peg < 1.0:
            score += 25
        elif 1.0 <= peg < 1.5:
            score += 12

        pg = self._sf(fin.get("profit_growth"))
        if 20 <= pg <= 40:
            score += 25
        elif 40 < pg <= 80:
            score += 18
        elif 10 <= pg < 20:
            score += 12
        elif 0 < pg < 10:
            score += 5

        gm = self._sf(fin.get("gross_margin"))
        if gm > 50:
            score += 20
        elif gm > 35:
            score += 16
        elif gm > 20:
            score += 10
        elif gm > 10:
            score += 4

        roe = self._sf(fin.get("roe"))
        if roe >= 20:
            score += 15
        elif roe >= 15:
            score += 11
        elif roe >= 10:
            score += 6
        elif roe >= 5:
            score += 2

        dr = self._sf(fin.get("debt_ratio"))
        if dr < 30:
            score += 10
        elif dr < 45:
            score += 7
        elif dr < 65:
            score += 4
        elif dr < 80:
            score += 1

        return score

    def _build_growth_logic(self, fin: dict) -> str:
        parts = []
        peg = self._sf(fin.get("peg"))
        if 0 < peg < 1.0:
            parts.append(f"PEG={peg:.2f}<1，估值具有安全边际")
        elif 1.0 <= peg < 1.5:
            parts.append(f"PEG={peg:.2f}，估值基本合理")
        pg = self._sf(fin.get("profit_growth"))
        if 20 <= pg <= 40:
            parts.append(f"净利润增速{pg:.1f}%处于黄金区间")
        elif pg > 40:
            parts.append(f"净利润增速{pg:.1f}%，需警惕真实性")
        elif pg > 0:
            parts.append(f"净利润增速{pg:.1f}%")
        gm = self._sf(fin.get("gross_margin"))
        if gm > 40:
            parts.append(f"毛利率{gm:.1f}%体现强护城河")
        elif gm > 20:
            parts.append(f"毛利率{gm:.1f}%，具备行业壁垒")
        dr = self._sf(fin.get("debt_ratio"))
        if dr < 40:
            parts.append(f"负债率{dr:.1f}%，财务稳健")
        roe = self._sf(fin.get("roe"))
        if roe > 15:
            parts.append(f"ROE={roe:.1f}%，资本效率优秀")
        return "；".join(parts) if parts else "数据采集中..."

    # ============================================================
    # 策略三：稳健堡垒
    # ============================================================

    async def _fetch_stable_candidates(self) -> list[dict]:
        sectors = ["new_jrhy", "new_ljhy", "new_dlhy", "new_fdc", "new_syhy", "new_qczz"]
        futures = [self.sina.fetch_sina_sector_stocks(s) for s in sectors]
        results = await __import__("asyncio").gather(*futures, return_exceptions=True)
        all_stocks = []
        for r in results:
            if isinstance(r, list):
                all_stocks.extend(r)

        if not all_stocks:
            return []
        all_stocks.sort(key=lambda x: -self._sf(x.get("amount")))
        candidates = all_stocks[:70]

        scored = []
        for s in candidates:
            code = s.get("code", "")
            if not code:
                continue
            try:
                fin = await self.eastmoney.fetch_financial_data(code)
                score = self._score_stable(s, fin)
                if score > 0:
                    s["strategy_score"] = score
                    s.update({k: fin.get(k) for k in ("pe", "roe", "dividend_yield", "debt_ratio",
                                                       "interest_coverage", "gross_margin")})
                    s["stable_logic"] = self._build_stable_logic(fin)
                    scored.append(s)
            except Exception:
                continue

        scored.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        return scored[:10]

    def _score_stable(self, stock: dict, fin: dict) -> float:
        name = stock.get("name", "")
        if "ST" in name or "*ST" in name:
            return 0
        score = 0.0
        roe = self._sf(fin.get("roe"))
        if roe >= 22:
            score += 30
        elif roe >= 17:
            score += 24
        elif roe >= 12:
            score += 16
        elif roe >= 8:
            score += 8
        elif roe >= 4:
            score += 3

        dy = self._sf(fin.get("dividend_yield"))
        if dy >= 5.0:
            score += 25
        elif dy >= 3.5:
            score += 20
        elif dy >= 2.0:
            score += 12
        elif dy >= 1.0:
            score += 5

        pe = self._sf(fin.get("pe"))
        if 0 < pe < 8:
            score += 20
        elif 8 <= pe < 12:
            score += 16
        elif 12 <= pe < 18:
            score += 10
        elif 18 <= pe < 25:
            score += 4

        ic = self._sf(fin.get("interest_coverage"))
        if ic >= 10:
            score += 15
        elif ic >= 5:
            score += 12
        elif ic >= 3:
            score += 7
        elif ic > 0:
            score += 3

        dr = self._sf(fin.get("debt_ratio"))
        if dr < 30:
            score += 10
        elif dr < 45:
            score += 7
        elif dr < 60:
            score += 4
        elif dr < 75:
            score += 1

        return score

    def _build_stable_logic(self, fin: dict) -> str:
        parts = []
        roe = self._sf(fin.get("roe"))
        if roe >= 15:
            parts.append(f"ROE={roe:.1f}%，持续高回报")
        dy = self._sf(fin.get("dividend_yield"))
        if dy >= 3.5:
            parts.append(f"股息率{dy:.1f}%，分红丰厚")
        elif dy > 0:
            parts.append(f"股息率{dy:.1f}%")
        pe = self._sf(fin.get("pe"))
        if 0 < pe < 15:
            parts.append(f"PE={pe:.1f}处于低位")
        dr = self._sf(fin.get("debt_ratio"))
        if dr < 40:
            parts.append(f"负债率{dr:.1f}%，安全垫充足")
        return "；".join(parts) if parts else "数据采集中..."

    # ============================================================
    # 策略四：A股游资
    # ============================================================

    async def _fetch_hot_money_candidates(self) -> list[dict]:
        top = await self.sina.fetch_sina_ranking(300, "changepercent")
        if not top:
            return []

        candidates = []
        for s in top:
            sym = s.get("symbol", "")
            name = s.get("name", "")
            p = self._sf(s.get("price"))
            if "ST" in name or "*ST" in name:
                continue
            if name.startswith("N") and len(name) < 6:
                continue
            if sym.startswith("bj"):
                continue
            if 0 < p < 3:
                continue
            candidates.append(s)

        strategy_a = [dict(s) for s in candidates if self._sf(s.get("change_pct")) >= 7.0]
        strategy_b = [dict(s) for s in candidates if 2.0 <= self._sf(s.get("change_pct")) <= 6.0
                      and self._sf(s.get("turnoverratio")) > 2.0]

        all_candidates = strategy_a + strategy_b
        if not all_candidates:
            return []

        enriched = await self.tencent.enrich_with_realtime(all_candidates[:80])

        scored = []
        for s in enriched:
            scored_item = self._score_hot_money(s)
            if self._sf(scored_item.get("strategy_score")) > 0:
                scored.append(scored_item)

        scored.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        top5 = scored[:5]

        for s in top5:
            price = self._sf(s.get("price"))
            chg = self._sf(s.get("change_pct"))
            is_a = chg >= 7.0
            s["strategy_type"] = "打板确认" if is_a else "尾盘潜伏"
            exp_high_pct = 3.0 if is_a else 2.5
            s["next_day_high"] = round(price * (1 + exp_high_pct / 100), 2)
            s["next_day_high_pct"] = exp_high_pct
            stop_pct = 4.0 if is_a else 4.5
            s["stop_price"] = round(price * (1 - stop_pct / 100), 2)
            s["stop_pct"] = stop_pct
            prev_close = self._sf(s.get("prev_close"))
            if is_a and prev_close > 0:
                s["entry_price"] = round(prev_close * 1.10, 2)
                s["entry_note"] = "涨停板排队价"
            else:
                s["entry_price"] = price
                s["entry_note"] = "尾盘14:30-14:50确认买入"
            s["hot_money_logic"] = self._build_hot_money_logic(s)

        return top5

    def _score_hot_money(self, s: dict) -> dict:
        name = s.get("name", "")
        if "ST" in name or "*ST" in name:
            return s
        if name.startswith("N"):
            return s

        score = 0.0
        chg = self._sf(s.get("change_pct"))
        turnover = self._sf(s.get("turnoverratio"))
        amount = self._sf(s.get("amount"))
        mktcap = self._sf(s.get("mktcap"))
        price = self._sf(s.get("price"))
        volume = self._sf(s.get("volume"))
        is_a = chg >= 7.0

        if is_a:
            if chg >= 9.9:
                score += 30
            elif chg >= 9.0:
                score += 25
            elif chg >= 8.0:
                score += 18
            elif chg >= 7.0:
                score += 10
            if amount > 20e8:
                score += 25
            elif amount > 10e8:
                score += 20
            elif amount > 5e8:
                score += 15
            elif amount > 2e8:
                score += 10
            else:
                score += 5
            if turnover > 15:
                score += 20
            elif turnover > 10:
                score += 16
            elif turnover > 5:
                score += 10
            else:
                score += 4
            if 0 < mktcap < 20e4:
                score += 15
            elif 20e4 <= mktcap < 50e4:
                score += 12
            elif 50e4 <= mktcap < 100e4:
                score += 8
            else:
                score += 3
            if volume > 500000:
                score += 10
            elif volume > 200000:
                score += 7
            else:
                score += 3
        else:
            if 4.0 <= chg <= 6.0:
                score += 30
            elif 3.0 <= chg < 4.0:
                score += 24
            elif 2.0 <= chg < 3.0:
                score += 16
            if 3.0 <= turnover <= 8.0:
                score += 25
            elif 8.0 < turnover <= 15.0:
                score += 18
            elif turnover > 2.0:
                score += 12
            else:
                score += 5
            if amount > 10e8:
                score += 20
            elif amount > 5e8:
                score += 15
            elif amount > 2e8:
                score += 10
            else:
                score += 5
            if 0 < mktcap < 30e4:
                score += 15
            elif 30e4 <= mktcap < 80e4:
                score += 12
            elif 80e4 <= mktcap < 200e4:
                score += 8
            else:
                score += 3
            if 0 < price < 15:
                score += 10
            elif 15 <= price < 30:
                score += 7
            else:
                score += 3

        result = dict(s)
        result["strategy_score"] = score
        return result

    def _build_hot_money_logic(self, d: dict) -> str:
        parts = []
        is_a = d.get("strategy_type") == "打板确认"
        chg = self._sf(d.get("change_pct"))
        turnover = self._sf(d.get("turnoverratio"))
        mktcap = self._sf(d.get("mktcap"))

        if is_a:
            if chg >= 9.9:
                parts.append("【打板确认】已封死涨停，一致性预期极强")
            else:
                parts.append(f"【打板确认】涨幅{chg:.1f}%，即将触板")
        else:
            parts.append(f"【尾盘潜伏】温和上涨{chg:.1f}%，量价配合健康")

        if turnover > 10:
            parts.append(f"换手{turnover:.1f}%极度活跃")
        elif turnover > 5:
            parts.append(f"换手{turnover:.1f}%资金积极")

        if mktcap > 0:
            cap_yi = mktcap / 10000
            if cap_yi < 30:
                parts.append(f"流通盘{cap_yi:.0f}亿弹性极大")
            elif cap_yi < 80:
                parts.append(f"流通盘{cap_yi:.0f}亿")

        ndh = self._sf(d.get("next_day_high"))
        ndp = self._sf(d.get("next_day_high_pct"))
        sp = self._sf(d.get("stop_price"))
        spct = self._sf(d.get("stop_pct"))
        parts.append(f"次日预期高点{ndh:.2f}(+{ndp:.1f}%)")
        parts.append(f"止损红线{sp:.2f}(-{spct:.1f}%)")

        if is_a:
            parts.append("T+1开盘半小时内决断，破止损红线无条件离场")
        else:
            parts.append("T+1早盘若低开或上攻乏力，立刻市价卖出")

        return "；".join(parts)

    # ============================================================
    # 策略四B：A股游资B
    # ============================================================

    async def _fetch_hot_money_b_candidates(self) -> list[dict]:
        candidates = await self._fetch_hot_money_candidates()
        if not candidates:
            return []
        candidates.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        top5 = candidates[:5]
        for s in top5:
            if not s.get("strategy_type"):
                s["strategy_type"] = "本地游资"
            if not s.get("ai_analysis_text"):
                s["ai_analysis_text"] = "云端AI分析请使用App端AI模型配置"
        return top5

    # ============================================================
    # 策略五：隔夜导航
    # ============================================================

    async def _fetch_overnight_candidates(self) -> list[dict]:
        top = await self.sina.fetch_sina_ranking(500, "changepercent")
        if not top:
            return []

        hot_sectors = await self.sina.fetch_hot_sectors()
        hot_names = [s.get("name", "") for s in hot_sectors[:3]]

        candidates = []
        for s in top:
            chg = self._sf(s.get("change_pct"))
            sym = s.get("symbol", "")
            name = s.get("name", "")
            p = self._sf(s.get("price"))
            if chg < 5.0:
                continue
            if "ST" in name or "*ST" in name:
                continue
            if name.startswith("N") and len(name) < 6:
                continue
            if sym.startswith("bj"):
                continue
            if 0 < p < 3:
                continue
            candidates.append(s)

        candidates = [s for s in candidates
                      if 1.0 <= self._sf(s.get("turnoverratio")) <= 50.0]
        if not candidates:
            return []

        enriched = await self.tencent.enrich_with_realtime(candidates[:80])

        scored = []
        for s in enriched:
            scored_item = self._score_overnight(s, hot_names)
            if self._sf(scored_item.get("strategy_score")) > 0:
                scored.append(scored_item)

        scored.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        top5 = scored[:5]

        for s in top5:
            price = self._sf(s.get("price"))
            chg = self._sf(s.get("change_pct"))
            prev_close = self._sf(s.get("prev_close"))
            is_limit = chg >= 9.9
            s["pattern_type"] = "首板涨停" if is_limit else "底部突破"
            s["buy_price_aggressive"] = round(price * 1.02, 2)
            s["buy_price_stable"] = round(price * 1.00, 2)
            s["buy_price_model"] = round(price * 1.015, 2)
            target_pct = chg * 0.5
            s["target_sell_price"] = round(s["buy_price_model"] * (1 + target_pct / 100), 2)
            s["target_sell_pct"] = round(target_pct, 1)
            s["target_sell_standard"] = round(s["buy_price_model"] * 1.04, 2)
            s["stop_price"] = round(s["buy_price_model"] * 0.96, 2)
            s["stop_pct"] = 4.0
            wk52 = self._sf(s.get("week52_high"))
            if wk52 > 0 and s["target_sell_standard"] > wk52 * 0.98:
                s["target_sell_price"] = round(wk52 * 0.98, 2)
                s["pressure_adjusted"] = True
            else:
                s["pressure_adjusted"] = False
            s["sell_time_advice"] = "T+2日上午10:30前未达止盈价，10:30-11:30分批卖出"
            if is_limit:
                turnover = self._sf(s.get("turnoverratio"))
                if turnover <= 5.0:
                    s["seal_strength"] = "强"
                elif turnover <= 8.0:
                    s["seal_strength"] = "中"
                else:
                    s["seal_strength"] = "弱"
            else:
                s["seal_strength"] = "--"
            sec_name = s.get("sector_name", "")
            s["in_hot_sector"] = any(h in sec_name or sec_name in h for h in hot_names)
            s["overnight_logic"] = self._build_overnight_logic(s)

        return top5

    def _score_overnight(self, s: dict, hot_names: list[str]) -> dict:
        name = s.get("name", "")
        if "ST" in name or "*ST" in name:
            return s
        if name.startswith("N"):
            return s
        score = 0.0
        chg = self._sf(s.get("change_pct"))
        turnover = self._sf(s.get("turnoverratio"))
        amount = self._sf(s.get("amount"))
        mktcap = self._sf(s.get("mktcap"))

        if chg >= 9.9:
            score += 30
        elif chg >= 9.0:
            score += 25
        elif chg >= 7.0:
            score += 20
        elif chg >= 5.0:
            score += 12
        else:
            score += 5

        if 3.0 <= turnover <= 10.0:
            score += 20
        elif 10.0 < turnover <= 20.0:
            score += 15
        elif 20.0 < turnover <= 35.0:
            score += 10
        else:
            score += 5

        if chg >= 9.9:
            if turnover <= 5.0:
                score += 20
            elif turnover <= 7.0:
                score += 15
            elif turnover <= 10.0:
                score += 10
            else:
                score += 5
        else:
            if amount > 10e8:
                score += 20
            elif amount > 5e8:
                score += 15
            elif amount > 2e8:
                score += 10
            else:
                score += 5

        sec_name = s.get("sector_name", "")
        if any(h in sec_name or sec_name in h for h in hot_names):
            score += 15
        else:
            score += 3

        if 0 < mktcap < 50e4:
            score += 15
        elif 50e4 <= mktcap < 100e4:
            score += 10
        else:
            score += 5

        result = dict(s)
        result["strategy_score"] = score
        return result

    def _build_overnight_logic(self, d: dict) -> str:
        parts = []
        parts.append(f"【{d.get('pattern_type', '底部突破')}】")
        parts.append(f"今日涨{self._sf(d.get('change_pct')):.1f}%")
        parts.append(f"换手{self._sf(d.get('turnoverratio')):.1f}%")
        ss = d.get("seal_strength", "--")
        if ss != "--":
            parts.append(f"封单强度{ss}")
        parts.append(f"买入参考：激进{self._sf(d.get('buy_price_aggressive')):.2f}/稳健{self._sf(d.get('buy_price_stable')):.2f}")
        parts.append(f"止盈{self._sf(d.get('target_sell_price')):.2f}(+{self._sf(d.get('target_sell_pct')):.1f}%)")
        parts.append(f"止损{self._sf(d.get('stop_price')):.2f}(-4.0%)")
        if d.get("pressure_adjusted"):
            parts.append("目标价已因压力位下调")
        parts.append("T+1早盘9:15前限价委托，T+2上午10:30未达标则分批离场")
        return "；".join(parts)

    # ============================================================
    # 策略六：锦鲤选股
    # ============================================================

    async def _fetch_koi_candidates(self) -> list[dict]:
        top = await self.sina.fetch_sina_ranking(500, "changepercent")
        if not top:
            return []

        hot_sectors = await self.sina.fetch_hot_sectors()
        hot_names = [s.get("name", "") for s in hot_sectors[:5]]

        candidates = []
        for s in top:
            sym = s.get("symbol", "")
            name = s.get("name", "")
            chg = self._sf(s.get("change_pct"))
            if "ST" in name or "*ST" in name:
                continue
            if name.startswith("N") and len(name) < 6:
                continue
            if sym.startswith("bj"):
                continue
            if chg < 0:
                continue
            candidates.append(dict(s))

        if not candidates:
            return []

        enriched = await self.tencent.enrich_with_realtime(candidates[:100])

        passed = []
        for s in enriched:
            code = s.get("code", "")
            if not code:
                continue
            try:
                fin = await self.eastmoney.fetch_financial_data(code)
                if self._is_vetoed(s, fin):
                    continue
                pg = self._sf(fin.get("profit_growth"))
                rev = self._sf(fin.get("revenue_growth"))
                debt = self._sf(fin.get("debt_ratio"))
                roe = self._sf(fin.get("roe"))
                if (pg > 10 or rev > 15) and debt < 70 and roe > 5:
                    s["financials"] = fin
                    passed.append(s)
            except Exception:
                continue

        if not passed:
            return []

        scored = []
        for s in passed:
            scored_item = await self._score_koi(s, hot_names)
            if self._sf(scored_item.get("strategy_score")) > 0:
                scored.append(scored_item)

        scored.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        top15 = scored[:15]

        for s in top15:
            s["koi_logic"] = self._build_koi_logic(s)
            s["ai_analysis_text"] = "AI深度分析请使用App端AI模型配置"
            s["ai_score"] = 0
            s["local_score"] = self._sf(s.get("strategy_score"))

        return top15[:10]

    async def _score_koi(self, s: dict, hot_names: list[str]) -> dict:
        capital_score = 0.0
        trend_score = 0.0
        fundamental_score = 0.0
        event_score = 0.0

        chg = self._sf(s.get("change_pct"))
        turnover = self._sf(s.get("turnoverratio"))
        amount = self._sf(s.get("amount"))
        mktcap = self._sf(s.get("mktcap"))
        price = self._sf(s.get("price"))

        if amount > 30e8:
            capital_score += 30
        elif amount > 15e8:
            capital_score += 25
        elif amount > 8e8:
            capital_score += 20
        elif amount > 3e8:
            capital_score += 14
        elif amount > 1e8:
            capital_score += 8
        else:
            capital_score += 3

        if 5 <= turnover <= 15:
            capital_score += 10
        elif 15 < turnover <= 25:
            capital_score += 7
        elif turnover >= 3:
            capital_score += 4

        if chg >= 9.5:
            trend_score += 25
        elif chg >= 7.0:
            trend_score += 22
        elif chg >= 5.0:
            trend_score += 18
        elif chg >= 3.0:
            trend_score += 12
        elif chg >= 1.0:
            trend_score += 6
        else:
            trend_score += 2

        high = self._sf(s.get("high"))
        low = self._sf(s.get("low"))
        if high > low and price > 0:
            pos = (price - low) / (high - low)
            if pos >= 0.7:
                trend_score += 10
            elif pos >= 0.5:
                trend_score += 6

        fin = s.get("financials", {})
        roe = self._sf(fin.get("roe"))
        peg = self._sf(fin.get("peg"))
        gm = self._sf(fin.get("gross_margin"))
        pg = self._sf(fin.get("profit_growth"))
        rev = self._sf(fin.get("revenue_growth"))

        if roe >= 20:
            fundamental_score += 10
        elif roe >= 15:
            fundamental_score += 8
        elif roe >= 10:
            fundamental_score += 5
        else:
            fundamental_score += 2

        if 0 < peg < 0.8:
            fundamental_score += 8
        elif 0.8 <= peg < 1.2:
            fundamental_score += 6
        elif 1.2 <= peg < 2.0:
            fundamental_score += 3

        if gm > 40:
            fundamental_score += 4
        elif gm > 25:
            fundamental_score += 3
        elif gm > 15:
            fundamental_score += 1

        avg_growth = (pg + rev) / 2
        if avg_growth > 50:
            fundamental_score += 3
        elif avg_growth > 30:
            fundamental_score += 2
        elif avg_growth > 15:
            fundamental_score += 1

        sec_name = s.get("sector_name", "")
        in_hot = any(h in sec_name or sec_name in h for h in hot_names)
        if in_hot:
            event_score += 15
        else:
            event_score += 3

        cap_yi = mktcap / 10000
        if cap_yi < 30:
            event_score += 5
        elif cap_yi < 80:
            event_score += 3
        else:
            event_score += 1

        total = capital_score * 0.30 + trend_score * 0.25 + fundamental_score * 0.25 + event_score * 0.20

        result = dict(s)
        result["strategy_score"] = total
        result["capital_score"] = capital_score
        result["trend_score"] = trend_score
        result["fundamental_score"] = fundamental_score
        result["event_score"] = event_score
        return result

    def _build_koi_logic(self, d: dict) -> str:
        parts = []
        total = self._sf(d.get("strategy_score"))
        cap = self._sf(d.get("capital_score"))
        trend = self._sf(d.get("trend_score"))
        fund = self._sf(d.get("fundamental_score"))
        evt = self._sf(d.get("event_score"))
        parts.append(f"综合{total:.0f}分(资金{cap:.0f}+趋势{trend:.0f}+基本面{fund:.0f}+事件{evt:.0f})")
        chg = self._sf(d.get("change_pct"))
        parts.append(f"今日涨{chg:.1f}%")
        turnover = self._sf(d.get("turnoverratio"))
        parts.append(f"换手{turnover:.1f}%")
        amount = self._sf(d.get("amount"))
        if amount > 10e8:
            parts.append(f"成交{amount/1e8:.1f}亿资金热捧")
        mktcap = self._sf(d.get("mktcap"))
        cap_yi = mktcap / 10000
        if cap_yi < 50:
            parts.append(f"流通盘{cap_yi:.0f}亿弹性佳")
        fin = d.get("financials", {})
        roe = self._sf(fin.get("roe"))
        if roe > 15:
            parts.append(f"ROE{roe:.1f}%")
        peg = self._sf(fin.get("peg"))
        if 0 < peg < 1.5:
            parts.append(f"PEG{peg:.2f}")
        pg = self._sf(fin.get("profit_growth"))
        if pg > 20:
            parts.append(f"净利增{pg:.0f}%")
        if total >= 70:
            parts.append("【五星级锦鲤】")
        elif total >= 55:
            parts.append("【四星级锦鲤】")
        elif total >= 45:
            parts.append("【三星级锦鲤】")
        return "；".join(parts)

    # ============================================================
    # 策略六B：锦鲤选股B
    # ============================================================

    async def _fetch_koi_b_candidates(self) -> list[dict]:
        top = await self.sina.fetch_sina_ranking(300, "changepercent")
        if not top:
            return []

        candidates = []
        for s in top:
            name = s.get("name", "")
            sym = s.get("symbol", "")
            p = self._sf(s.get("price"))
            chg = self._sf(s.get("change_pct"))
            if "ST" in name or "*ST" in name:
                continue
            if name.startswith("N") and len(name) < 6:
                continue
            if sym.startswith("bj"):
                continue
            if 0 < p < 2.5:
                continue
            if chg < 1.0:
                continue
            candidates.append(dict(s))

        if not candidates:
            return []

        enriched = await self.tencent.enrich_with_realtime(candidates)

        passed = []
        for s in enriched:
            code = s.get("code", "")
            if not code:
                continue
            try:
                fin = await self.eastmoney.fetch_financial_data(code)
                s["financials"] = fin
                veto = self._check_koi_b_veto(s, fin)
                if veto.get("vetoed"):
                    s["veto_triggered"] = True
                    s["veto_reason"] = veto.get("reason", "")
                    s["strategy_score"] = 0.0
                    s["decision"] = "淘汰剔除"
                    s["core_analysis"] = veto.get("reason", "")
                else:
                    s["veto_triggered"] = False
                    s["veto_reason"] = ""
                passed.append(s)
            except Exception:
                continue

        if not passed:
            return []

        scored = []
        for s in passed:
            if s.get("veto_triggered"):
                scored.append(s)
                continue
            score_result = self._score_koi_b(s)
            s["strategy_score"] = score_result["total_score"]
            s["financial_score"] = score_result["financial_score"]
            s["capital_score_koi_b"] = score_result["capital_score"]
            s["technical_score"] = score_result["technical_score"]
            scored.append(s)

        scored.sort(key=lambda x: -self._sf(x.get("strategy_score")))
        top10 = scored[:10]

        for s in top10:
            if not s.get("veto_triggered"):
                s["decision"] = self._get_koi_b_decision(self._sf(s.get("strategy_score")))
                s["core_analysis"] = self._build_koi_b_analysis(s)
                s["ai_analysis_text"] = "AI深度穿透分析请使用App端AI模型配置"
                s["local_score"] = self._sf(s.get("strategy_score"))
                s["ai_score"] = 0

        return top10

    def _check_koi_b_veto(self, stock: dict, fin: dict) -> dict:
        name = stock.get("name", "")
        if "ST" in name or "*ST" in name:
            return {"vetoed": True, "reason": "ST/*ST股，风险极高"}
        risk_kw = ["SST", "S*ST", "S ST", "风险警示", "退市"]
        for kw in risk_kw:
            if kw in name:
                return {"vetoed": True, "reason": f"存在退市风险标识({kw})"}

        debt = self._sf(fin.get("debt_ratio"))
        if debt >= 70:
            return {"vetoed": True, "reason": f"资产负债率{debt:.0f}%≥70%，财务风险高"}

        deduct = self._sf(fin.get("deduct_profit"))
        deduct_growth = self._sf(fin.get("deduct_profit_growth"))
        eps = self._sf(fin.get("eps"))
        roe = self._sf(fin.get("roe"))
        pg = self._sf(fin.get("profit_growth"))
        gm = self._sf(fin.get("gross_margin"))

        if deduct < 0:
            return {"vetoed": True, "reason": f"扣非净利润为负({deduct:.0f}万元)，已亏损面临ST风险"}
        if 0 < deduct < 5000:
            return {"vetoed": True, "reason": f"扣非净利润仅{deduct:.0f}万元<5000万，不达标面临ST风险"}
        if 5000 <= deduct < 10000 and 0 < eps < 0.3:
            return {"vetoed": True, "reason": f"扣非净利润{deduct:.0f}万元偏低且EPS仅{eps:.2f}元，盈利质量差"}
        if pg > 50 and deduct_growth > 0 and deduct_growth < pg * 0.3:
            return {"vetoed": True, "reason": f"净利润增{pg:.0f}%但扣非仅增{deduct_growth:.0f}%，利润靠非经常性损益粉饰"}
        if eps < 0:
            return {"vetoed": True, "reason": f"EPS为负({eps:.3f}元)，已亏损面临ST风险"}
        if 0 <= roe < 1 and 0 < eps < 0.1:
            return {"vetoed": True, "reason": f"ROE仅{roe:.1f}%，盈利能力极低"}

        sunset = ["钢铁", "煤炭", "水泥", "造纸", "玻纤", "氯碱", "纯碱", "PVC", "磷化工", "石化", "化纤"]
        for kw in sunset:
            if kw in name:
                return {"vetoed": True, "reason": f"属于夕阳行业({kw})，产能过剩风险"}

        if 0 <= gm < 10 and (pg < -20 or eps < 0.1):
            return {"vetoed": True, "reason": f"毛利率{gm:.0f}%过低且盈利差，经营质量堪忧"}
        if roe > 30 and 0 < gm < 20:
            return {"vetoed": True, "reason": f"ROE{roe:.0f}%异常高但毛利率仅{gm:.0f}%，财务数据存疑"}

        return {"vetoed": False, "reason": ""}

    def _score_koi_b(self, s: dict) -> dict:
        financial_score = 0.0
        capital_score = 0.0
        technical_score = 0.0

        fin = s.get("financials", {})
        chg = self._sf(s.get("change_pct"))
        turnover = self._sf(s.get("turnoverratio"))
        amount = self._sf(s.get("amount"))
        mktcap = self._sf(s.get("mktcap"))

        rev = self._sf(fin.get("revenue_growth"))
        pg = self._sf(fin.get("profit_growth"))
        if rev > 20 and pg > 50:
            financial_score += 20
        elif rev > 20 or pg > 50:
            financial_score += 10

        roe = self._sf(fin.get("roe"))
        gm = self._sf(fin.get("gross_margin"))
        if roe >= 20:
            financial_score += 10
        elif roe >= 15:
            financial_score += 8
        elif roe >= 10:
            financial_score += 5
        elif roe >= 5:
            financial_score += 2

        if gm > 40:
            financial_score += 10
        elif gm > 25:
            financial_score += 7
        elif gm > 15:
            financial_score += 4
        else:
            financial_score += 1

        cap_yi = mktcap / 10000
        amount_yi = amount / 1e8
        if cap_yi > 0 and amount_yi > 0:
            ratio = (amount_yi / cap_yi) * 100
            if ratio >= 10:
                capital_score += 20
            elif ratio >= 5:
                capital_score += 15
            elif ratio >= 2:
                capital_score += 10
            elif ratio >= 1:
                capital_score += 5
            else:
                capital_score += 0

        if 3 <= turnover <= 15 and amount_yi > 3:
            capital_score += 20
        elif 15 < turnover <= 25 and amount_yi > 5:
            capital_score += 15
        elif turnover >= 3 and amount_yi > 2:
            capital_score += 10
        elif turnover < 3 or amount_yi < 1:
            capital_score += 0
        else:
            capital_score += 5

        if chg >= 9.8:
            technical_score += 15
        elif chg >= 7.0:
            technical_score += 12
        elif chg >= 5.0:
            technical_score += 8
        elif chg >= 3.0:
            technical_score += 5
        else:
            technical_score += 0

        if 3 <= turnover <= 10:
            technical_score += 5
        elif 10 < turnover <= 20:
            technical_score += 3
        else:
            technical_score += 1

        return {
            "total_score": financial_score + capital_score + technical_score,
            "financial_score": financial_score,
            "capital_score": capital_score,
            "technical_score": technical_score,
        }

    def _get_koi_b_decision(self, score: float) -> str:
        if score >= 85:
            return "强力推荐"
        if score >= 60:
            return "建议观察"
        return "淘汰剔除"

    def _build_koi_b_analysis(self, s: dict) -> str:
        parts = []
        fin = s.get("financials", {})
        chg = self._sf(s.get("change_pct"))
        turnover = self._sf(s.get("turnoverratio"))
        fs = self._sf(s.get("financial_score"))
        cs = self._sf(s.get("capital_score_koi_b"))
        ts = self._sf(s.get("technical_score"))
        total = self._sf(s.get("strategy_score"))

        parts.append(f"三维度评分:财务{fs:.0f}+资金{cs:.0f}+技术{ts:.0f}={total:.0f}分")
        parts.append(f"今日涨{chg:.1f}%，换手{turnover:.1f}%")

        roe = self._sf(fin.get("roe"))
        if roe > 0:
            parts.append(f"ROE{roe:.1f}%")
        pg = self._sf(fin.get("profit_growth"))
        if pg > 0:
            parts.append(f"净利增{pg:.0f}%")
        debt = self._sf(fin.get("debt_ratio"))
        if 0 < debt < 70:
            parts.append(f"负债率{debt:.0f}%，安全")

        decision = s.get("decision", self._get_koi_b_decision(total))
        parts.append(f"决策:{decision}")

        return "；".join(parts)
