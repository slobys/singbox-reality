#!/bin/bash

echo "=== 安装 sing-box 并配置 Reality + uTLS ==="

# 安装 sing-box
echo "[1/5] 安装 sing-box..."
curl -fsSL https://sing-box.sagernet.org/install.sh | bash

# 生成密钥对
echo "[2/5] 生成 Reality 密钥对..."
REALITY_KEY=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$REALITY_KEY" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$REALITY_KEY" | grep PublicKey | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)

# 用户输入
read -p "请输入你的 VLESS UUID: " UUID
read -p "请输入伪装域名（如 cloudflare.com）: " SERVER_NAME

# 写入配置文件
echo "[3/5] 写入配置文件..."
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

# 创建 systemd 服务
echo "[4/5] 创建 systemd 服务..."
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

# 启动服务
echo "[5/5] 启动 sing-box 服务..."
systemctl daemon-reexec
systemctl enable sing-box
systemctl start sing-box

echo "✅ 安装完成！以下是你的 Reality 节点参数："
echo "-------------------------------------------"
echo "服务器地址：你的 VPS IP"
echo "端口：443"
echo "UUID：$UUID"
echo "伪装域名（Server Name）：$SERVER_NAME"
echo "Reality 公钥（public_key）：$PUBLIC_KEY"
echo "short_id：$SHORT_ID"
echo "uTLS 指纹建议：edge / chrome / firefox 等（客户端设置）"
echo "-------------------------------------------"
