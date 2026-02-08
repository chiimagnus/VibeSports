# Claude Code & Codex（PixelHQ Bridge 监听机制说明）

本文档描述 PixelHQ Bridge（`pixelhq`）如何“检测”Claude Code 与 Codex CLI，以及它实际监听/解析的本地会话日志来源、数据流与隐私剥离策略。

## 一句话结论：这里的“检测”是什么

- **Claude Code 检测**：是否能解析到 Claude 配置目录，且存在 `projects/`（会话 JSONL 落盘目录）。实现见 `src/config.ts`。
- **Codex CLI 检测**：是否能解析到 Codex 配置目录，且存在 `sessions/`（rollout JSONL 落盘目录）。实现见 `src/config.ts`。
- **运行中活动感知**：不是探测进程/终端/PTY，而是 **监听这些目录下的 JSONL 文件追加写入**，增量读取新行并解析。实现见 `src/watcher.ts`。

## 架构总览（两者共用）

数据流（两种 agent 共用一条管线）：

1. **Watcher**：`chokidar` 监听 JSONL 文件 `add/change`，按文件偏移量增量读取新增字节并按行切分（类似 tail）。见 `src/watcher.ts`。
2. **Parser**：对每行做 `JSON.parse`，注入 `_sessionId/_agentId`，再按 `source` 路由到不同 adapter。见 `src/parser.ts`。
3. **Adapter**：把 raw JSONL 映射为最小化的 `PixelEvent`（活动/工具/错误/agent 等），并执行隐私剥离（allowlist）。见 `src/adapters/claude-code.ts`、`src/adapters/codex.ts`。
4. **WebSocket**：仅对通过配对认证的客户端广播 `PixelEvent`。见 `src/websocket.ts`、`src/auth.ts`。

## Claude Code

### 目录解析与“检测”

Claude 目录候选（优先级从高到低）：

- `--claude-dir <path>`
- `CLAUDE_CONFIG_DIR`
- `~/.claude`
- `~/.config/claude`

当 `<claudeDir>/projects` 存在时，认为可用；否则会报错提示手动指定。见 `src/config.ts` 的 `resolveClaudeDir()`。

### 监听的文件与会话/子代理识别

Watcher 会监听：

- `~/.claude/projects/*/*.jsonl`
- `~/.claude/projects/*/*/subagents/*.jsonl`

并由文件路径解析出：

- **普通会话**：`sessionId = 文件名(去 .jsonl)`，`project = 目录名`
- **subagent 会话**：`agentId = 文件名`，`sessionId = subagents 上一级目录名`，`project = sessionId 上一级目录名`

见 `src/watcher.ts` 的 `parseFilePath()`。

### Claude JSONL → PixelEvent 的映射（隐私剥离后）

Claude adapter 只处理少数 raw 类型，且不透传文本内容：

- `assistant.message.content[].type === thinking` → `activity: thinking`
- `assistant.message.content[].type === text` → `activity: responding`（仅携带 token 数，不携带文本）
- `assistant.message.content[].type === tool_use` → `tool: started`（按工具名映射分类）
- `user.userType === tool_result` → `tool: completed/error`（不透传输出内容）
- `summary` → `summary`

实现见 `src/adapters/claude-code.ts`。

工具分类映射（示例）见 `src/config.ts` 的 `TOOL_TO_CATEGORY`。

### Claude 的“安全上下文”（allowlist）

仅允许非常有限的上下文出现在广播事件中：

- `Read/Write/Edit`：仅保留 `file_path` 的 basename（如 `auth.ts`）
- `Bash`：仅保留 `description`（用户给的摘要，不是命令）
- `Grep/Glob`：仅保留 `pattern`
- `Task`：仅保留 `subagent_type`
- `TodoWrite`：仅保留 todo 数量（如 `3 items`）
- 其他工具：不携带上下文

实现见 `src/adapters/claude-code.ts` 的 `extractSafeContext()`。

## Codex CLI

### 目录解析与“检测”

Codex 目录候选（优先级从高到低）：

- `--codex-dir <path>`
- `CODEX_HOME`
- `~/.codex`

当 `<codexDir>/sessions` 存在时认为可用；如果找不到则视为未安装/未使用过（返回 `null`）。见 `src/config.ts` 的 `resolveCodexDir()`。

### 监听的文件与 sessionId 识别

Watcher 额外监听（若存在 `codexSessionsDir`）：

- `~/.codex/sessions/**/**/*.jsonl`（实现为 `join(config.codexSessionsDir, '**', '*.jsonl')`）

并假设 Codex rollout 文件名形如：

- `rollout-YYYY-MM-DDThh-mm-ss-{uuid}.jsonl`

Watcher 会从文件名尾部提取 UUID 作为 `sessionId`，否则退回为文件名；`project` 固定为 `codex`，`source` 为 `codex`。见 `src/watcher.ts` 的 `parseCodexFilePath()`。

### Codex JSONL → PixelEvent 的映射（隐私剥离后）

Codex adapter 主要处理：

- `raw.type === response_item` 且 `raw.payload.type` 为：
  - `message`：
    - `role=user` 且 content 含 `input_text` → `activity: user_prompt`
    - `role=assistant` 且 content 含 `output_text` → `activity: responding`
  - `reasoning` → `activity: thinking`
  - `function_call` → `tool: started`（按工具名映射分类；部分会额外生成 `activity.waiting`/`agent.spawned`）
  - `function_call_output` → `tool: completed/error`（不透传 output）
  - `local_shell_call` → `tool: started/completed/error`（终端类）
  - `web_search_call` → `tool: started/completed/error`（搜索类）
  - `custom_tool_call` / `custom_tool_call_output` → `tool`（other）

其他 raw 类型（`session_meta/turn_context/compacted/event_msg` 等）会被忽略。实现见 `src/adapters/codex.ts`。

工具分类映射见 `src/config.ts` 的 `CODEX_TOOL_TO_CATEGORY`。

### Codex 的“安全上下文”（allowlist）

Codex 对 `function_call.arguments`（字符串 JSON）做解析，并仅在少数工具上提取上下文：

- `read_file/view_image`：仅保留 `path` 或 `file_path` 的 basename
- `grep_files`：仅保留 `pattern`
- 其他：不携带上下文

实现见 `src/adapters/codex.ts` 的 `extractSafeContext()`。

## 广播事件与认证（两者共用）

- 广播内容是统一的 `PixelEvent`（`session/activity/tool/agent/error/summary`）。类型定义见 `src/types.ts`。
- WebSocket 只对通过认证的客户端广播：
  - 首次连接使用 **6 位配对码**换取 token
  - token 会持久化到本地 JSON 文件（见 `src/auth.ts`，路径由 `src/config.ts` 的 `authTokenFile` 决定）
- Bonjour/mDNS 负责让 iOS 端在局域网发现服务。见 `src/bonjour.ts`。

## 隐私边界说明

- 本项目会 **读取并解析** 本地 JSONL 会话日志（这一步不可避免地把原始内容带入进程内存）。
- 但对外广播时，adapter 使用 allowlist 仅保留动画所需的结构化元数据；prompt、思考文本、代码片段、完整路径、命令与输出内容不会被放入广播事件中。

---

## 附录：核心源码（快照）

说明：

- 以下为撰写本文档时的核心实现源码原文（便于离线审计）。
- 生成时仓库版本：`d094d96`。
- 若你只关心“检测/监听”本质，优先阅读 `src/config.ts` 与 `src/watcher.ts`。

### `src/config.ts`

```ts
import { homedir } from 'os';
import { join, dirname } from 'path';
import { existsSync, readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import type { ToolMapping } from './types.js';

// ---------------------------------------------------------------------------
// Package version
// ---------------------------------------------------------------------------

const __dirname = dirname(fileURLToPath(import.meta.url));

function findPackageJson(startDir: string): string {
  let dir = startDir;
  while (true) {
    const candidate = join(dir, 'package.json');
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) throw new Error('Could not find package.json');
    dir = parent;
  }
}

const pkg = JSON.parse(readFileSync(findPackageJson(__dirname), 'utf-8')) as {
  version: string;
};

// ---------------------------------------------------------------------------
// Claude directory auto-detection
// ---------------------------------------------------------------------------

function getCliArg(name: string): string | null {
  const flag = `--${name}`;
  const idx = process.argv.indexOf(flag);
  return idx !== -1 && idx + 1 < process.argv.length ? process.argv[idx + 1]! : null;
}

function hasCliFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

interface ResolvedClaudeDir {
  claudeDir: string;
  projectsDir: string;
  resolvedVia: string;
}

export function resolveClaudeDir(): ResolvedClaudeDir {
  const home = homedir();
  const candidates: { path: string | null | undefined; via: string }[] = [
    { path: getCliArg('claude-dir'), via: '--claude-dir flag' },
    { path: process.env.CLAUDE_CONFIG_DIR, via: 'CLAUDE_CONFIG_DIR env' },
    { path: join(home, '.claude'), via: 'default (~/.claude)' },
    { path: join(home, '.config', 'claude'), via: 'XDG (~/.config/claude)' },
  ];

  for (const { path, via } of candidates) {
    if (!path) continue;
    const projectsDir = join(path, 'projects');
    if (existsSync(projectsDir)) {
      return { claudeDir: path, projectsDir, resolvedVia: via };
    }
    if (existsSync(path)) {
      return { claudeDir: path, projectsDir, resolvedVia: `${via} (no projects/ yet)` };
    }
  }

  throw new Error(
    'Could not find Claude config directory. Tried:\n' +
    candidates
      .filter(c => c.path)
      .map(c => `  - ${c.path} (${c.via})`)
      .join('\n') +
    '\n\nUse --claude-dir <path> to specify the directory manually.'
  );
}

// ---------------------------------------------------------------------------
// Codex directory auto-detection
// ---------------------------------------------------------------------------

interface ResolvedCodexDir {
  codexDir: string;
  codexSessionsDir: string;
  resolvedVia: string;
}

export function resolveCodexDir(): ResolvedCodexDir | null {
  const home = homedir();
  const candidates: { path: string | null | undefined; via: string }[] = [
    { path: getCliArg('codex-dir'), via: '--codex-dir flag' },
    { path: process.env.CODEX_HOME, via: 'CODEX_HOME env' },
    { path: join(home, '.codex'), via: 'default (~/.codex)' },
  ];

  for (const { path, via } of candidates) {
    if (!path) continue;
    const sessionsDir = join(path, 'sessions');
    if (existsSync(sessionsDir)) {
      return { codexDir: path, codexSessionsDir: sessionsDir, resolvedVia: via };
    }
    if (existsSync(path)) {
      return { codexDir: path, codexSessionsDir: sessionsDir, resolvedVia: `${via} (no sessions/ yet)` };
    }
  }

  return null;
}

// Resolve once at import time
const resolved = resolveClaudeDir();
const resolvedCodex = resolveCodexDir();

// ---------------------------------------------------------------------------
// Bridge server configuration
// ---------------------------------------------------------------------------

export const config = {
  claudeDir: resolved.claudeDir,
  projectsDir: resolved.projectsDir,
  claudeDirResolvedVia: resolved.resolvedVia,
  codexDir: resolvedCodex?.codexDir ?? null as string | null,
  codexSessionsDir: resolvedCodex?.codexSessionsDir ?? null as string | null,
  codexDirResolvedVia: resolvedCodex?.resolvedVia ?? null as string | null,
  version: pkg.version,
  wsPort: Number(getCliArg('port') || process.env.PIXEL_OFFICE_PORT || 8765),
  bonjourName: 'Pixel Office Bridge',
  bonjourType: 'pixeloffice',
  watchDebounce: 100,
  sessionTtlMs: 2 * 60 * 1000,
  sessionReapIntervalMs: 30 * 1000,
  authTokenFile: join(resolved.claudeDir, 'pixel-office-auth.json'),
  verbose: hasCliFlag('verbose'),
  nonInteractive: hasCliFlag('yes') || hasCliFlag('y') || process.env.CI === 'true',
};

// ---------------------------------------------------------------------------
// PixelEvent types
// ---------------------------------------------------------------------------

export const PixelEventType = {
  SESSION: 'session',
  ACTIVITY: 'activity',
  TOOL: 'tool',
  AGENT: 'agent',
  ERROR: 'error',
  SUMMARY: 'summary',
} as const;

// ---------------------------------------------------------------------------
// Tool category mapping
// ---------------------------------------------------------------------------

export const ToolCategory = {
  FILE_READ: 'file_read',
  FILE_WRITE: 'file_write',
  TERMINAL: 'terminal',
  SEARCH: 'search',
  PLAN: 'plan',
  COMMUNICATE: 'communicate',
  SPAWN_AGENT: 'spawn_agent',
  NOTEBOOK: 'notebook',
  OTHER: 'other',
} as const;

export const TOOL_TO_CATEGORY: Record<string, ToolMapping> = {
  Read:            { category: ToolCategory.FILE_READ,    detail: 'read' },
  Write:           { category: ToolCategory.FILE_WRITE,   detail: 'write' },
  Edit:            { category: ToolCategory.FILE_WRITE,   detail: 'edit' },
  Bash:            { category: ToolCategory.TERMINAL,     detail: 'bash' },
  Grep:            { category: ToolCategory.SEARCH,       detail: 'grep' },
  Glob:            { category: ToolCategory.SEARCH,       detail: 'glob' },
  WebFetch:        { category: ToolCategory.SEARCH,       detail: 'web_fetch' },
  WebSearch:       { category: ToolCategory.SEARCH,       detail: 'web_search' },
  Task:            { category: ToolCategory.SPAWN_AGENT,  detail: 'task' },
  TodoWrite:       { category: ToolCategory.PLAN,         detail: 'todo' },
  EnterPlanMode:   { category: ToolCategory.PLAN,         detail: 'enter_plan' },
  ExitPlanMode:    { category: ToolCategory.PLAN,         detail: 'exit_plan' },
  AskUserQuestion: { category: ToolCategory.COMMUNICATE,  detail: 'ask_user' },
  NotebookEdit:    { category: ToolCategory.NOTEBOOK,     detail: 'notebook' },
};

// ---------------------------------------------------------------------------
// Codex tool category mapping
// ---------------------------------------------------------------------------

export const CODEX_TOOL_TO_CATEGORY: Record<string, ToolMapping> = {
  shell:              { category: ToolCategory.TERMINAL,     detail: 'bash' },
  exec_command:       { category: ToolCategory.TERMINAL,     detail: 'bash' },
  apply_patch:        { category: ToolCategory.FILE_WRITE,   detail: 'patch' },
  read_file:          { category: ToolCategory.FILE_READ,    detail: 'read' },
  list_dir:           { category: ToolCategory.SEARCH,       detail: 'list_dir' },
  grep_files:         { category: ToolCategory.SEARCH,       detail: 'grep' },
  view_image:         { category: ToolCategory.FILE_READ,    detail: 'image' },
  get_memory:         { category: ToolCategory.OTHER,        detail: 'memory' },
  plan:               { category: ToolCategory.PLAN,         detail: 'plan' },
  update_plan:        { category: ToolCategory.PLAN,         detail: 'plan' },
  request_user_input: { category: ToolCategory.COMMUNICATE,  detail: 'ask_user' },
  spawn_agent:        { category: ToolCategory.SPAWN_AGENT,  detail: 'collab' },
  send_input:         { category: ToolCategory.SPAWN_AGENT,  detail: 'collab' },
  wait:               { category: ToolCategory.SPAWN_AGENT,  detail: 'collab' },
  close_agent:        { category: ToolCategory.SPAWN_AGENT,  detail: 'collab' },
  web_search:         { category: ToolCategory.SEARCH,       detail: 'web_search' },
};
```

### `src/watcher.ts`

```ts
import { watch, type FSWatcher } from 'chokidar';
import { createReadStream, statSync } from 'fs';
import { createInterface } from 'readline';
import { join, basename, dirname } from 'path';
import { TypedEmitter } from './typed-emitter.js';
import { config } from './config.js';
import { logger } from './logger.js';
import type { WatcherSessionEvent, WatcherLineEvent, ParsedFilePath } from './types.js';

interface WatcherEvents {
  session: [WatcherSessionEvent];
  line: [WatcherLineEvent];
  error: [Error];
}

/**
 * Watches agent session JSONL files for new events.
 * Supports Claude Code and Codex CLI.
 * Emits 'line' events for each new JSONL line.
 */
export class SessionWatcher extends TypedEmitter<WatcherEvents> {
  private watcher: FSWatcher | null;
  private filePositions: Map<string, number>;
  private trackedSessions: Set<string>;

  constructor() {
    super();
    this.watcher = null;
    this.filePositions = new Map();
    this.trackedSessions = new Set();
  }

  start(): void {
    const watchPatterns = [
      join(config.projectsDir, '*', '*.jsonl'),
      join(config.projectsDir, '*', '*', 'subagents', '*.jsonl'),
    ];

    if (config.codexSessionsDir) {
      watchPatterns.push(join(config.codexSessionsDir, '**', '*.jsonl'));
    }

    logger.verbose('Watcher', 'Starting file watcher...');

    this.watcher = watch(watchPatterns, {
      persistent: true,
      ignoreInitial: false,
      awaitWriteFinish: {
        stabilityThreshold: config.watchDebounce,
        pollInterval: 50,
      },
      usePolling: false,
    });

    this.watcher
      .on('add', (filePath: string) => this.handleFileAdd(filePath))
      .on('change', (filePath: string) => this.handleFileChange(filePath))
      .on('error', (error: Error) => this.emit('error', error));

    logger.verbose('Watcher', 'File watcher started');
  }

  async stop(): Promise<void> {
    if (this.watcher) {
      await this.watcher.close();
      this.watcher = null;
      logger.verbose('Watcher', 'File watcher stopped');
    }
  }

  handleFileAdd(filePath: string): void {
    try {
      const stats = statSync(filePath);
      const now = Date.now();
      const modifiedAgo = now - stats.mtimeMs;

      const recencyThreshold = 10 * 60 * 1000;

      if (modifiedAgo > recencyThreshold) {
        this.filePositions.set(filePath, stats.size);
        return;
      }

      const { sessionId, agentId, project, source } = this.parseFilePath(filePath);
      const minutesAgo = Math.round(modifiedAgo / 60000);

      logger.verbose('Watcher', `Tracking recent session (${source}): ${sessionId.slice(0, 8)}... (${minutesAgo}m ago)`);

      this.filePositions.set(filePath, stats.size);
      this.trackedSessions.add(sessionId);

      this.emit('session', {
        sessionId,
        agentId,
        project,
        filePath,
        action: 'discovered',
        source,
      });
    } catch (err) {
      logger.error('Watcher', `Error reading file stats: ${(err as Error).message}`);
    }
  }

  async handleFileChange(filePath: string): Promise<void> {
    const { sessionId, agentId, source } = this.parseFilePath(filePath);
    const previousPosition = this.filePositions.get(filePath) || 0;

    try {
      const stats = statSync(filePath);
      const currentSize = stats.size;

      if (currentSize <= previousPosition) {
        return;
      }

      if (!this.trackedSessions.has(sessionId)) {
        const { project } = this.parseFilePath(filePath);
        logger.verbose('Watcher', `Session became active (${source}): ${sessionId.slice(0, 8)}...`);
        this.trackedSessions.add(sessionId);

        this.emit('session', {
          sessionId,
          agentId,
          project,
          filePath,
          action: 'discovered',
          source,
        });
      }

      const newLines = await this.readNewLines(filePath, previousPosition);
      this.filePositions.set(filePath, currentSize);

      for (const line of newLines) {
        if (line.trim()) {
          this.emit('line', {
            line,
            sessionId,
            agentId,
            filePath,
            source,
          });
        }
      }
    } catch (err) {
      logger.error('Watcher', `Error reading file changes: ${(err as Error).message}`);
    }
  }

  readNewLines(filePath: string, startPosition: number): Promise<string[]> {
    return new Promise((resolve, reject) => {
      const lines: string[] = [];
      const stream = createReadStream(filePath, {
        start: startPosition,
        encoding: 'utf8',
      });

      const rl = createInterface({
        input: stream,
        crlfDelay: Infinity,
      });

      rl.on('line', (line: string) => lines.push(line));
      rl.on('close', () => resolve(lines));
      rl.on('error', reject);
    });
  }

  parseFilePath(filePath: string): ParsedFilePath {
    // Codex rollout files: ~/.codex/sessions/YYYY/MM/DD/rollout-...-{uuid}.jsonl
    if (config.codexSessionsDir && filePath.startsWith(config.codexSessionsDir)) {
      return this.parseCodexFilePath(filePath);
    }

    const fileName = basename(filePath, '.jsonl');
    const dirPath = dirname(filePath);

    const isSubagent = dirPath.includes('/subagents');

    let sessionId: string;
    let agentId: string | null = null;
    let project: string;

    if (isSubagent) {
      agentId = fileName;
      const subagentsDir = dirname(dirPath);
      sessionId = basename(subagentsDir);
      project = basename(dirname(subagentsDir));
    } else {
      sessionId = fileName;
      project = basename(dirPath);
    }

    const projectPath = project.replace(/^-/, '/').replace(/-/g, '/');

    return {
      sessionId,
      agentId,
      project: projectPath,
      source: 'claude-code',
    };
  }

  private parseCodexFilePath(filePath: string): ParsedFilePath {
    const fileName = basename(filePath, '.jsonl');
    // Extract UUID from: rollout-YYYY-MM-DDThh-mm-ss-{uuid}
    const uuidMatch = fileName.match(
      /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i,
    );
    const sessionId = uuidMatch ? uuidMatch[1]! : fileName;

    return {
      sessionId,
      agentId: null,
      project: 'codex',
      source: 'codex',
    };
  }
}
```

### `src/parser.ts`

```ts
import { claudeCodeAdapter } from './adapters/claude-code.js';
import { codexAdapter } from './adapters/codex.js';
import type { PixelEvent, RawJsonlEvent } from './types.js';

type Adapter = (raw: RawJsonlEvent) => PixelEvent[];

const adapters: Record<string, Adapter> = {
  'claude-code': claudeCodeAdapter,
  'codex': codexAdapter,
};

/**
 * Parse a raw JSONL line from a session file.
 * Source-agnostic — just validates JSON and injects session metadata.
 */
export function parseJsonlLine(
  line: string,
  sessionId: string,
  agentId: string | null = null,
): RawJsonlEvent | null {
  const trimmed = line.trim();
  if (!trimmed) return null;

  try {
    const raw = JSON.parse(trimmed) as RawJsonlEvent;
    raw._sessionId = sessionId;
    raw._agentId = agentId;
    return raw;
  } catch (err) {
    console.error(`[Parser] Failed to parse JSONL: ${(err as Error).message}`);
    return null;
  }
}

/**
 * Transform a raw parsed JSONL object into PixelEvent(s) using the appropriate adapter.
 */
export function transformToPixelEvents(
  raw: RawJsonlEvent,
  source: string = 'claude-code',
): PixelEvent[] {
  const adapter = adapters[source];
  if (!adapter) {
    console.warn(`[Parser] No adapter for source: ${source}`);
    return [];
  }
  return adapter(raw);
}
```

### `src/index.ts`

```ts
import { existsSync } from 'fs';
import { SessionWatcher } from './watcher.js';
import { SessionManager } from './session.js';
import { BroadcastServer } from './websocket.js';
import { BonjourAdvertiser } from './bonjour.js';
import { AuthManager } from './auth.js';
import { parseJsonlLine, transformToPixelEvents } from './parser.js';
import { createAgentEvent } from './pixel-events.js';
import { config } from './config.js';
import { logger } from './logger.js';

export interface PreflightResult {
  claudeDir: string;
  codexDir: string | null;
  port: number;
  pairedDevices: number;
}

/**
 * Pixel Office Bridge Server
 *
 * Watches AI agent session files (Claude Code, Codex CLI) and broadcasts
 * events to connected iOS clients via WebSocket.
 */
export class PixelOfficeBridge {
  private watcher: SessionWatcher;
  private sessionManager: SessionManager;
  private authManager: AuthManager;
  private server: BroadcastServer;
  private bonjour: BonjourAdvertiser;
  private isRunning: boolean;

  constructor() {
    this.watcher = new SessionWatcher();
    this.sessionManager = new SessionManager();
    this.authManager = new AuthManager();
    this.server = new BroadcastServer(this.authManager);
    this.bonjour = new BonjourAdvertiser();
    this.isRunning = false;
  }

  /** Run pre-flight validation without starting anything */
  preflight(): PreflightResult {
    const hasClaudeCode = existsSync(config.claudeDir);
    const hasCodex = config.codexDir !== null && existsSync(config.codexDir);

    if (!hasClaudeCode && !hasCodex) {
      throw new Error(
        'No supported agent found. Tried:\n' +
        `  - Claude Code at ${config.claudeDir}\n` +
        (config.codexDir ? `  - Codex at ${config.codexDir}\n` : '') +
        '\nInstall Claude Code or Codex CLI to use the bridge.'
      );
    }

    return {
      claudeDir: config.claudeDir,
      codexDir: config.codexDir,
      port: config.wsPort,
      pairedDevices: this.authManager.tokens.size,
    };
  }

  /** Get the pairing code (generated at construction) */
  get pairingCode(): string {
    return this.authManager.pairingCode;
  }

  /** Get the local IP address after bonjour starts */
  get localIP(): string {
    return this.bonjour.localIP;
  }

  async start(): Promise<void> {
    try {
      await this.server.start();
      logger.info('\u2713 WebSocket server on port ' + config.wsPort);

      this.server.setStateRequestHandler(() => {
        return this.sessionManager.getState();
      });

      this.bonjour.start();
      logger.info('\u2713 Broadcasting on local network (' + this.bonjour.localIP + ')');

      this.setupEventHandlers();
      this.watcher.start();
      this.sessionManager.startReaper();

      this.isRunning = true;

      logger.verbose('Bridge', `Claude dir: ${config.claudeDir} (${config.claudeDirResolvedVia})`);
      logger.verbose('Bridge', `Watching: ${config.projectsDir}`);

      if (config.codexDir) {
        logger.verbose('Bridge', `Codex dir: ${config.codexDir} (${config.codexDirResolvedVia})`);
        logger.verbose('Bridge', `Watching: ${config.codexSessionsDir}`);
      }

      this.setupShutdownHandlers();

    } catch (error) {
      logger.error('Bridge', `Failed to start: ${(error as Error).message}`);
      throw error;
    }
  }

  private setupEventHandlers(): void {
    this.watcher.on('session', ({ sessionId, agentId, project, source }) => {
      this.sessionManager.registerSession(sessionId, project, agentId, source || 'claude-code');

      if (agentId) {
        this.sessionManager.correlateAgentFile(sessionId, agentId);
      }
    });

    this.watcher.on('line', ({ line, sessionId, agentId, filePath, source }) => {
      this.handleNewLine(line, sessionId, agentId, filePath, source || 'claude-code');
    });

    this.watcher.on('error', (error) => {
      logger.error('Bridge', `Watcher error: ${error.message}`);
    });

    this.sessionManager.on('event', (event) => {
      this.server.broadcast(event);
    });
  }

  private handleNewLine(
    line: string,
    sessionId: string,
    agentId: string | null,
    filePath: string,
    source: string = 'claude-code',
  ): void {
    if (!this.sessionManager.sessions.has(sessionId)) {
      const { project } = this.watcher.parseFilePath(filePath);
      this.sessionManager.registerSession(sessionId, project, agentId, source);
    }

    const resolvedAgentId = agentId
      ? this.sessionManager.resolveAgentId(sessionId, agentId)
      : agentId;
    const raw = parseJsonlLine(line, sessionId, resolvedAgentId);
    if (!raw) return;

    const events = transformToPixelEvents(raw, source);

    this.sessionManager.recordActivity(sessionId);

    for (const event of events) {
      if (event.type === 'tool' && event.tool === 'spawn_agent' && event.status === 'started') {
        this.sessionManager.trackTaskSpawn(sessionId, event.toolUseId);
      }

      if (event.type === 'tool' && (event.status === 'completed' || event.status === 'error')) {
        if (this.sessionManager.handleTaskResult(sessionId, event.toolUseId)) {
          const agentCompletedEvent = createAgentEvent(
            sessionId,
            event.toolUseId,
            event.timestamp,
            event.status === 'error' ? 'error' : 'completed',
          );
          this.server.broadcast(agentCompletedEvent);
          this.sessionManager.agentCompleted(sessionId, event.toolUseId);
        }
      }

      this.server.broadcast(event);
    }
  }

  private setupShutdownHandlers(): void {
    const shutdown = async (signal: string) => {
      logger.blank();
      logger.verbose('Bridge', `Received ${signal}, shutting down...`);

      await this.stop();
      process.exit(0);
    };

    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
  }

  async stop(): Promise<void> {
    this.isRunning = false;

    await this.watcher.stop();
    this.bonjour.stop();
    await this.server.stop();
    this.sessionManager.cleanup();

    logger.verbose('Bridge', 'Shutdown complete');
  }
}
```

### `src/adapters/claude-code.ts`

```ts
import {
  createActivityEvent,
  createToolEvent,
  createAgentEvent,
  createErrorEvent,
  createSummaryEvent,
  toBasename,
} from '../pixel-events.js';
import { TOOL_TO_CATEGORY, ToolCategory } from '../config.js';
import type { PixelEvent, RawJsonlEvent, RawUsage, TokenUsage } from '../types.js';

/**
 * Transform a raw Claude Code JSONL object into PixelEvent(s).
 * Privacy-safe: strips all text content, full paths, commands, URLs, and queries.
 */
export function claudeCodeAdapter(raw: RawJsonlEvent): PixelEvent[] {
  const sessionId = raw._sessionId;
  const agentId = raw._agentId || null;
  const timestamp = raw.timestamp || new Date().toISOString();

  switch (raw.type) {
    case 'assistant':
      return handleAssistant(raw, sessionId, agentId, timestamp);

    case 'user':
      return handleUser(raw, sessionId, agentId, timestamp);

    case 'summary':
      return [createSummaryEvent(sessionId, timestamp)];

    case 'system':
    case 'progress':
    case 'queue-operation':
      return [];

    default:
      return [];
  }
}

// ---------------------------------------------------------------------------
// Assistant message handling
// ---------------------------------------------------------------------------

function handleAssistant(
  raw: RawJsonlEvent,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const events: PixelEvent[] = [];
  const message = raw.message;
  if (!message?.content) return events;

  // content must be an array for assistant messages
  if (!Array.isArray(message.content)) return events;

  const tokens = extractTokens(message.usage ?? null);

  for (const block of message.content) {
    switch (block.type) {
      case 'thinking':
        events.push(
          createActivityEvent(sessionId, agentId, timestamp, 'thinking'),
        );
        break;

      case 'text':
        if (block.text === '(no content)') {
          events.push(
            createActivityEvent(sessionId, agentId, timestamp, 'thinking'),
          );
        } else {
          events.push(
            createActivityEvent(sessionId, agentId, timestamp, 'responding', tokens),
          );
        }
        break;

      case 'tool_use':
        events.push(
          buildToolStartedEvent(sessionId, agentId, timestamp, block),
        );
        if (block.name === 'Task') {
          events.push(
            createAgentEvent(
              sessionId,
              block.id,
              timestamp,
              'spawned',
              (block.input as Record<string, unknown>)?.subagent_type as string || 'general',
            ),
          );
        }
        if (block.name === 'AskUserQuestion') {
          events.push(
            createActivityEvent(sessionId, agentId, timestamp, 'waiting'),
          );
        }
        break;
    }
  }

  return events;
}

// ---------------------------------------------------------------------------
// User message handling
// ---------------------------------------------------------------------------

function handleUser(
  raw: RawJsonlEvent,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const events: PixelEvent[] = [];
  const message = raw.message;
  if (!message?.content) return events;

  const content = typeof message.content === 'string'
    ? [{ type: 'text' as const, text: message.content }]
    : message.content;

  if (raw.userType === 'tool_result') {
    for (const block of content) {
      if (block.type === 'tool_result') {
        const isError =
          block.is_error === true ||
          (typeof block.content === 'string' && block.content.includes('Error'));

        events.push(
          createToolEvent(sessionId, agentId, timestamp, {
            tool: ToolCategory.OTHER,
            status: isError ? 'error' : 'completed',
            toolUseId: block.tool_use_id,
          }),
        );

        if (isError) {
          events.push(
            createErrorEvent(sessionId, agentId, timestamp, 'warning'),
          );
        }
      }
    }
  } else {
    const hasText = content.some(
      (b) => b.type === 'text' && 'text' in b && (b as { text: string }).text?.trim(),
    );
    if (hasText) {
      events.push(
        createActivityEvent(sessionId, agentId, timestamp, 'user_prompt'),
      );
    }
  }

  return events;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface ToolUseBlock {
  type: 'tool_use';
  id: string;
  name: string;
  input: Record<string, unknown>;
}

function buildToolStartedEvent(
  sessionId: string,
  agentId: string | null,
  timestamp: string,
  block: ToolUseBlock,
): PixelEvent {
  const toolName = block.name;
  const mapping = TOOL_TO_CATEGORY[toolName] || {
    category: ToolCategory.OTHER,
    detail: toolName,
  };

  return createToolEvent(sessionId, agentId, timestamp, {
    tool: mapping.category,
    detail: mapping.detail,
    status: 'started',
    toolUseId: block.id,
    context: extractSafeContext(toolName, block.input),
  });
}

function extractSafeContext(toolName: string, input: Record<string, unknown> | null): string | null {
  if (!input) return null;

  switch (toolName) {
    case 'Read':
    case 'Write':
    case 'Edit':
      return toBasename(input.file_path as string);

    case 'Bash':
      return (input.description as string) || null;

    case 'Grep':
      return (input.pattern as string) || null;

    case 'Glob':
      return (input.pattern as string) || null;

    case 'Task':
      return (input.subagent_type as string) || null;

    case 'TodoWrite':
      return Array.isArray(input.todos) ? `${input.todos.length} items` : null;

    case 'NotebookEdit':
      return toBasename(input.notebook_path as string);

    default:
      return null;
  }
}

function extractTokens(usage: RawUsage | null): TokenUsage | null {
  if (!usage) return null;

  const tokens: TokenUsage = {
    input: usage.input_tokens || 0,
    output: usage.output_tokens || 0,
  };

  if (usage.cache_read_input_tokens) {
    tokens.cacheRead = usage.cache_read_input_tokens;
  }
  if (usage.cache_creation_input_tokens) {
    tokens.cacheWrite = usage.cache_creation_input_tokens;
  }

  return tokens;
}
```

### `src/adapters/codex.ts`

```ts
import {
  createActivityEvent,
  createToolEvent,
  createAgentEvent,
  createErrorEvent,
  toBasename,
} from '../pixel-events.js';
import { CODEX_TOOL_TO_CATEGORY, ToolCategory } from '../config.js';
import type { PixelEvent, RawJsonlEvent, TokenUsage } from '../types.js';

// ---------------------------------------------------------------------------
// Codex rollout payload types (untyped — accessed via casting)
// ---------------------------------------------------------------------------

interface CodexPayload {
  type?: string;
  [key: string]: unknown;
}

/**
 * Transform a raw Codex CLI JSONL rollout line into PixelEvent(s).
 * Privacy-safe: strips all text content, full paths, commands, and queries.
 */
export function codexAdapter(raw: RawJsonlEvent): PixelEvent[] {
  const sessionId = raw._sessionId;
  const agentId = raw._agentId || null;
  const timestamp = raw.timestamp || new Date().toISOString();
  const payload = (raw as unknown as Record<string, unknown>).payload as CodexPayload | undefined;

  switch (raw.type) {
    case 'response_item':
      return handleResponseItem(payload, sessionId, agentId, timestamp);

    case 'session_meta':
    case 'turn_context':
    case 'compacted':
    case 'event_msg':
      return [];

    default:
      return [];
  }
}

// ---------------------------------------------------------------------------
// response_item dispatch
// ---------------------------------------------------------------------------

function handleResponseItem(
  payload: CodexPayload | undefined,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  if (!payload?.type) return [];

  switch (payload.type) {
    case 'message':
      return handleMessage(payload, sessionId, agentId, timestamp);
    case 'reasoning':
      return [createActivityEvent(sessionId, agentId, timestamp, 'thinking')];
    case 'function_call':
      return handleFunctionCall(payload, sessionId, agentId, timestamp);
    case 'function_call_output':
      return handleFunctionCallOutput(payload, sessionId, agentId, timestamp);
    case 'local_shell_call':
      return handleLocalShellCall(payload, sessionId, agentId, timestamp);
    case 'web_search_call':
      return handleWebSearchCall(payload, sessionId, agentId, timestamp);
    case 'custom_tool_call':
      return handleCustomToolCall(payload, sessionId, agentId, timestamp);
    case 'custom_tool_call_output':
      return handleCustomToolCallOutput(payload, sessionId, agentId, timestamp);
    case 'ghost_snapshot':
    case 'compaction':
    case 'other':
      return [];
    default:
      return [];
  }
}

// ---------------------------------------------------------------------------
// message (user / assistant)
// ---------------------------------------------------------------------------

function handleMessage(
  payload: CodexPayload,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const role = payload.role as string | undefined;

  if (role === 'user') {
    const content = payload.content as unknown[] | undefined;
    if (!content || !Array.isArray(content)) return [];
    const hasText = content.some(
      (b) => typeof b === 'object' && b !== null && (b as Record<string, unknown>).type === 'input_text',
    );
    if (hasText) {
      return [createActivityEvent(sessionId, agentId, timestamp, 'user_prompt')];
    }
    return [];
  }

  if (role === 'assistant') {
    const content = payload.content as unknown[] | undefined;
    if (!content || !Array.isArray(content)) return [];
    const hasOutput = content.some(
      (b) => typeof b === 'object' && b !== null && (b as Record<string, unknown>).type === 'output_text',
    );
    if (hasOutput) {
      return [createActivityEvent(sessionId, agentId, timestamp, 'responding')];
    }
    return [];
  }

  return [];
}

// ---------------------------------------------------------------------------
// function_call → tool.started
// ---------------------------------------------------------------------------

function handleFunctionCall(
  payload: CodexPayload,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const events: PixelEvent[] = [];
  const toolName = (payload.name as string) || 'unknown';
  const callId = (payload.call_id as string) || (payload.id as string) || 'unknown';
  const argsStr = payload.arguments as string | undefined;

  const mapping = CODEX_TOOL_TO_CATEGORY[toolName] || {
    category: ToolCategory.OTHER,
    detail: toolName,
  };

  const context = extractSafeContext(toolName, argsStr);

  events.push(
    createToolEvent(sessionId, agentId, timestamp, {
      tool: mapping.category,
      detail: mapping.detail,
      status: 'started',
      toolUseId: callId,
      context,
    }),
  );

  if (toolName === 'request_user_input') {
    events.push(createActivityEvent(sessionId, agentId, timestamp, 'waiting'));
  }

  if (toolName === 'spawn_agent') {
    events.push(
      createAgentEvent(sessionId, callId, timestamp, 'spawned', 'collab'),
    );
  }

  return events;
}

// ---------------------------------------------------------------------------
// function_call_output → tool.completed / tool.error
// ---------------------------------------------------------------------------

function handleFunctionCallOutput(
  payload: CodexPayload,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const events: PixelEvent[] = [];
  const callId = (payload.call_id as string) || 'unknown';
  const output = (payload.output as string) || '';
  const isError = typeof output === 'string' && output.includes('Error');

  events.push(
    createToolEvent(sessionId, agentId, timestamp, {
      tool: ToolCategory.OTHER,
      status: isError ? 'error' : 'completed',
      toolUseId: callId,
    }),
  );

  if (isError) {
    events.push(createErrorEvent(sessionId, agentId, timestamp, 'warning'));
  }

  return events;
}

// ---------------------------------------------------------------------------
// local_shell_call → terminal events
// ---------------------------------------------------------------------------

function handleLocalShellCall(
  payload: CodexPayload,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const id = (payload.call_id as string) || (payload.id as string) || 'unknown';
  const status = payload.status as string | undefined;

  if (status === 'completed' || status === 'failed') {
    const events: PixelEvent[] = [
      createToolEvent(sessionId, agentId, timestamp, {
        tool: ToolCategory.TERMINAL,
        detail: 'shell',
        status: status === 'failed' ? 'error' : 'completed',
        toolUseId: id,
      }),
    ];
    if (status === 'failed') {
      events.push(createErrorEvent(sessionId, agentId, timestamp, 'warning'));
    }
    return events;
  }

  // Default: started
  return [
    createToolEvent(sessionId, agentId, timestamp, {
      tool: ToolCategory.TERMINAL,
      detail: 'shell',
      status: 'started',
      toolUseId: id,
    }),
  ];
}

// ---------------------------------------------------------------------------
// web_search_call → search events
// ---------------------------------------------------------------------------

function handleWebSearchCall(
  payload: CodexPayload,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const id = (payload.id as string) || 'unknown';
  const status = payload.status as string | undefined;

  return [
    createToolEvent(sessionId, agentId, timestamp, {
      tool: ToolCategory.SEARCH,
      detail: 'web_search',
      status: status === 'completed' ? 'completed' : status === 'failed' ? 'error' : 'started',
      toolUseId: id,
    }),
  ];
}

// ---------------------------------------------------------------------------
// custom_tool_call → other events
// ---------------------------------------------------------------------------

function handleCustomToolCall(
  payload: CodexPayload,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const toolName = (payload.name as string) || 'custom';
  const callId = (payload.call_id as string) || (payload.id as string) || 'unknown';

  return [
    createToolEvent(sessionId, agentId, timestamp, {
      tool: ToolCategory.OTHER,
      detail: toolName,
      status: 'started',
      toolUseId: callId,
    }),
  ];
}

// ---------------------------------------------------------------------------
// custom_tool_call_output → completed/error
// ---------------------------------------------------------------------------

function handleCustomToolCallOutput(
  payload: CodexPayload,
  sessionId: string,
  agentId: string | null,
  timestamp: string,
): PixelEvent[] {
  const callId = (payload.call_id as string) || 'unknown';
  const output = (payload.output as string) || '';
  const isError = typeof output === 'string' && output.includes('Error');

  const events: PixelEvent[] = [
    createToolEvent(sessionId, agentId, timestamp, {
      tool: ToolCategory.OTHER,
      status: isError ? 'error' : 'completed',
      toolUseId: callId,
    }),
  ];

  if (isError) {
    events.push(createErrorEvent(sessionId, agentId, timestamp, 'warning'));
  }

  return events;
}

// ---------------------------------------------------------------------------
// Safe context extraction (privacy-preserving)
// ---------------------------------------------------------------------------

function extractSafeContext(toolName: string, argsStr: string | undefined): string | null {
  if (!argsStr) return null;

  let args: Record<string, unknown>;
  try {
    args = JSON.parse(argsStr) as Record<string, unknown>;
  } catch {
    return null;
  }

  switch (toolName) {
    case 'read_file':
    case 'view_image':
      return toBasename(args.path as string) || toBasename(args.file_path as string);

    case 'grep_files':
      return (args.pattern as string) || null;

    default:
      return null;
  }
}
```

### `src/websocket.ts`

```ts
import { WebSocketServer, WebSocket } from 'ws';
import type { IncomingMessage } from 'http';
import { config } from './config.js';
import { logger } from './logger.js';
import type { AuthManager } from './auth.js';
import type { PixelEvent, BridgeState, ClientMessage } from './types.js';

/**
 * WebSocket server for broadcasting events to authenticated iOS clients.
 */
export class BroadcastServer {
  private wss: WebSocketServer | null;
  private clients: Set<WebSocket>;
  private authenticatedClients: Set<WebSocket>;
  private authManager: AuthManager;
  private onStateRequest: (() => BridgeState) | null;

  constructor(authManager: AuthManager) {
    this.wss = null;
    this.clients = new Set();
    this.authenticatedClients = new Set();
    this.authManager = authManager;
    this.onStateRequest = null;
  }

  start(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.wss = new WebSocketServer({
        port: config.wsPort,
        clientTracking: true,
      });

      this.wss.on('listening', () => {
        logger.verbose('WebSocket', `Server listening on port ${config.wsPort}`);
        resolve();
      });

      this.wss.on('error', (error: Error) => {
        logger.error('WebSocket', `Server error: ${error.message}`);
        reject(error);
      });

      this.wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
        this.handleConnection(ws, req);
      });
    });
  }

  stop(): Promise<void> {
    return new Promise((resolve) => {
      if (this.wss) {
        for (const client of this.clients) {
          client.close();
        }
        this.clients.clear();
        this.authenticatedClients.clear();

        this.wss.close(() => {
          logger.verbose('WebSocket', 'Server stopped');
          resolve();
        });
      } else {
        resolve();
      }
    });
  }

  private handleConnection(ws: WebSocket, req: IncomingMessage): void {
    const clientIp = req.socket.remoteAddress;
    logger.verbose('WebSocket', `Client connected: ${clientIp}`);
    logger.status('\u25CF Device connected');

    this.clients.add(ws);

    ws.on('message', (data: Buffer) => {
      this.handleMessage(ws, data);
    });

    ws.on('close', () => {
      logger.verbose('WebSocket', `Client disconnected: ${clientIp}`);
      logger.status('\u25CF Device disconnected');
      this.clients.delete(ws);
      this.authenticatedClients.delete(ws);
    });

    ws.on('error', (error: Error) => {
      logger.error('WebSocket', `Client error: ${error.message}`);
      this.clients.delete(ws);
      this.authenticatedClients.delete(ws);
    });

    this.sendTo(ws, {
      type: 'welcome',
      payload: {
        message: 'Connected to Pixel Office Bridge',
        version: config.version,
        authRequired: true,
      },
    });
  }

  private handleMessage(ws: WebSocket, data: Buffer): void {
    try {
      const message = JSON.parse(data.toString()) as ClientMessage;

      if (!this.authenticatedClients.has(ws)) {
        if (message.type === 'ping') {
          this.sendTo(ws, { type: 'pong' });
          return;
        }
        if (message.type === 'auth') {
          this.handleAuth(ws, message);
          return;
        }
        this.sendTo(ws, {
          type: 'auth_failed',
          payload: { reason: 'Authentication required' },
        });
        return;
      }

      switch (message.type) {
        case 'ping':
          this.sendTo(ws, { type: 'pong' });
          break;

        case 'subscribe':
          logger.verbose('WebSocket', `Client subscribed to: ${message.sessionId || 'all'}`);
          break;

        case 'get_state':
          if (this.onStateRequest) {
            const state = this.onStateRequest();
            this.sendTo(ws, { type: 'state', payload: state });
          }
          break;

        default:
          logger.verbose('WebSocket', `Unknown message type: ${(message as { type: string }).type}`);
      }
    } catch (err) {
      logger.error('WebSocket', `Failed to parse message: ${(err as Error).message}`);
    }
  }

  private handleAuth(ws: WebSocket, message: ClientMessage & { type: 'auth' }): void {
    if (message.token) {
      if (this.authManager.validateToken(message.token)) {
        this.authenticatedClients.add(ws);
        logger.verbose('WebSocket', 'Client authenticated via token');
        logger.status('\u25CF Device reconnected');
        this.sendTo(ws, {
          type: 'auth_success',
          payload: { token: message.token },
        });
        return;
      }
      logger.verbose('WebSocket', 'Token auth failed \u2014 invalid token');
      this.sendTo(ws, {
        type: 'auth_failed',
        payload: { reason: 'Invalid or revoked token' },
      });
      return;
    }

    if (message.pairingCode) {
      const result = this.authManager.validatePairingCode(
        message.pairingCode,
        message.deviceName,
      );
      if (result) {
        this.authenticatedClients.add(ws);
        logger.verbose('WebSocket', 'Client paired with code, issued token');
        logger.status('\u25CF Device paired successfully');
        this.sendTo(ws, {
          type: 'auth_success',
          payload: { token: result.token },
        });
        return;
      }
      logger.verbose('WebSocket', 'Pairing code auth failed \u2014 wrong code');
      this.sendTo(ws, {
        type: 'auth_failed',
        payload: { reason: 'Invalid pairing code' },
      });
      return;
    }

    this.sendTo(ws, {
      type: 'auth_failed',
      payload: { reason: 'Provide pairingCode or token' },
    });
  }

  private sendTo(ws: WebSocket, message: Record<string, unknown>): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
    }
  }

  broadcast(event: PixelEvent): void {
    if (this.authenticatedClients.size === 0) return;

    const message = JSON.stringify({
      type: 'event',
      payload: event,
    });

    let sentCount = 0;
    for (const client of this.authenticatedClients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(message);
        sentCount++;
      }
    }

    if (sentCount > 0 && event.type !== 'activity') {
      const detail = ('tool' in event ? event.tool : '') || ('action' in event ? event.action : '') || '';
      logger.verbose('WebSocket', `\u2192 ${event.type}${detail ? `: ${detail}` : ''}`);
    }
  }

  sendState(ws: WebSocket, state: BridgeState): void {
    this.sendTo(ws, {
      type: 'state',
      payload: state,
    });
  }

  broadcastState(state: BridgeState): void {
    const message = JSON.stringify({
      type: 'state',
      payload: state,
    });

    for (const client of this.authenticatedClients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(message);
      }
    }
  }

  getClientCount(): number {
    return this.clients.size;
  }

  getAuthenticatedClientCount(): number {
    return this.authenticatedClients.size;
  }

  setStateRequestHandler(callback: () => BridgeState): void {
    this.onStateRequest = callback;
  }
}
```

### `src/auth.ts`

```ts
import { randomBytes, randomInt } from 'crypto';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { config } from './config.js';
import { logger } from './logger.js';
import type { TokenEntry } from './types.js';

/**
 * Manages device pairing and authentication for bridge connections.
 *
 * On startup a 6-digit numeric pairing code is generated and displayed in the
 * terminal. iOS clients exchange the code for a persistent auth token (UUID)
 * which is saved to disk so it survives bridge restarts.
 */
export class AuthManager {
  pairingCode: string;
  tokenFilePath: string;
  tokens: Map<string, TokenEntry>;

  constructor(tokenFilePath?: string) {
    this.pairingCode = AuthManager.generatePairingCode();
    this.tokenFilePath = tokenFilePath ?? config.authTokenFile;
    this.tokens = new Map();
    this.loadTokens();
  }

  static generatePairingCode(): string {
    return String(randomInt(0, 1_000_000)).padStart(6, '0');
  }

  validatePairingCode(code: string, deviceName: string = 'Unknown device'): { token: string } | null {
    if (code !== this.pairingCode) {
      return null;
    }

    const token = randomBytes(16).toString('hex');
    const entry: TokenEntry = {
      token,
      deviceName,
      pairedAt: new Date().toISOString(),
    };

    this.tokens.set(token, entry);
    this.saveTokens();

    return { token };
  }

  validateToken(token: string): boolean {
    return this.tokens.has(token);
  }

  revokeToken(token: string): boolean {
    const existed = this.tokens.delete(token);
    if (existed) {
      this.saveTokens();
    }
    return existed;
  }

  loadTokens(): void {
    try {
      if (existsSync(this.tokenFilePath)) {
        const data = JSON.parse(readFileSync(this.tokenFilePath, 'utf-8')) as unknown;
        if (Array.isArray(data)) {
          for (const entry of data as TokenEntry[]) {
            if (entry.token) {
              this.tokens.set(entry.token, entry);
            }
          }
        }
        logger.verbose('Auth', `Loaded ${this.tokens.size} paired device(s)`);
      }
    } catch (err) {
      logger.error('Auth', `Failed to load tokens: ${(err as Error).message}`);
    }
  }

  saveTokens(): void {
    try {
      const data = Array.from(this.tokens.values());
      writeFileSync(this.tokenFilePath, JSON.stringify(data, null, 2), 'utf-8');
    } catch (err) {
      logger.error('Auth', `Failed to save tokens: ${(err as Error).message}`);
    }
  }
}
```

### `src/session.ts`

```ts
import { TypedEmitter } from './typed-emitter.js';
import { createSessionEvent } from './pixel-events.js';
import { config } from './config.js';
import { logger } from './logger.js';
import type { PixelEvent, SessionInfo, BridgeState } from './types.js';

interface SessionManagerEvents {
  event: [PixelEvent];
}

/**
 * Manages active sessions, agent tracking, and state sync.
 * Stateless event registry — idle detection lives on the iOS client.
 */
export class SessionManager extends TypedEmitter<SessionManagerEvents> {
  sessions: Map<string, SessionInfo>;
  private _reapTimer: ReturnType<typeof setInterval> | null;

  constructor() {
    super();
    this.sessions = new Map();
    this._reapTimer = null;
  }

  startReaper(): void {
    this.stopReaper();
    this._reapTimer = setInterval(() => this._reapStaleSessions(), config.sessionReapIntervalMs);
    this._reapTimer.unref();
  }

  stopReaper(): void {
    if (this._reapTimer) {
      clearInterval(this._reapTimer);
      this._reapTimer = null;
    }
  }

  _reapStaleSessions(): void {
    const now = Date.now();
    for (const [sessionId, info] of this.sessions) {
      const age = now - info.lastEventAt.getTime();
      if (age > config.sessionTtlMs) {
        logger.verbose('Session', `Reaping stale session: ${sessionId.slice(0, 8)}... (idle ${Math.round(age / 1000)}s)`);
        this.removeSession(sessionId);
      }
    }
  }

  registerSession(
    sessionId: string,
    project: string,
    agentId: string | null = null,
    source: string = 'claude-code',
  ): SessionInfo {
    let session = this.sessions.get(sessionId);

    if (!session) {
      session = {
        sessionId,
        project,
        source,
        lastEventAt: new Date(),
        agentIds: new Set(),
        pendingTaskIds: new Set(),
        pendingSpawnQueue: [],
        agentIdMap: new Map(),
        deferredAgentFiles: [],
      };
      this.sessions.set(sessionId, session);

      logger.verbose('Session', `New session registered: ${sessionId.slice(0, 8)}... (${project})`);
      logger.status(`\u2191 streaming session ${sessionId.slice(0, 8)}...`);

      this.emit('event', createSessionEvent(sessionId, 'started', {
        project,
        source,
      }));
    }

    if (agentId && !session.agentIds.has(agentId)) {
      session.agentIds.add(agentId);
    }

    return session;
  }

  recordActivity(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.lastEventAt = new Date();
  }

  removeSession(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    this.sessions.delete(sessionId);
    logger.verbose('Session', `Session removed: ${sessionId.slice(0, 8)}...`);

    this.emit('event', createSessionEvent(sessionId, 'ended', {
      project: session.project,
      source: session.source,
    }));
  }

  // -------------------------------------------------------------------------
  // Agent / Task tracking
  // -------------------------------------------------------------------------

  trackTaskSpawn(sessionId: string, toolUseId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.pendingTaskIds.add(toolUseId);
    session.pendingSpawnQueue.push(toolUseId);
    this._processDeferredAgentFiles(sessionId);
  }

  handleTaskResult(sessionId: string, toolUseId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) return false;
    return session.pendingTaskIds.delete(toolUseId);
  }

  isTaskPending(sessionId: string, toolUseId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) return false;
    return session.pendingTaskIds.has(toolUseId);
  }

  agentCompleted(sessionId: string, agentId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    session.agentIds.delete(agentId);

    for (const [fileId, mappedId] of session.agentIdMap) {
      if (mappedId === agentId) {
        session.agentIdMap.delete(fileId);
        break;
      }
    }

    logger.verbose('Session', `Agent completed: ${agentId} in session ${sessionId.slice(0, 8)}...`);
  }

  // -------------------------------------------------------------------------
  // Agent file correlation (FIFO)
  // -------------------------------------------------------------------------

  correlateAgentFile(sessionId: string, fileAgentId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    if (session.agentIdMap.has(fileAgentId)) return;

    if (session.pendingSpawnQueue.length > 0) {
      const toolUseId = session.pendingSpawnQueue.shift()!;
      session.agentIdMap.set(fileAgentId, toolUseId);
      logger.verbose('Session', `Correlated agent file ${fileAgentId} \u2192 ${toolUseId}`);
    } else {
      if (!session.deferredAgentFiles.includes(fileAgentId)) {
        session.deferredAgentFiles.push(fileAgentId);
      }
    }
  }

  private _processDeferredAgentFiles(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    while (session.deferredAgentFiles.length > 0 && session.pendingSpawnQueue.length > 0) {
      const fileAgentId = session.deferredAgentFiles.shift()!;
      const toolUseId = session.pendingSpawnQueue.shift()!;
      session.agentIdMap.set(fileAgentId, toolUseId);
      logger.verbose('Session', `Deferred correlation: ${fileAgentId} \u2192 ${toolUseId}`);
    }
  }

  resolveAgentId(sessionId: string, fileAgentId: string): string {
    const session = this.sessions.get(sessionId);
    if (!session) return fileAgentId;
    return session.agentIdMap.get(fileAgentId) ?? fileAgentId;
  }

  // -------------------------------------------------------------------------
  // State queries
  // -------------------------------------------------------------------------

  getState(): BridgeState {
    const sessions = [];

    for (const [sessionId, info] of this.sessions) {
      sessions.push({
        sessionId,
        project: info.project,
        source: info.source,
        lastEventAt: info.lastEventAt.toISOString(),
        agentIds: Array.from(info.agentIds),
        pendingTaskIds: Array.from(info.pendingTaskIds),
      });
    }

    return {
      sessions,
      timestamp: new Date().toISOString(),
    };
  }

  getActiveCount(): number {
    return this.sessions.size;
  }

  cleanup(): void {
    this.stopReaper();
    this.sessions.clear();
  }
}
```

### `src/pixel-events.ts`

```ts
import { v4 as uuidv4 } from 'uuid';
import type {
  SessionEvent,
  ActivityEvent,
  ToolEvent,
  AgentEvent,
  ErrorEvent,
  SummaryEvent,
  TokenUsage,
} from './types.js';

export function createSessionEvent(
  sessionId: string,
  action: 'started' | 'ended',
  { project, model, source }: { project?: string; model?: string; source?: string } = {},
): SessionEvent {
  return {
    id: uuidv4(),
    type: 'session',
    sessionId,
    timestamp: new Date().toISOString(),
    action,
    ...(project && { project }),
    ...(model && { model }),
    ...(source && { source }),
  };
}

export function createActivityEvent(
  sessionId: string,
  agentId: string | null,
  timestamp: string,
  action: 'thinking' | 'responding' | 'waiting' | 'user_prompt',
  tokens: TokenUsage | null = null,
): ActivityEvent {
  return {
    id: uuidv4(),
    type: 'activity',
    sessionId,
    ...(agentId && { agentId }),
    timestamp,
    action,
    ...(tokens && { tokens }),
  };
}

export function createToolEvent(
  sessionId: string,
  agentId: string | null,
  timestamp: string,
  { tool, detail, status, toolUseId, context }: {
    tool: string;
    detail?: string;
    status: 'started' | 'completed' | 'error';
    toolUseId: string;
    context?: string | null;
  },
): ToolEvent {
  return {
    id: uuidv4(),
    type: 'tool',
    sessionId,
    ...(agentId && { agentId }),
    timestamp,
    tool,
    ...(detail && { detail }),
    status,
    toolUseId,
    ...(context && { context }),
  };
}

export function createAgentEvent(
  sessionId: string,
  agentId: string | null,
  timestamp: string,
  action: 'spawned' | 'completed' | 'error',
  agentRole: string | null = null,
): AgentEvent {
  return {
    id: uuidv4(),
    type: 'agent',
    sessionId,
    ...(agentId && { agentId }),
    timestamp,
    action,
    ...(agentRole && { agentRole }),
  };
}

export function createErrorEvent(
  sessionId: string,
  agentId: string | null,
  timestamp: string,
  severity: 'warning' | 'error',
): ErrorEvent {
  return {
    id: uuidv4(),
    type: 'error',
    sessionId,
    ...(agentId && { agentId }),
    timestamp,
    severity,
  };
}

export function createSummaryEvent(
  sessionId: string,
  timestamp: string,
): SummaryEvent {
  return {
    id: uuidv4(),
    type: 'summary',
    sessionId,
    timestamp,
  };
}

// ---------------------------------------------------------------------------
// Privacy utilities
// ---------------------------------------------------------------------------

export function toBasename(filePath: unknown): string | null {
  if (!filePath || typeof filePath !== 'string') return null;
  const parts = filePath.split('/');
  return parts[parts.length - 1] || null;
}

export function toProjectName(projectPath: unknown): string | null {
  if (!projectPath || typeof projectPath !== 'string') return null;
  const cleaned = projectPath.replace(/\/+$/, '');
  const parts = cleaned.split('/');
  return parts[parts.length - 1] || null;
}
```

### `src/types.ts`

```ts
// ---------------------------------------------------------------------------
// Shared types for the Pixel Office bridge
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Token usage
// ---------------------------------------------------------------------------

export interface TokenUsage {
  input: number;
  output: number;
  cacheRead?: number;
  cacheWrite?: number;
}

// ---------------------------------------------------------------------------
// PixelEvent discriminated union
// ---------------------------------------------------------------------------

interface BaseEvent {
  id: string;
  sessionId: string;
  timestamp: string;
}

export interface SessionEvent extends BaseEvent {
  type: 'session';
  action: 'started' | 'ended';
  project?: string;
  model?: string;
  source?: string;
}

export interface ActivityEvent extends BaseEvent {
  type: 'activity';
  agentId?: string;
  action: 'thinking' | 'responding' | 'waiting' | 'user_prompt';
  tokens?: TokenUsage;
}

export interface ToolEvent extends BaseEvent {
  type: 'tool';
  agentId?: string;
  tool: string;
  detail?: string;
  status: 'started' | 'completed' | 'error';
  toolUseId: string;
  context?: string;
}

export interface AgentEvent extends BaseEvent {
  type: 'agent';
  agentId?: string;
  action: 'spawned' | 'completed' | 'error';
  agentRole?: string;
}

export interface ErrorEvent extends BaseEvent {
  type: 'error';
  agentId?: string;
  severity: 'warning' | 'error';
}

export interface SummaryEvent extends BaseEvent {
  type: 'summary';
}

export type PixelEvent =
  | SessionEvent
  | ActivityEvent
  | ToolEvent
  | AgentEvent
  | ErrorEvent
  | SummaryEvent;

// ---------------------------------------------------------------------------
// Session info (managed by SessionManager)
// ---------------------------------------------------------------------------

export interface SessionInfo {
  sessionId: string;
  project: string;
  source: string;
  lastEventAt: Date;
  agentIds: Set<string>;
  pendingTaskIds: Set<string>;
  pendingSpawnQueue: string[];
  agentIdMap: Map<string, string>;
  deferredAgentFiles: string[];
}

// ---------------------------------------------------------------------------
// Bridge state (returned by getState)
// ---------------------------------------------------------------------------

export interface SessionStateEntry {
  sessionId: string;
  project: string;
  source: string;
  lastEventAt: string;
  agentIds: string[];
  pendingTaskIds: string[];
}

export interface BridgeState {
  sessions: SessionStateEntry[];
  timestamp: string;
}

// ---------------------------------------------------------------------------
// Token entry (persisted by AuthManager)
// ---------------------------------------------------------------------------

export interface TokenEntry {
  token: string;
  deviceName: string;
  pairedAt: string;
}

// ---------------------------------------------------------------------------
// Tool category mapping
// ---------------------------------------------------------------------------

export interface ToolMapping {
  category: string;
  detail: string;
}

// ---------------------------------------------------------------------------
// Raw JSONL types (from Claude Code session files)
// ---------------------------------------------------------------------------

export interface RawJsonlEvent {
  type: string;
  timestamp?: string;
  message?: RawMessage;
  userType?: string;
  _sessionId: string;
  _agentId: string | null;
}

export interface RawMessage {
  content?: RawContentBlock[] | string;
  usage?: RawUsage;
}

export interface RawUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

export type RawContentBlock =
  | { type: 'thinking'; thinking: string }
  | { type: 'text'; text: string }
  | { type: 'tool_use'; id: string; name: string; input: Record<string, unknown> }
  | { type: 'tool_result'; tool_use_id: string; content?: string; is_error?: boolean };

// ---------------------------------------------------------------------------
// Watcher events
// ---------------------------------------------------------------------------

export interface WatcherSessionEvent {
  sessionId: string;
  agentId: string | null;
  project: string;
  filePath: string;
  action: 'discovered';
  source?: string;
}

export interface WatcherLineEvent {
  line: string;
  sessionId: string;
  agentId: string | null;
  filePath: string;
  source?: string;
}

export interface ParsedFilePath {
  sessionId: string;
  agentId: string | null;
  project: string;
  source: string;
}

// ---------------------------------------------------------------------------
// WebSocket client messages
// ---------------------------------------------------------------------------

export type ClientMessage =
  | { type: 'ping' }
  | { type: 'auth'; token?: string; pairingCode?: string; deviceName?: string }
  | { type: 'subscribe'; sessionId?: string }
  | { type: 'get_state' };

// ---------------------------------------------------------------------------
// WebSocket server messages
// ---------------------------------------------------------------------------

export type ServerMessage =
  | { type: 'welcome'; payload: { message: string; version: string; authRequired: boolean } }
  | { type: 'pong' }
  | { type: 'auth_success'; payload: { token: string } }
  | { type: 'auth_failed'; payload: { reason: string } }
  | { type: 'event'; payload: PixelEvent }
  | { type: 'state'; payload: BridgeState };
```

### `bin/cli.ts`

```ts
#!/usr/bin/env node

import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

function findPackageJson(startDir: string): string {
  let dir = startDir;
  while (true) {
    const candidate = join(dir, 'package.json');
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) throw new Error('Could not find package.json');
    dir = parent;
  }
}

const pkg = JSON.parse(readFileSync(findPackageJson(__dirname), 'utf-8')) as {
  name: string;
  version: string;
};

const args = process.argv.slice(2);

// ---------------------------------------------------------------------------
// --help
// ---------------------------------------------------------------------------

if (args.includes('--help') || args.includes('-h')) {
  console.log(`
  ${pkg.name} v${pkg.version}

  Watches AI agent session files and broadcasts events
  via WebSocket for the Pixel Office iOS app.

  Supported agents: Claude Code, Codex CLI

  Usage
    $ pixelhq [options]

  Options
    --port <number>       WebSocket server port (default: 8765)
    --claude-dir <path>   Path to Claude config directory
    --codex-dir <path>    Path to Codex config directory
    --yes, -y             Skip interactive prompts (non-interactive mode)
    --verbose             Show detailed debug logging
    --help, -h            Show this help message
    --version, -v         Show version number

  Environment variables
    PIXEL_OFFICE_PORT     WebSocket server port
    CLAUDE_CONFIG_DIR     Path to Claude config directory
    CODEX_HOME            Path to Codex config directory

  Examples
    $ npx pixelhq
    $ npx pixelhq --yes
    $ npx pixelhq --port 9999
    $ npx pixelhq --verbose
    $ pixelhq --claude-dir ~/.config/claude
`);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// --version
// ---------------------------------------------------------------------------

if (args.includes('--version') || args.includes('-v')) {
  console.log(pkg.version);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const isNonInteractive = args.includes('--yes') || args.includes('-y');
const isVerbose = args.includes('--verbose');

async function main(): Promise<void> {
  const { logger } = await import('../src/logger.js');
  logger.setVerbose(isVerbose);

  const { PixelOfficeBridge } = await import('../src/index.js');

  if (isNonInteractive) {
    await startBridge(PixelOfficeBridge, logger);
    return;
  }

  await showInteractiveMenu(PixelOfficeBridge, logger);
}

async function showInteractiveMenu(
  PixelOfficeBridge: typeof import('../src/index.js').PixelOfficeBridge,
  logger: typeof import('../src/logger.js').logger,
): Promise<void> {
  const { select, input } = await import('@inquirer/prompts');

  console.log('');
  console.log(`  ${pkg.name} v${pkg.version}`);
  console.log('');
  console.log('  Pixel Office Bridge watches your Claude Code sessions');
  console.log('  and streams activity to the Pixel Office iOS app as');
  console.log('  real-time pixel art animations.');
  console.log('');
  console.log('  How it works:');
  console.log('  \u2022 Watches ~/.claude/projects/ for session activity');
  console.log('  \u2022 Broadcasts events on your local network via WebSocket');
  console.log('  \u2022 iOS app discovers this bridge automatically via Bonjour');
  console.log('');
  console.log('  Security:');
  console.log('  \u2022 Only devices you pair with a one-time code can connect');
  console.log('  \u2022 No code content, file paths, or commands are transmitted');
  console.log('  \u2022 Only activity types are sent (e.g. "thinking", "reading file")');
  console.log('  \u2022 All communication stays on your local network');
  console.log('  \u2022 Open source \u2014 github.com/waynedev9598/PixelHQ-bridge');
  console.log('  \u2022 Every release is provenance-verified on npm');
  console.log('');

  let customPort: number | undefined;
  let customClaudeDir: string | undefined;

  while (true) {
    const choice = await select({
      message: 'What would you like to do?',
      choices: [
        { name: 'Start bridge', value: 'start' },
        { name: 'Configure options', value: 'configure' },
        { name: 'Exit', value: 'exit' },
      ],
    });

    if (choice === 'exit') {
      process.exit(0);
    }

    if (choice === 'configure') {
      const portInput = await input({
        message: 'WebSocket port:',
        default: String(customPort ?? 8765),
      });
      const parsedPort = parseInt(portInput, 10);
      if (!isNaN(parsedPort) && parsedPort > 0 && parsedPort < 65536) {
        customPort = parsedPort;
      }

      const claudeDirInput = await input({
        message: 'Claude config directory:',
        default: customClaudeDir ?? '~/.claude',
      });
      if (claudeDirInput && claudeDirInput !== '~/.claude') {
        customClaudeDir = claudeDirInput;
      }

      // Apply custom options by modifying argv before config re-reads
      if (customPort) {
        const portIdx = process.argv.indexOf('--port');
        if (portIdx !== -1) {
          process.argv[portIdx + 1] = String(customPort);
        } else {
          process.argv.push('--port', String(customPort));
        }
      }
      if (customClaudeDir) {
        const dirIdx = process.argv.indexOf('--claude-dir');
        if (dirIdx !== -1) {
          process.argv[dirIdx + 1] = customClaudeDir;
        } else {
          process.argv.push('--claude-dir', customClaudeDir);
        }
      }

      console.log('');
      console.log(`  Options updated. Port: ${customPort ?? 8765}, Claude dir: ${customClaudeDir ?? '~/.claude'}`);
      console.log('');
      continue;
    }

    if (choice === 'start') {
      await startBridge(PixelOfficeBridge, logger);
      return;
    }
  }
}

async function startBridge(
  PixelOfficeBridge: typeof import('../src/index.js').PixelOfficeBridge,
  logger: typeof import('../src/logger.js').logger,
): Promise<void> {
  const bridge = new PixelOfficeBridge();

  // Pre-flight checks
  try {
    const info = bridge.preflight();
    logger.info('\u2713 Claude Code detected at ' + info.claudeDir);
    if (info.codexDir) {
      logger.info('\u2713 Codex CLI detected at ' + info.codexDir);
    }
  } catch (err) {
    console.log('');
    console.log('  \u2717 No supported agent found');
    console.log('');
    console.log('  Make sure Claude Code or Codex CLI is installed and has been used at least once.');
    console.log('');
    console.log('  Specify a custom path:');
    console.log('    npx pixelhq --claude-dir /path/to/claude');
    console.log('    npx pixelhq --codex-dir /path/to/codex');
    console.log('');
    process.exit(1);
  }

  // Start the bridge
  try {
    await bridge.start();
  } catch (err) {
    const message = (err as Error).message;
    if (message.includes('EADDRINUSE') || message.includes('address already in use')) {
      const { config } = await import('../src/config.js');
      console.log('');
      console.log(`  \u2717 Port ${config.wsPort} is already in use`);
      console.log('');
      console.log(`  Try a different port:  npx pixelhq --port 9999`);
      console.log('');
    } else {
      console.log('');
      console.log(`  \u2717 Failed to start: ${message}`);
      console.log('');
    }
    process.exit(1);
  }

  // Show pairing code
  const code = bridge.pairingCode;
  logger.blank();
  console.log('  \u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557');
  console.log(`  \u2551         Pairing Code: ${code}          \u2551`);
  console.log('  \u2551                                       \u2551');
  console.log('  \u2551  Enter this code in the iOS app to    \u2551');
  console.log('  \u2551  connect. Code regenerates on restart. \u2551');
  console.log('  \u255A\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255D');
  logger.blank();
  logger.info('Waiting for agent activity...');
  logger.info('Press Ctrl+C to stop');
  logger.blank();
}

main().catch((err) => {
  console.error(`  \u2717 ${(err as Error).message}`);
  process.exit(1);
});
```

### `src/typed-emitter.ts`

```ts
import { EventEmitter } from 'events';

/**
 * Generic typed EventEmitter helper.
 * Provides type-safe emit/on/off/once for a known event map.
 */
export class TypedEmitter<Events extends { [K in keyof Events]: unknown[] }> {
  private emitter = new EventEmitter();

  emit<K extends keyof Events & string>(event: K, ...args: Events[K]): boolean {
    return this.emitter.emit(event, ...args);
  }

  on<K extends keyof Events & string>(event: K, listener: (...args: Events[K]) => void): this {
    this.emitter.on(event, listener as (...args: unknown[]) => void);
    return this;
  }

  off<K extends keyof Events & string>(event: K, listener: (...args: Events[K]) => void): this {
    this.emitter.off(event, listener as (...args: unknown[]) => void);
    return this;
  }

  once<K extends keyof Events & string>(event: K, listener: (...args: Events[K]) => void): this {
    this.emitter.once(event, listener as (...args: unknown[]) => void);
    return this;
  }

  removeAllListeners<K extends keyof Events & string>(event?: K): this {
    this.emitter.removeAllListeners(event);
    return this;
  }
}
```

### `src/logger.ts`

```ts
/**
 * Centralized logger with normal and verbose modes.
 *
 * Normal mode (default): clean, minimal output for end users.
 * Verbose mode (--verbose): shows all [Module] prefixed debug logs.
 */

let _verbose = false;

export const logger = {
  /** Always shown — important milestones */
  info(message: string): void {
    console.log(`  ${message}`);
  },

  /** Only in verbose mode — debug details */
  verbose(tag: string, message: string): void {
    if (_verbose) {
      console.log(`[${tag}] ${message}`);
    }
  },

  /** Always shown — errors */
  error(tag: string, message: string): void {
    console.error(`[${tag}] ${message}`);
  },

  /** User-facing status updates (e.g., "● Device connected") */
  status(message: string): void {
    console.log(`  ${message}`);
  },

  /** Blank line */
  blank(): void {
    console.log('');
  },

  /** Set verbose mode */
  setVerbose(enabled: boolean): void {
    _verbose = enabled;
  },

  /** Check if verbose mode is enabled */
  isVerbose(): boolean {
    return _verbose;
  },
};
```

### `src/bonjour.ts`

```ts
import Bonjour from 'bonjour-service';
import { networkInterfaces } from 'os';
import { config } from './config.js';
import { logger } from './logger.js';

function getLocalIPv4(): string {
  const nets = networkInterfaces();

  const preferredInterfaces = ['en0', 'en1', 'eth0', 'wlan0'];

  for (const ifname of preferredInterfaces) {
    const net = nets[ifname];
    if (net) {
      for (const addr of net) {
        if (addr.family === 'IPv4' && !addr.internal) {
          return addr.address;
        }
      }
    }
  }

  for (const name of Object.keys(nets)) {
    for (const addr of nets[name]!) {
      if (addr.family === 'IPv4' && !addr.internal) {
        return addr.address;
      }
    }
  }

  return '0.0.0.0';
}

/**
 * Advertises the bridge server via Bonjour/mDNS.
 * Allows iOS app to discover the bridge automatically.
 */
export class BonjourAdvertiser {
  private bonjour: InstanceType<typeof Bonjour.default> | null;
  private service: ReturnType<InstanceType<typeof Bonjour.default>['publish']> | null;
  private _localIP: string;

  constructor() {
    this.bonjour = null;
    this.service = null;
    this._localIP = '0.0.0.0';
  }

  get localIP(): string {
    return this._localIP;
  }

  start(): void {
    this.bonjour = new Bonjour.default();

    this._localIP = getLocalIPv4();

    this.service = this.bonjour.publish({
      name: config.bonjourName,
      type: config.bonjourType,
      port: config.wsPort,
      txt: {
        version: '1.0.0',
        protocol: 'websocket',
        ip: this._localIP,
        auth: 'required',
      },
    });

    this.service.on('up', () => {
      logger.verbose('Bonjour', `Service advertised: ${config.bonjourName}`);
      logger.verbose('Bonjour', `Type: _${config.bonjourType}._tcp`);
      logger.verbose('Bonjour', `Port: ${config.wsPort}`);
      logger.verbose('Bonjour', `IP: ${this._localIP}`);
    });

    this.service.on('error', (error: unknown) => {
      logger.error('Bonjour', `Service error: ${(error as Error).message}`);
    });
  }

  stop(): void {
    if (this.service) {
      this.service.stop?.();
      this.service = null;
    }

    if (this.bonjour) {
      this.bonjour.destroy();
      this.bonjour = null;
    }

    logger.verbose('Bonjour', 'Service unpublished');
  }
}
```
