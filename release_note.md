# Agent Dance Release Notes

> 版本号来源于项目根目录 `VERSION` 文件。

---

## 0.0.2 — 上下文修复 (2026-06-26)

### Bug 修复

| # | 问题 | 修复 |
|---|------|------|
| B-004 | 推理模型(DeepSeek-v4-pro)调用工具后只显示思考过程，不显示正式回复 | `run.completed` output 为空时用 reasoning 补位；流式渲染兜底；消息保存兜底 |
| B-005 | `takeStreamingIncrement` 增量 token 被静默丢弃，正文只显示第一个字 | 恢复原始逻辑 `return (accumulated + incoming, incoming)` |
| B-006 | 退出 App 重进后上下文丢失 | 每次请求携带 `conversationHistory`（从本地 DB 加载历史消息构建） |
| B-007 | Hermes v0.17 `/v1/runs` 不自动注入 session 历史 | App 端始终传 `conversationHistory`，不依赖服务端自动加载 |

### 架构变更

- **Session 管理**：从"服务器维度单对话"重构为"会话维度多对话"
- 新增 `SessionListScreen`（会话列表页），支持创建/切换/重命名/删除会话
- `ChatTaskRegistry` 按 `sessionId` 索引（原 `serverId`）
- `ChatViewModel` 新增 `sessionId`/`sessionTitle` 参数
- API 请求增加 `X-Hermes-Session-Id` / `X-Hermes-Session-Key` header

### 根因分析（本次调试关键发现）

- **Hermes v0.17 `/v1/runs` 不自动注入 session 历史消息到模型上下文**。模型只能通过 `session_search` 工具检索（搜全量记忆而非当前 session），导致上下文歪到其他 session。
- **TUI（channel hermes）正常**是因为走 Gateway 进程内 session，直接注入全量历史；API Server 路径不同。
- **解法**：客户端必须自己传 `conversation_history`，不能依赖 `/v1/runs` 自动加载。

---

## 0.0.1 — 初始版本 (2026-06-15)

### 功能概述

4 Tab 微信式结构：智能体 · 服务器 · 发现AI · 我。

#### Tab 1：智能体

| 编号 | 功能 |
|------|------|
| F-101 | 服务器列表入口 |
| F-102 | 在线状态标识 |
| F-103 | 搜索 |
| F-110 | 文字发送（流式返回） |
| F-111 | Markdown 渲染（代码高亮/表格/列表） |
| F-112 | 停止生成 |
| F-113 | 思考过程展示 |
| F-114 | 思考过程折叠 |
| F-115 | 拍照发送 |
| F-116 | 相册选择 |
| F-117 | 缩略图预览 |
| F-118 | 长按录音 |
| F-119 | 上滑取消录音 |
| F-120 | 工具进度条 |
| F-121 | 流式光标 |
| F-122 | 错误提示 |
| F-123 | 权限申请弹窗 |
| F-124 | 音量键快捷审批 |
| F-125 | 60s 超时自动批准 |
| F-129 | 多轮上下文对话 |
| F-130 | 会话持久化（SQLite） |
| F-138 | 对话用户头像 |

#### Tab 2：服务器列表

| 编号 | 功能 |
|------|------|
| F-201 | 服务器列表（按名称排序） |
| F-202 | 在线状态+延迟 |
| F-203 | 添加服务器 |
| F-204 | 编辑服务器 |
| F-205 | 删除服务器 |
| F-210~F-215 | 添加/编辑表单（名称/地址/密钥/类型/图标） |
| F-220~F-221 | 网络诊断（连通性检测/延迟） |

#### Tab 3：发现AI

| 编号 | 功能 |
|------|------|
| F-301~F-305 | 功能入口/AI市场/附近智能体/帮助/关于 |
| F-310~F-311 | 局域网自动发现+一键添加 |

#### Tab 4：我

| 编号 | 功能 |
|------|------|
| F-401~F-403 | 头像/昵称/设备标识 |
| F-410~F-416 | 主题/默认智能体/通知/数据管理/安全/日志/关于 |

#### 全局

| 编号 | 功能 |
|------|------|
| F-501~F-507 | 底部导航/暗色模式/安全存储/权限/后台运行/通知/图标 |

### 技术栈

- Flutter 3.x（Dart），Material 3
- MVVM + Repository（ChangeNotifier）
- SQLite（drift）本地持久化
- 手动 SSE 流式解析
- flutter_markdown_plus 渲染 Markdown
- flutter_secure_storage 安全存储

### 平台

Android 8.0+ / iOS 16.0+
