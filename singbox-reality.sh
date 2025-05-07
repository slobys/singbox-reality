#!/bin/bash

echo "=== 安装 sing-box 并配置 Reality + uTLS ==="

# 安装 sing-box
echo "[1/6] 安装 sing-box..."
curl -fsSL https://sing-box.sagernet.org/install.sh | bash

# 生成密钥对
echo "[2/6] 生成 Reality 密钥对..."
REALITY_KEY=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$REALITY_KEY" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$REALITY_KEY" | grep PublicKey | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)

# 用户输入
read -p "请输入你的 VLESS UUID: " UUID
read -p "请输入伪装域名（如 cloudflare.com）: " SERVER_NAME

# 获取公网 IP
SERVER_IP=$(curl -s https://api.ip.sb/ip)

# 写入服务端配置
echo "[3/6] 写入服务端配置文件..."
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
      "listen": "::",
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

# 写入客户端配置
echo "[4/6] 生成客户端配置文件到 /root/client-config.json"

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
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "reality-out",
      "server": "$SERVER_IP",
      "server_port": 443,
      "uuid": "$UUID",
      "flow": "",
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

# 创建并启动服务
echo "[5/6] 创建并启动 systemd 服务..."
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
systemctl enable sing-box
systemctl restart sing-box

# 提示信息
echo "✅ [6/6] 安装完成！以下是配置信息："
echo "-------------------------------------------"
echo "服务端 IP：$SERVER_IP"
echo "UUID：$UUID"
echo "Reality 公钥：$PUBLIC_KEY"
echo "short_id：$SHORT_ID"
echo "伪装域名：$SERVER_NAME"
echo "客户端配置文件已生成：/root/client-config.json"
echo "你可以通过以下命令下载："
echo "scp root@$SERVER_IP:/root/client-config.json ./"
echo "-------------------------------------------"
