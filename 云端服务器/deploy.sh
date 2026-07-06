#!/bin/bash
mkdir -p /root/backend/strategies /root/backend/services /root/backend/portfolios /root/backend/cache /data/backups
cp ai_stock_picker_backend/main.py /root/backend/
cp ai_stock_picker_backend/portfolio_manager.py /root/backend/
cp ai_stock_picker_backend/portfolio_monitor.py /root/backend/
cp ai_stock_picker_backend/scheduler.py /root/backend/
cp ai_stock_picker_backend/strategies/engine.py /root/backend/strategies/
cp ai_stock_picker_backend/services/*.py /root/backend/services/
cp ai_stock_picker_backend/requirements.txt /root/backend/
cd /root/backend && python3 -m venv venv && venv/bin/pip install -r requirements.txt
echo "部署完成，请手动创建 systemd 服务和 crontab（参考文档）"
