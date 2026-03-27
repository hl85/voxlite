# orvice/ddns 库分析

> 原始仓库：[https://github.com/orvice/ddns](https://github.com/orvice/ddns)

---

## 一、一句话概述

`orvice/ddns` 是一个用 **Go** 编写的 **动态 DNS（DDNS）客户端**，其核心作用是：**周期性检测当前公网 IP 地址，一旦发生变化则自动更新指定域名的 DNS A 记录**，从而让域名始终解析到最新的公网 IP。

---

## 二、使用场景

适用于家庭宽带、VPS、树莓派等 **没有固定公网 IP** 的场景：

- 用户希望通过固定域名（如 `home.example.com`）访问家里的设备；
- 运营商分配的公网 IP 不定期发生变化；
- DDNS 客户端作为后台服务运行，检测到 IP 变化时自动更新 DNS 记录，让域名始终可用。

---

## 三、功能清单

| 功能 | 说明 |
|---|---|
| 公网 IP 获取 | 调用 `https://ifconfig.co/json`，自动重试 3 次 |
| DNS 记录查询 | 从 DNS 服务商读取当前 A 记录 |
| DNS 记录更新 | IP 变化时调用 DNS API 更新 A 记录 |
| DNS 记录创建 | 记录不存在时自动追加新 A 记录 |
| IP 未变跳过 | 检测到 IP 未变则静默跳过，不产生多余 API 调用 |
| 定时轮询 | 每 **3 分钟**执行一次检测（硬编码） |
| Telegram 通知 | IP 变更时可选推送 Telegram 消息 |
| 多 DNS 服务商 | 支持 **Cloudflare** 和 **阿里云（Aliyun）** |
| Docker 支持 | 提供 `Dockerfile` 与 `docker-compose.yml` |

---

## 四、工作流程

```
启动
  │
  ▼
[定时循环，每 3 分钟]
  │
  ├─1─▶ 调用 ifconfig.co/json 获取当前公网 IP
  │
  ├─2─▶ 解析配置中的域名，拆分为 name 和 zone
  │        例如 "home.example.com" → name="home", zone="example.com"
  │
  ├─3─▶ 查询 DNS 服务商当前 zone 下的所有记录
  │
  ├─4─▶ 查找与 name 匹配的 A 记录
  │        ├─ 找到 & IP 相同 → 跳过，等待下次轮询
  │        ├─ 找到 & IP 不同 → SetRecords 更新 + 发送 Telegram 通知
  │        └─ 未找到 → AppendRecords 新建 A 记录
  │
  └─▶ 休眠 3 分钟后重复
```

---

## 五、项目结构

```
ddns/
├── cmd/ddns/           # main 入口，Wire 注入启动
├── dns/
│   └── dns.go          # DNS 服务商工厂：根据配置创建 Cloudflare 或 Aliyun 实例
├── internal/
│   ├── app/app.go      # 核心业务逻辑：IP 检测、DNS 读写、通知
│   ├── config/config.go# 配置读取（全部来自环境变量）
│   ├── ip/ip.go        # 公网 IP 获取（ifconfig.co）
│   └── wire/           # Google Wire 依赖注入声明
├── notify/             # 通知模块（Telegram）
├── Dockerfile
└── docker-compose.yml
```

---

## 六、配置说明

所有配置通过 **环境变量** 传入，无配置文件。

| 环境变量 | 必填 | 说明 |
|---|---|---|
| `DOMAIN` | ✅ | 要更新的完整域名，如 `home.example.com` |
| `DNS_PROVIDER` | ✅ | DNS 服务商：`cloudflare` 或 `aliyun` |
| `CF_TOKEN` | Cloudflare 时必填 | Cloudflare API Token |
| `ALIYUN_ACCESS_KEY_ID` | 阿里云时必填 | 阿里云 AccessKey ID |
| `ALIYUN_ACCESS_KEY_SECRET` | 阿里云时必填 | 阿里云 AccessKey Secret |
| `TELEGRAM_TOKEN` | ❌ 可选 | Telegram Bot Token |
| `TELEGRAM_CHATID` | ❌ 可选 | Telegram Chat ID，用于接收变更通知 |

---

## 七、关键依赖

| 依赖 | 作用 |
|---|---|
| [`libdns/libdns`](https://github.com/libdns/libdns) | DNS 操作抽象接口（`RecordGetter / RecordAppender / RecordSetter`） |
| [`libdns/cloudflare`](https://github.com/libdns/cloudflare) | Cloudflare DNS 实现 |
| [`libdns/alidns`](https://github.com/libdns/alidns) | 阿里云 DNS 实现 |
| [`hashicorp/go-retryablehttp`](https://github.com/hashicorp/go-retryablehttp) | 带自动重试的 HTTP 客户端，用于 IP 获取 |
| [`google/wire`](https://github.com/google/wire) | 编译期依赖注入 |

---

## 八、快速使用示例

### 使用 Cloudflare

```bash
DNS_PROVIDER=cloudflare \
DOMAIN=home.example.com \
CF_TOKEN=your_cloudflare_api_token \
./ddns
```

### 使用阿里云

```bash
DNS_PROVIDER=aliyun \
DOMAIN=home.example.com \
ALIYUN_ACCESS_KEY_ID=your_key_id \
ALIYUN_ACCESS_KEY_SECRET=your_key_secret \
./ddns
```

### 使用 Docker Compose

```yaml
# docker-compose.yml
services:
  ddns:
    image: ghcr.io/orvice/ddns:latest
    environment:
      DNS_PROVIDER: cloudflare
      DOMAIN: home.example.com
      CF_TOKEN: your_cloudflare_api_token
      TELEGRAM_TOKEN: your_bot_token   # 可选
      TELEGRAM_CHATID: your_chat_id    # 可选
    restart: unless-stopped
```

---

## 九、局限性说明

| 限制 | 描述 |
|---|---|
| 仅支持 A 记录（IPv4） | 代码硬编码 `Type: "A"`，不支持 AAAA（IPv6）记录 |
| 轮询间隔固定为 3 分钟 | 不可配置 |
| 单域名模式 | 每次只能管理一个域名，多域名需运行多个实例 |
| IP 服务单点依赖 | 仅使用 `ifconfig.co`，该服务不可用时无法获取 IP |
| 错误即退出 | `updateIP` 出错后调用 `os.Exit(1)` 直接终止进程 |
