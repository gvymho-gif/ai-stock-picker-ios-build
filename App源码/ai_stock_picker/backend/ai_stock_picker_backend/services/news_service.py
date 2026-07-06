"""
东方财富新闻服务 - 热点追踪新闻源
"""
import httpx


class NewsService:
    """东方财富实时财经新闻"""

    def __init__(self):
        self._client = httpx.AsyncClient(timeout=15.0)
        self._base_url = "https://np-listapi.eastmoney.com/comm/web/getListInfo"

    async def close(self):
        await self._client.aclose()

    async def fetch_latest_news(self, page_size: int = 10) -> list[dict]:
        """获取最新财经新闻"""
        try:
            resp = await self._client.get(
                f"{self._base_url}?client=web&pageSize={page_size}&type=1&mTypeAndCode=1.000001",
                headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                    "Referer": "https://so.eastmoney.com/",
                },
            )
            if resp.status_code != 200 or not resp.text:
                return []
            data = resp.json()
            if data.get("code") != 1:
                return []
            items = data.get("data", {}).get("list") or []
            return [
                {
                    "title": str(item.get("Art_Title", "")),
                    "code": str(item.get("Art_Code", "")),
                    "time": str(item.get("Art_ShowTime", "")),
                    "url": str(item.get("Art_Url", "")),
                }
                for item in items
                if str(item.get("Art_Title", ""))
            ]
        except Exception:
            return []

    def filter_hot_news(self, news_list: list[dict]) -> list[dict]:
        """关键词初筛高潜力新闻"""
        hot_keywords = [
            # 政策类
            r'重大政策', r'政策转向', r'国务院', r'发改委', r'工信部', r'商务部',
            r'扶持', r'补贴', r'减免', r'放宽', r'准入',
            # 突发事件
            r'突发', r'紧急', r'限制出口', r'禁止出口', r'出口管制',
            r'制裁', r'断供', r'禁令', r'反制',
            # 从0到1新技术
            r'突破', r'首创', r'全球首', r'国内首', r'量产',
            r'商业化', r'落地', r'重大进展', r'关键突破',
            # 供需危机
            r'涨价', r'紧缺', r'缺货', r'断供', r'产能不足',
            r'供给收缩', r'需求暴增', r'供不应求',
            # 行业重大事件
            r'重组', r'并购', r'注入', r'借壳',
            r'中标', r'签约', r'大单', r'订单',
            # 市场异动
            r'涨停', r'暴涨', r'大爆发', r'掀涨停潮',
        ]

        filtered = []
        import re
        pattern = re.compile("|".join(hot_keywords))
        for news in news_list:
            title = news.get("title", "")
            if pattern.search(title):
                filtered.append(news)

        # 如果筛选后为空，返回前5条作为降级
        if not filtered:
            return news_list[:5]

        return filtered
