# 蓝图极智AI选股 - 后端部署指南

## 系统要求
- Linux 服务器（CentOS 7+/Ubuntu 20.04+）
- Python 3.9+
- 2核2G 以上配置

## 快速部署

```bash
# 1. 上传后端代码到服务器
# 使用 scp 或 git clone

# 2. 安装依赖
cd ai_stock_picker_backend
pip3 install -r requirements.txt

# 3. 配置安全Token（务必修改！）
export AUTH_TOKEN="你的安全Token_请修改为随机字符串"

# 4. 启动服务（测试）
python3 main.py

# 5. 使用 systemd 作为守护进程（推荐）
cat > /etc/systemd/system/aistock.service << 'EOF'
[Unit]
Description=蓝图极智AI选股后端
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/ai_stock_picker_backend
Environment=AUTH_TOKEN=你的安全Token_请修改为随机字符串
Environment=BACKUP_DIR=/data/backups
ExecStart=/usr/bin/python3 /root/ai_stock_picker_backend/main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable aistock
systemctl start aistock

# 6. 查看状态
systemctl status aistock
```

## 安全配置

1. **务必修改 AUTH_TOKEN** 为一个随机字符串（32位以上）
2. 建议配置防火墙，只开放 `8000`（或你设置的）端口
3. 如需 HTTPS，请使用 Nginx 反向代理 + Let's Encrypt

## Nginx 反向代理配置

```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## API 文档

启动后访问 `http://your-server:8000/docs` 查看 Swagger 文档。
