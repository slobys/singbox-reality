#!/bin/bash

echo "=== [1/6] 使用官方脚本安装 sing-box ==="
bash <(curl -fsSL https://sing-box.app/install.sh)

if ! command -v sing-box &> /dev/null; then
    echo "❌ sing-box 安装失败，终止脚本。"
    exit 1
fi

echo "=== [2/6] 生成 Reality 密钥对 ==="
REALITY_KEY=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$REALITY_KEY" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$REALITY_KEY" | grep PublicKey | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)

read -p "请输入你的 UUID（可使用 https://uuidgenerator.net 生成）: " UUID
read -p "请输入伪装域名（如 cloudflare.com、yahoo.com）: " SERVER_NAME
SERVER_IP=$(curl -s https://api.ipify.org)

echo "=== [3/6] 写入服务端配置 ==="
mkdir -p /etc/sing-box

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info",
    "output": "console"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "0.0.0.0",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SERVER_NAME",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$SERVER_NAME",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

echo "=== [4/6] 配置 systemd 启动项 ==="
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

echo "=== [5/6] 创建客户端配置文件到 /root/client-config.json ==="
cat > /root/client-config.json <<EOF
{
  "log": {
    "level": "info",
    "output": "console"
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": 10808
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "reality-out",
      "server": "$SERVER_IP",
      "server_port": 443,
      "uuid": "$UUID",
      "tls": {
        "enabled": true,
        "server_name": "$SERVER_NAME",
        "reality": {
          "enabled": true,
          "public_key": "$PUBLIC_KEY",
          "short_id": "$SHORT_ID"
        },
        "utls": {
          "enabled": true,
          "fingerprint": "edge"
        }
      }
    }
  ],
  "route": {
    "rules": [
      {
        "outbound": "reality-out"
      }
    ]
  }
}
EOF

echo "=== [6/6] 自动放行 443 端口（如有启用 ufw） ==="
ufw allow 443 > /dev/null 2>&1 || echo "⚠️ 手动检查防火墙是否允许 443 端口"

echo "✅ 安装完成，以下是配置信息："
echo "-------------------------------------------"
echo "服务端 IP：$SERVER_IP"
echo "UUID：$UUID"
echo "Reality 公钥（public_key）：$PUBLIC_KEY"
echo "short_id：$SHORT_ID"
echo "伪装域名：$SERVER_NAME"
echo "客户端配置已生成：/root/client-config.json"
echo "下载命令示例：scp root@$SERVER_IP:/root/client-config.json ./"
echo "-------------------------------------------"
