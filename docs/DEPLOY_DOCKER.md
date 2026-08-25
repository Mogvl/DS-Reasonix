# DS-Reasonix 绿联 NAS / Docker 部署指南

> 本文档说明如何在 **绿联 NAS（UGREEN）** 或任意支持 Docker 的主机上，用
> Docker Compose 一键部署 [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix)
> 的 Web 服务版本。

## 架构

```
浏览器 ──► 前端 nginx (:7551) ──反向代理──► 后端 reasonix serve (:7552)
                                             │
                                             ├─ DeepSeek API（OpenAI 兼容）
                                             ├─ 数据目录 ./data/reasonix（配置/会话/记忆）
                                             └─ 工作区   ./workspace（agent 执行任务）
```

| 服务 | 容器 | 端口 | 说明 |
| --- | --- | --- | --- |
| `web` | ds-reasonix-web | **7551** → 80 | nginx 前端，浏览器访问入口（SSE 友好） |
| `reasonix` | ds-reasonix | **7552** → 7552 | 后端引擎，Web UI + SSE 事件流 + JSON API |

`reasonix serve` 是官方自带的 Web 前端（内置聊天界面），可直连 7552 访问；
日常使用推荐走 7551。

## 一、准备

1. **获取 DeepSeek API Key**：<https://platform.deepseek.com> → API Keys。
2. **把仓库拷到 NAS**（二选一）：
   - 绿联 Docker / 终端里 `git clone https://github.com/Mogvl/DS-Reasonix.git`
   - 或直接把整个文件夹上传到 NAS（例如 `/volume1/docker/ds-reasonix`）
3. 在仓库根目录创建 `.env` 并填写密钥：

   ```bash
   cp .env.docker.example .env
   # 编辑 .env，把 DEEPSEEK_API_KEY 换成你自己的 key
   ```

## 二、一键启动

在仓库根目录（`docker-compose.yml` 所在目录）执行：

```bash
docker compose up -d
```

- **海外网络**：直接拉取 GitHub Container Registry 预构建镜像（amd64 + arm64）。
- **国内网络**：GHCR 拉不动时改为本地构建（首次构建约 5–15 分钟）：

  ```bash
  docker compose up -d --build
  # 若 Go 模块下载慢，在 .env 里加： GOPROXY=https://goproxy.cn,direct
  ```

启动完成后：

- 浏览器打开 **http://NAS地址:7551**（前端）
- 后端直连：**http://NAS地址:7552**

> 绿联 Docker UI：也可在「项目」中新建，填写 compose 内容并部署，效果相同。

## 三、登录鉴权

默认 `REASONIX_SERVE_AUTH=token`：

- 若 `.env` 里设置了 `REASONIX_SERVE_TOKEN`，用它登录；
- 若留空，服务启动时随机生成，查看 `docker logs ds-reasonix` 中的
  `share: http://.../#token=...` 链接，打开即可自动登录。

也可改用密码登录（浏览器记住密码更友好）：

```env
REASONIX_SERVE_AUTH=password
REASONIX_SERVE_PASSWORD=你的密码
```

然后访问 `http://NAS地址:7551/login` 登录。

> ⚠️ 不建议 `REASONIX_SERVE_AUTH=none`：任何能访问 NAS 端口的人都能使用你的
> API Key 并操作工作区。

## 四、目录与数据

| 宿主机路径 | 用途 |
| --- | --- |
| `./data/reasonix/` | Reasonix 主目录：`config.toml`、`.env`（凭据）、会话、记忆、缓存 |
| `./workspace/` | 工作区：agent 读写任务文件的目录，可从 NAS 文件管理器直接查看 |
| `./config/config.toml` | 只读配置模板，首次启动复制进数据目录；之后以数据目录中的为准 |
| `./nginx.conf` | nginx 前端反向代理配置 |

**修改配置**：编辑 `./data/reasonix/config.toml`（如更换默认模型、增加 provider），
然后 `docker compose restart reasonix`。新增 provider 时参考项目根目录
`reasonix.example.toml`。

**修改 API Key**：改 `.env` 里的 `DEEPSEEK_API_KEY`，然后
`docker compose up -d`（入口脚本每次启动都会把环境变量同步进数据目录的 `.env`）。

## 五、升级 / 更新

```bash
git pull                       # 拉取最新代码
docker compose up -d --build   # 重新构建并滚动更新（数据目录不受影响）
```

或拉取最新镜像：

```bash
docker compose pull && docker compose up -d
```

## 六、常用运维

```bash
docker compose logs -f reasonix   # 查看后端日志（token 链接、运行情况）
docker compose logs -f web        # 查看 nginx 日志
docker compose restart reasonix   # 重启后端
docker compose down               # 停止（数据保留）
docker compose down -v            # 停止并删除数据卷（慎用）
```

## 七、常见问题

- **容器反复重启**：看 `docker compose logs reasonix`。最常见原因是 `.env`
  中 `DEEPSEEK_API_KEY` 未设置或无效（compose 会直接报错提示）。
- **token 模式进不去**：确认用 `docker logs ds-reasonix` 里的 share 链接，
  或固定 `REASONIX_SERVE_TOKEN` 后重启。
- **国内拉取 nginx 镜像慢**：给 Docker 配置国内镜像加速器，或
  `docker pull nginx:1.27-alpine` 手动先拉一次。
- **工作区文件权限**：容器内以 UID 1000 运行；如需 NAS 管理员直接编辑
  `./workspace`，可在宿主机执行 `chown -R 1000:1000 workspace`。
- **Bash 沙箱**：容器内已配置 `[sandbox] bash = "off"`（Docker 中大多 NAS 内核
  无法运行 bubblewrap 沙箱）。隔离边界由容器本身承担——agent 的 Bash 命令在
  容器内执行，文件写入被限制在 `/workspace`（`workspace_root`）。不要把容器
  直接暴露到公网，并务必开启 token/password 鉴权。
