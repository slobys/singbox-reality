#!/bin/bash

echo "=== 安装 sing-box（从 GitHub Releases 获取最新版）==="

# 1. 下载并安装 sing-box 最新版本
VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f 4)
wget https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION}-linux-amd64.tar.gz
tar -xvzf sing-box-${VERSION}-linux-amd64.tar.gz
cd sing-box-${VERSION}-linux-amd64
chmod +x sing-box
mv sing-box /usr/local/bin/
cd ..
rm -rf sing-box-${VERSION}-linux-amd64*

# 2. 生成 Reality 密钥
echo "[2/6] 生成 Reality 密钥..."
REALITY_KEY=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$REALITY_KEY" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$REALITY_KEY" | grep PublicKey | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)

# 3. 用户输入
read -p "请输入你的 VLESS UUID: " UUID
read -p "请输入伪装域名（如 cloudflare.com）: " SERVER_NAME
SERVER_IP=$(curl -s https://api.ipify.org)

# 4. 写入服务端配置文件
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

# 5. 写入客户端配置文件
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

# 6. 写入 systemd 启动服务
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

# 7. 防火墙开放 443 端口
ufw allow 443 > /dev/null 2>&1 || echo "⚠️ 请手动确保防火墙允许 443 端口"

# 8. 输出连接信息
echo "✅ Reality + sing-box 安装完成！以下是你的节点信息："
echo "-------------------------------------------"
echo "服务端 IP：$SERVER_IP"
echo "UUID：$UUID"
echo "Reality 公钥：$PUBLIC_KEY"
echo "short_id：$SHORT_ID"
echo "伪装域名（Server Name）：$SERVER_NAME"
echo "客户端配置文件路径：/root/client-config.json"
echo "下载命令：scp root@$SERVER_IP:/root/client-config.json ./"
echo "-------------------------------------------"
