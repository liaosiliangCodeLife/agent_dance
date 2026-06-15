1|# AGENTS.md — Agent Dance
2|
3|## 项目概览
4|
5|一个对接 Agents Agent 的 AI 助手移动端 App，用 Flutter 一套代码同时跑 Android 和 iOS，功能类似 ChatGPT。**本项目只实现 Android 和 iOS 双端，不涉及 Web/桌面端。**
6|
7|聊天记录**本地持久化**（SQLite），支持多会话切换、历史回溯。与 Agents 的对话状态各端独立管理。
8|
9|## 技术栈
10|
11|| 层 | 选型 |
12||----|------|
13|| 框架 | **Flutter** (Dart) |
14|| 架构 | MVVM + Repository（用 `ChangeNotifier` 或 `Riverpod`） |
15|| 网络 | `http` 包（普通请求）+ 手动 SSE 解析（`http.Client.send()` 流式读 body） |
16|| 序列化 | `json_serializable` + `freezed`（不可变 Model） |
17|| 本地存储 | **SQLite**（`drift` 推荐，或 `sqflite`） |
18|| 敏感配置 | `flutter_secure_storage`（Keychain / EncryptedSharedPreferences） |
19|| UI | Material 3 |
20|| Markdown 渲染 | `flutter_markdown` |
21|| 语音输入 | `record` 包（录音 .m4a）→ base64 → Agents STT 引擎转录 |
22|| 图片选择 | `image_picker` |
23|| 最低版本 | Android 8.0 / iOS 16.0 |
24|| 开发工具 | Android Studio 或 VS Code + Flutter 插件 |
25|
26|## 项目结构
27|
28|```
29|agent_dance/
30|├── AGENTS.md                              # 本文件（Cursor 规则）
31|├── protocol/
32|│   └── api-contract.md                    # Agents API 接口协议文档
33|├── lib/
34|│   ├── main.dart                          # 入口：初始化日志 → 读取配置 → runApp
35|│   ├── app.dart                           # MaterialApp + 路由 + 主题
36|│   ├── config/
37|│   │   └── app_config.dart                # 配置常量 + 安全存储读写
38|│   │
39|│   ├── agents/                            # ═══ Agents 业务逻辑层 ═══
40|│   │   ├── models/                        # 数据模型
41|│   │   │   ├── message.dart               #   Message（含 reasoning/image/audio 字段）
42|│   │   │   ├── session.dart               #   Session
43|│   │   │   └── chat_state.dart            #   ChatState 枚举 + SseEvent sealed class
44|│   │   ├── database/                      # SQLite 持久化
45|│   │   │   ├── app_database.dart          #   drift 数据库定义
46|│   │   │   ├── session_dao.dart           #   会话 DAO
47|│   │   │   └── message_dao.dart           #   消息 DAO（含 reasoning/images_json）
48|│   │   ├── repositories/                  # 数据仓库（网络 + 本地）
49|│   │   │   ├── chat_repository.dart       #   聊天：拼装 API 请求 + 流式解析 + 写 DB
50|│   │   │   └── session_repository.dart    #   会话：CRUD
51|│   │   └── viewmodels/                    # 状态管理（ChangeNotifier）
52|│   │       ├── chat_viewmodel.dart        #   聊天页 VM（消息列表、流式状态、发送控制）
53|│   │       └── session_list_viewmodel.dart #  会话列表 VM
54|│   │
55|│   ├── protocol/                          # ═══ 网络通信层 ═══
56|│   │   ├── agents_api_client.dart         #   HTTP 客户端（chat/health）
57|│   │   └── agents_sse_client.dart         #   SSE 流式客户端（逐行解析）
58|│   │
59|│   ├── ui/                                # ═══ 界面层 ═══
60|│   │   ├── chatui/                        # 聊天模块
61|│   │   │   ├── chat_screen.dart           #   聊天主页面（Scaffold + 状态组装）
62|│   │   │   └── widgets/                   #   聊天专用组件
63|│   │   │       ├── message_bubble.dart    #     消息气泡（用户/AI 样式 + Markdown）
64|│   │   │       ├── thinking_section.dart  #     思考过程折叠区
65|│   │   │       ├── streaming_text.dart    #     流式输出文本 + 闪烁光标
66|│   │   │       ├── tool_progress_bar.dart #     工具执行进度条
67|│   │   │       ├── image_picker_sheet.dart #    图片选择 BottomSheet
68|│   │   │       └── chat_input_bar.dart    #     输入栏（文字 + 🎤 + 📎 + 发送/停止）
69|│   │   ├── sessionui/                     # 会话模块
70|│   │   │   └── session_list_panel.dart    #   侧栏会话列表（Drawer）
71|│   │   └── settingui/                     # 设置模块
72|│   │       └── settings_screen.dart       #   设置页面（base_url/api_key/测试连接）
73|│   │
74|│   └── utils/                             # ═══ 工具层 ═══
75|│       ├── logger.dart                    #   统一日志（级别过滤 + 模块标签 + 文件输出）
76|│       ├── audio_service.dart             #   录音（M4A）+ base64 编码
77|│       └── image_service.dart             #   图片选择 + 压缩 + base64 编码
78|│
79|├── test/                                  # 单元测试 + Widget 测试
80|├── pubspec.yaml
81|└── .env.example
82|```
83|
84|### 模块依赖规则
85|
86|```
87|ui/ ──(调用)──▶ agents/viewmodels/ ──(调用)──▶ agents/repositories/
88|                                                    │
89|                                    ┌───────────────┼───────────────┐
90|                                    ▼               ▼               ▼
91|                              protocol/        agents/database/   utils/
92|                            (网络通信)         (SQLite)         (录音/图片/日志)
93|```
94|
95|- **`ui/`** 只依赖 `agents/viewmodels/` 和 `utils/logger.dart`，不直接调 network/database
96|- **`agents/`** 是核心业务层，内部 models → database → repositories → viewmodels 自底向上
97|- **`protocol/`** 纯网络层，只被 repositories 调用
98|- **`utils/`** 横切工具，所有层可引用
99|
100|---
101|
102|## 一、协议设计
103|
104|Agents API Server 是 **OpenAI 兼容** 的 HTTP 端点。App 通过端口映射访问，等价于本地调用。
105|
106|```
107|App ── http://localhost:8642/v1/chat/completions ──▶ Agents Gateway
108|```
109|
110|详细协议见 `protocol/api-contract.md`。
111|
112|### 1.1 App 端配置
113|
114|| 配置项 | 说明 | 默认值 | 存储方式 |
115||--------|------|--------|----------|
116|| `base_url` | Agents API 地址 | `http://localhost:8642` | `flutter_secure_storage` |
117|| `api_key` | Bearer Token | — | `flutter_secure_storage` |
118|| `model` | 模型名 | `agents-agent` | 常量 |
119|
120|---
121|
122|## 二、数据模型
123|
124|### 2.1 Message（消息）— 含推理字段
125|
126|```dart
127|class Message {
128|  final String id;             // UUID
129|  final String sessionId;      // 所属会话 ID
130|  final String role;           // "user" | "assistant"
131|  final String content;        // 消息正文（Markdown 格式）
132|  final String? reasoningText; // 思考过程（仅 assistant 有，DeepSeek 模型）
133|  final List<String>? imageBase64s; // 用户发送的图片 base64 列表（仅 user 有）
134|  final DateTime createdAt;
135|  final int tokenCount;
136|
137|  // 便捷属性
138|  bool get hasReasoning => reasoningText != null && reasoningText!.isNotEmpty;
139|  bool get hasImages => imageBase64s != null && imageBase64s!.isNotEmpty;
140|}
141|```
142|
143|### 2.2 Session（会话）
144|
145|```dart
146|class Session {
147|  final String id;
148|  final String title;          // 取首条用户消息纯文本前 30 字
149|  final DateTime createdAt;
150|  final DateTime updatedAt;
151|  final int messageCount;
152|}
153|```
154|
155|### 2.3 ChatState（状态机）
156|
157|```dart
158|enum ChatState { idle, thinking, reasoning, streaming }
159|```
160|
161|**新增 `reasoning` 状态**：模型正在输出思考过程时的独立状态。
162|
163|```
164|          sendMessage()
165|IDLE ───────────────────────▶ THINKING
166|  ▲                              │
167|  │            收到第一个 reasoning│
168|  │                              ▼
169|  │                          REASONING  ← 思考过程中（展示折叠区）
170|  │                              │
171|  │           reasoning结束，收到 content│
172|  │                              ▼
173|  │                          STREAMING ── stopGeneration() ──▶ IDLE
174|  │                              │
175|  │                收到 [DONE]     │
176|  └──────────────────────────────┘
177|```
178|
179|---
180|
181|## 三、本地存储设计
182|
183|### 3.1 数据库（SQLite）
184|
185|**sessions 表：**
186|```sql
187|CREATE TABLE sessions (
188|  id           TEXT PRIMARY KEY,
189|  title        TEXT NOT NULL DEFAULT '新对话',
190|  created_at   INTEGER NOT NULL,
191|  updated_at   INTEGER NOT NULL,
192|  message_count INTEGER NOT NULL DEFAULT 0
193|);
194|```
195|
196|**messages 表（新增 reasoning + images 字段）：**
197|```sql
198|CREATE TABLE messages (
199|  id             TEXT PRIMARY KEY,
200|  session_id     TEXT NOT NULL,
201|  role           TEXT NOT NULL,
202|  content        TEXT NOT NULL,
203|  reasoning_text TEXT,              -- NULL 或推理过程全文
204|  images_json    TEXT,              -- NULL 或 JSON array of base64 strings
205|  created_at     INTEGER NOT NULL,
206|  token_count    INTEGER NOT NULL DEFAULT 0,
207|  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
208|);
209|
210|CREATE INDEX idx_messages_session ON messages(session_id, created_at);
211|```
212|
213|### 3.2 存储规则
214|
215|- **用户消息**：立即写入（content=文本, images_json=图片 base64 列表）
216|- **Assistant 消息**：流式完成后写入（content=Markdown 正文, reasoning_text=思考过程全文）
217|- **思考过程不逐 token 存**：内存中累积，仅在流完成后一次写入
218|- 其他规则不变（会话自动创建、切换加载、CASCADE 删除等）
219|
220|### 3.3 API 请求拼装
221|
222|```
223|从 SQLite 加载全部 messages
224|→ 逐条构建 API message:
225|   - user 且有 images: content = [{type:"text",text:"..."},{type:"image_url",...}]
226|   - user 纯文本:   content = "text"
227|   - assistant:     content = "markdown_text"（不带 reasoning_text，那是 UI 展示用）
228|→ POST /v1/chat/completions (stream=true)
229|```
230|
231|---
232|
233|## 四、核心功能实现
234|
235|### 4.1 思考过程展示
236|
237|**协议层**：SSE 流中先收到 `reasoning_content`（全部），再收到 `content`。见 `protocol/api-contract.md` 4.3.1 节。
238|
239|**UI 层**：
240|```
241|┌─────────────────────────────────────────┐
242|│  💭 思考过程                      ▼     │  ← ExpansionTile 折叠/展开
243|│  ┌─────────────────────────────────────┐│
244|│  │ 好的，用户想知道广州今天的天气。    ││  ← reasoningText 灰色斜体
245|│  │ 我需要调用搜索工具获取实时数据...   ││
246|│  └─────────────────────────────────────┘│
247|│  今天广州：多云转晴，26°C~33°C ☀️       │  ← content Markdown 渲染
248|└─────────────────────────────────────────┘
249|```
250|
251|**状态驱动**：
252|- `ChatState.reasoning`：显示 `💭 思考中...` 加载动画
253|- `ChatState.streaming`：思考完成→折叠默认收起、正文滚动输出
254|
255|**Widget 实现**：
256|```dart
257|// thinking_section.dart
258|// 用 ExpansionTile，默认不展开
259|// 仅 assistant 消息且 hasReasoning 时渲染在正文上方
260|// 流式时若 thinking 未完成→展开+loading；完成后→收起
261|```
262|
263|### 4.2 Markdown 渲染
264|
265|**依赖**：`flutter_markdown` 包。
266|
267|**MessageBubble 中集成**：
268|```dart
269|// 先判断消息类型：纯文本 vs Markdown
270|// - 用户消息 & 纯文本：Text widget
271|// - assistant 消息：MarkdownBody（支持代码块、表格、列表、粗斜体、链接）
272|```
273|
274|**约束**：
275|- 代码块加语言标签时启用语法高亮（flutter_markdown 内置）
276|- 链接点击用 `url_launcher` 外部打开
277|- 表格自适应宽度
278|- 不使用 WebView 方案
279|
280|### 4.3 图片消息发送
281|
282|**流程**：
283|```
284|点击输入栏 📎 按钮
285|  → showModalBottomSheet: [拍照 / 相册选择 / 取消]
286|  → ImagePicker 获取 File
287|  → 压缩：最长边 ≤ 2048px, JPEG quality 85%, ≤ 2MB
288|  → base64 编码
289|  → 拼入 API content 数组：
290|     [{"type":"text","text":"用户输入的文字"},
291|      {"type":"image_url","image_url":{"url":"data:image/jpeg;base64,..."}}]
292|  → POST /v1/chat/completions
293|```
294|
295|**UI**：
296|- 用户消息气泡中，文字下方显示缩略图
297|- 发送前可预览（点缩略图放大）
298|
299|**依赖**：`image_picker` + `flutter_image_compress`
300|
301|### 4.4 语音消息发送 — Agents STT
302|
303|**流程**：
304|```
305|按住 🎤 按钮录音
306|  → record 包生成 .m4a 文件（AAC, 16kHz 单声道, ≤ 60s）
307|  → base64 编码（不含 data: 前缀）
308|  → 拼入 API content 数组：
309|     [{"type":"text","text":"附言文字"},
310|      {"type":"input_audio","input_audio":{"data":"<base64>","format":"m4a"}}]
311|  → POST /v1/chat/completions
312|  → Agents Gateway STT 引擎自动转录
313|  → 转录文本作为 user message 注入 Agent
314|  → Agent 处理 → 流式返回回复
315|```
316|
317|**依赖**：`record` 包（跨平台录音，输出 M4A）。
318|
319|**Agents 侧前置条件**：`stt.enabled: true`，推荐 `provider: local`（faster-whisper，免费）。
320|
321|**录音 UI**：
322|- 长按 🎤 开始录音，松开自动发送
323|- 录音中显示波形脉冲动画 + 时长计数 + "上滑取消" 手势
324|- 用户可在录音前输入附言文字（如"帮我总结这段会议录音"）
325|
326|**服务封装**：
327|```dart
328|// utils/audio_service.dart
329|class AudioService {
330|  Future<bool> hasPermission();         // 麦克风权限
331|  Future<void> requestPermission();
332|  Future<void> startRecording();        // 开始录音
333|  Future<AudioRecordingResult> stopRecording(); // 停止，返回 base64
334|  Stream<Duration> get durationStream;  // 录音时长实时流
335|  void dispose();
336|}
337|
338|class AudioRecordingResult {
339|  final String base64Data;  // 纯 base64
340|  final String format;      // "m4a"
341|  final Duration duration;
342|}
343|```
344|
345|> **为什么不用本地 STT**：iOS 中文识别差、Android 需要 Google 服务、离线场景不可靠。Agents 端 faster-whisper 支持中英文混合，质量高且免额外 API 费用。
346|```
347|
348|---
349|
350|## 五、框架约束
351|
352|### 5.1 Flutter 通用约束
353|
354|1. **状态管理**：用 `ChangeNotifier` + `ListenableBuilder`，或 `Riverpod`。二选一，不要混用。
355|2. **网络**：用 `package:http` 发普通请求。SSE 流式用 `http.Client.send()` 获取 `StreamedResponse`，手动按行解析。
356|3. **序列化**：用 `freezed` + `json_serializable`。运行 `dart run build_runner build` 生成。
357|4. **数据库**：用 `drift`（推荐）或 `sqflite`。文件放 `getApplicationDocumentsDirectory()`。
358|5. **安全存储**：`flutter_secure_storage`，key 前缀 `agents_`。
359|6. **权限**：录音（麦克风）、图片（相机/相册）权限用 `permission_handler`。iOS 需配置 `NSMicrophoneUsageDescription`，Android 需 `RECORD_AUDIO`。
360|
361|### 5.2 ViewModel 接口契约
362|
363|```dart
364|class ChatViewModel extends ChangeNotifier {
365|  // --- 状态 ---
366|  List<Message> messages;
367|  String streamingReasoning;     // 流式思考过程暂态文本
368|  String streamingContent;       // 流式正文暂态文本
369|  ChatState chatState;           // idle / thinking / reasoning / streaming
370|  String? toolProgressMessage;
371|  String? errorMessage;
372|  Session? currentSession;
373|
374|  // --- 发送（支持多模态） ---
375|  Future<void> sendTextMessage(String text);
376|  Future<void> sendImageMessage({required String text, required List<String> imageBase64s});
377|  Future<void> sendVoiceMessage({required String base64Audio, required String format, String? caption});
378|
379|  // --- 控制 ---
380|  void stopGeneration();
381|  Future<void> createNewSession();
382|  Future<void> switchSession(String sessionId);
383|  Future<void> deleteSession(String sessionId);
384|}
385|```
386|
387|### 5.3 SSE 事件类型（含推理）
388|
389|```dart
390|sealed class SseEvent {}
391|class SseReasoning     extends SseEvent { final String text; }  // 思考 token
392|class SseToken         extends SseEvent { final String text; }  // 正文 token
393|class SseToolProgress  extends SseEvent { final String message; }
394|class SseDone          extends SseEvent {}
395|```
396|
397|### 5.4 网络层接口
398|
399|```dart
400|class AgentsApiClient {
401|  Future<ChatCompletionResponse> chatCompletion({
402|    required List<Map<String, dynamic>> messages,  // 含 content 数组
403|    bool stream = false,
404|  });
405|  Stream<SseEvent> streamChat({required List<Map<String, dynamic>> messages});
406|  Future<bool> healthCheck();
407|}
408|```
409|
410|### 4.5 UI 细节
411|
412|- **消息气泡**：用户靠右，`primaryContainer` 色；AI 靠左，`surfaceVariant` 色；`BorderRadius.circular(16)`
413|- **Markdown**：assistant 正文用 `MarkdownBody`，字体 15sp。
414|- **思考区**：灰色斜体、小字号、左侧竖线装饰。默认折叠。流式输出思考中时展开。
415|- **图片缩略图**：用户消息底部显示，宽高比保持，`BorderRadius.circular(8)`，点击全屏预览。
416|- **流式光标**：`streamingContent` 末尾闪烁 `▌`
417|- **工具进度**：`LinearProgressIndicator` + 文字
418|- **输入栏**：
419|  - 左侧 `📎` 按钮 → 图片选择 BottomSheet
420|  - 中间 `TextField`（多行自适应 1~5 行）
421|  - 右侧 `🎤` 按钮 → 长按录音 / 点击切语音模式
422|  - 最右侧发送/停止按钮（按 chatState 切换）
423|- **错误**：SnackBar 提示
424|
425|### 4.6 页面导航
426|
427|```
428|MaterialApp (Material 3, ThemeMode.system)
429|├── / → ChatScreen              聊天主界面
430|│   └── Drawer → SessionListPanel
431|└── /settings → SettingsScreen  设置页
432|```
433|
434|### 4.7 日志规范
435|
436|**统一日志工具 `utils/logger.dart`**：封装 `developer.log`，所有模块通过它输出日志。
437|
438|```dart
439|// 使用示例
440|import 'package:agent_dance/utils/logger.dart';
441|
442|final _log = Logger('ChatRepository');
443|
444|_log.info('开始发送消息', {'sessionId': session.id, 'textLen': text.length});
445|_log.warn('SSE 连接中断，准备重连', {'attempt': retryCount});
446|_log.error('API 返回 500', error, stackTrace);
447|```
448|
449|**日志级别**：
450|| 级别 | 用途 | 示例 |
451||------|------|------|
452|| `debug` | 开发调试细节 | SSE 解析到的每一行、DB 写入完成 |
453|| `info` | 关键操作节点 | "开始发送消息"、"流式完成"、"会话创建" |
454|| `warn` | 异常但可恢复 | 网络重试、数据为空、超时 |
455|| `error` | 不可恢复错误 | API 401、DB 写入失败、录音权限被拒 |
456|
457|**每条日志必须包含**：
458|- **模块标签**：构造函数参数，如 `'ChatViewModel'`、`'AgentsSseClient'`
459|- **上下文数据**：Map，包含关键 ID/参数/耗时
460|- **error 级别**：必须带 `error` 对象和 `stackTrace`
461|
462|**生产/开发行为**：
463|- 开发：`debug` 及以上全输出到控制台
464|- 生产：`info` 及以上输出到文件（`logger.setOutput(LogOutput.file)`），保留最近 7 天
465|
466|---
467|
468|## 六、MVP 功能清单
469|
470|- [ ] **设置页**：base_url + api_key + 测试连接
471|- [ ] **文字对话**：发送文字，流式显示回复（Markdown 渲染）
472|- [ ] **思考过程**：DeepSeek 模型的 reasoning 流式展示 + 折叠
473|- [ ] **图片发送**：拍照/相册 → 压缩 → base64 → 发送
474|- [ ] **语音发送**：录音 → 本地 STT → 文本填入输入框 → 发送
475|- [ ] **会话管理**：自动创建 + 列表切换/删除
476|- [ ] **历史加载**：SQLite 加载历史消息（含思考过程 + 图片）
477|- [ ] **工具进度**：`agents.tool.progress` 事件展示
478|- [ ] **停止生成**：流式输出中可停止
479|- [ ] **错误处理**：401/网络不通/超时 SnackBar 提示
480|- [ ] **暗色模式**：`ThemeMode.system`
481|
482|---
483|
484|## 七、代码规范
485|
486|- **命名**：类/枚举 `UpperCamelCase`，函数/变量 `lowerCamelCase`，文件名 `snake_case.dart`
487|- **注释**：用中文
488|- **文件粒度**：一个文件一个核心类
489|- **导入顺序**：dart: → package: → 相对路径
490|- **空安全**：全 null-safety
491|
492|---
493|
494|## 八、开发流程
495|
496|1. `flutter create agent_dance` 创建项目
497|2. 配置 `pubspec.yaml` 依赖（flutter_markdown, record, image_picker, flutter_image_compress, drift/sqflite, flutter_secure_storage, freezed, http, permission_handler 等）
498|3. 读 `protocol/api-contract.md` 理解 API 协议（重点关注 reasoning_content 流式时序）
499|4. 搭数据库（drift tables with reasoning_text + images_json 字段）
500|5. 实现 `AgentsApiClient` + `AgentsSseClient`（含 reasoning_content 解析）
501|6. 实现 `AudioService` + `ImageService`
502|7. 实现 `ChatRepository`
503|8. 实现 `ChatViewModel`（含 reasoning/streaming 状态切换）
504|9. 写 UI（ThinkingSection + MarkdownBody + ImagePickerSheet + 录音按钮）
505|10. 真机联调 Agents API Server

### 构建打包

产物命名格式：`agent_dance-{主版本号}-{打包日期}`

| 平台 | 产物 | 命名示例 |
|------|------|---------|
| Android | APK (arm64) | `agent_dance-1.0.0-20260615.apk` |
| iOS | IPA | `agent_dance-1.0.0-20260615.ipa` |

规则：
- **主版本号**：从 `pubspec.yaml` 的 `version` 字段取，格式 `x.y.z`
- **打包日期**：`YYYYMMDD`，如 `20260615`
- **Android 架构**：只打 arm64-v8a，不考虑 armeabi-v7a（32位）和 x86_64
- 严禁用 `release`、`latest`、`debug` 等模糊标签
506|
507|---
508|
509|*文档版本: v3.0*
510|*日期: 2026-06-12*
511|