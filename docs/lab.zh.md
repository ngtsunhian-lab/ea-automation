# Claude Code Skill 实战课堂实验

**基于 [ea-automation](https://github.com/ngtsunhian-lab/ea-automation) skill**

> 一个 60 分钟的互动小实验:从下载一个真实 skill,到让它干活,再到动手改造它。

---

## 实验目标

- 理解 Claude Code skill 的结构:一个文件夹 + `SKILL.md` + 可选脚本
- 学会安装、触发、验证一个 skill
- 体验"自然语言 → 工具调用"的完整链路
- 掌握 skill 的优化原则,并动手改进一个真实 skill

## 实验环境

| 项目 | 要求 |
|---|---|
| 操作系统 | Windows(EA COM 接口仅限 Windows) |
| Claude Code | 已安装并可用 |
| Enterprise Architect | 已安装,且打开一个项目(试用版即可) |
| 网络 | 能访问 GitHub |

**时长安排:** Part 1 ≈ 15 分钟 · Part 2 ≈ 25 分钟 · Part 3 ≈ 20 分钟

---

## Part 1 — 下载并加载 Skill(15 min)

### 1.1 认识 skill 的结构

一个 skill 就是一个文件夹,放在 `~/.claude/skills/` 下,最少只需要一个 `SKILL.md`:

```
~/.claude/skills/ea-automation/
├── SKILL.md          ← 说明书:名字、触发条件、用法(给 Claude 看的)
└── scripts/
    └── ea.ps1        ← 干活的脚本(给操作系统执行的)
```

`SKILL.md` 开头的 frontmatter 是关键——`description` 决定了 Claude **什么时候**会想起这个 skill:

```markdown
---
name: ea-automation
description: Read and write a running Enterprise Architect model ...
  Use when the user wants to programmatically edit an EA model
  (e.g. "add a component to the EA diagram", "connect these elements in EA") ...
---
```

注意 `description` 里括号中的触发短语:它们在教 Claude,"用户说了这样的话,就该用我"。

### 1.2 动手:安装

打开 PowerShell:

```powershell
# 1. 克隆仓库
git clone https://github.com/ngtsunhian-lab/ea-automation.git "$env:TEMP\ea-automation"

# 2. 复制到 Claude Code 的 skills 目录
Copy-Item -Recurse "$env:TEMP\ea-automation" "$env:USERPROFILE\.claude\skills\ea-automation"

# 3. 确认三个文件都在
dir "$env:USERPROFILE\.claude\skills\ea-automation"
```

### 1.3 检查点 ✅

新开一个 Claude Code 会话(或重启当前会话),问:

> 你现在有哪些 skill?ea-automation 是干什么的?

Claude 应该能说出它的用途。**注意:** skill 列表在会话启动时加载,装完必须重开会话才生效。

**思考题:** `description` 里为什么要写触发短语(如 "add a component to the EA diagram")?如果不写会怎样?

---

## Part 2 — 让 Skill 跑起来(25 min)

### 2.1 准备舞台

1. 打开 Enterprise Architect,打开任意项目(新建一个也行)
2. 打开或新建一张图(组件图 / 类图均可)
3. 保持 EA 处于运行状态——skill 操作的是**正在运行的** EA 实例

### 2.2 用自然语言驱动

在 Claude Code 里直接说(不要自己敲命令!):

> 帮我看看 EA 里现在打开的图,然后在图上加一个叫 DemoService 的组件,
> 再把它连到图里已有的任意一个元素上。

然后观察 Claude 做了什么。它应该:

1. 调用 skill 里的 `ea.ps1 -Command status` 拿到项目结构和真实 ID
2. `add-element` 创建元素 → 拿到新元素 ID
3. `place` 把元素放到图上
4. `connect` 创建连接线
5. EA 里的图**自动刷新**,新组件出现了

### 2.3 揭秘:背后发生了什么

Claude 做的每一步,其实都是在执行 skill 自带的 CLI:

```powershell
$ea = "$env:USERPROFILE\.claude\skills\ea-automation\scripts\ea.ps1"

& $ea -Command status                          # 1. 摸清环境:实例、包、图、元素 ID
& $ea -Command add-element -Name DemoService -PackageID 2
& $ea -Command place -ElementID 999 -DiagramID 1 -X 250 -Y 300 -Width 117 -Height 70
& $ea -Command connect -ClientID 6 -SupplierID 999 -ConnectorType Dependency -DiagramID 1
```

所有命令输出 JSON;失败时返回 `{"error": "..."}` 且退出码为 1。

**这就是 skill 的本质:把一套复杂操作封装成 Claude 能可靠执行的接口。**

### 2.4 动手:手动跑一遍

自己在 PowerShell 里依次执行上面的 4 条命令(用 `status` 输出里的真实 ID 替换示例 ID)。体会一下:Claude 平时就是在替你做这件事——读 JSON、提取 ID、填进下一条命令。

### 2.5 检查点 ✅

| 验证项 | 方法 |
|---|---|
| 元素已创建 | `& $ea -Command find -Name DemoService` 返回 ID |
| 已上图 | EA 里肉眼可见 |
| 已连接 | `& $ea -Command element -ElementID <id>` 列出 connectors |

**常见问题排查:**

| 症状 | 原因 | 解法 |
|---|---|---|
| `No running EA instance found` | EA 没开或没打开项目 | 打开 EA 和项目 |
| ID 找不到 | 多个 EA 实例,ID 属于另一个 | 先跑 `status`,用真实 ID |
| 图没刷新 | EA 窗口未激活 | `& $ea -Command reload -DiagramID <id>` |

---

## Part 3 — 优化这个 Skill(20 min)

"优化 skill" 有三个层次,从最重要到最不重要:

| 层次 | 优化什么 | 为什么 |
|---|---|---|
| ① 触发质量 | `description` 写得准不准 | 写错了 Claude 根本不会用它 |
| ② 安全性 | 危险操作有没有护栏 | skill 是有真实副作用的 |
| ③ 能力 | 加命令、改输出 | 按需添加,不要过度设计 |

### 3.1 练习 A:优化触发描述

打开 `SKILL.md`,只改 frontmatter 的 `description`,让它能被更多说法触发。比如学生可能会说:

- "在架构图里加个服务"
- "把 EA 里的组件连起来"
- "帮我画一张组件图"

改完重开会话,用新的说法测试是否触发。**记录:** 哪些说法触发了,哪些没有?

### 3.2 练习 B:加一条安全护栏

现在 `connect` 命令允许连接**任意**两个元素——包括把一个注记(Text)连到另一个注记。给它加一个护栏:如果 client 或 supplier 的类型是 `Text` / `Note`,返回错误拒绝连接。

提示(在 `connect` 分支里,拿到 `$client` 之后加判断):

```powershell
foreach ($side in @($client, $rep.GetElementByID($SupplierID))) {
  if ($side.Type -in @("Text", "Note")) {
    Fail ("Refusing to connect a " + $side.Type + " element (safety guardrail)")
  }
}
```

改完测试:① 正常连接仍成功;② 连接 Text 元素被拒绝并返回 JSON 错误。

### 3.3 练习 C(选做):加一个新命令

参考现有命令的模式,给 `ea.ps1` 加一个 `count` 命令:统计项目里每种元素类型有多少个。骨架:

```powershell
elseif ($Command -eq "count") {
  # 遍历所有包(参考 find 命令的 stack 写法),按 $e.Type 分组计数
  # 输出 @{ counts = @{ Component = 12; Class = 5; Text = 4 } }
}
```

别忘了同步改两处:"Unknown command" 的错误提示、`SKILL.md` 的命令表。

### 3.4 优化三原则

1. **最小改动** — 只改与目标直接相关的行,不顺手"美化"别的代码
2. **改完即测** — 每次改动后立刻跑一遍受影响的命令
3. **YAGNI** — 没人要的功能不要加;这个 skill 至今没有 delete 命令,是**故意的**(破坏性操作留在 EA 界面里手动做)

---

## 附录 A — ea-automation 命令速查

| 命令 | 参数 | 作用 |
|---|---|---|
| `status` | — | 所有运行中的 EA 实例:项目名、包树、元素/图 ID |
| `diagram` | `-DiagramID N` | 图上的元素(含坐标)和连接线 |
| `find` | `-Name substr` | 按名称子串搜索元素 |
| `element` | `-ElementID N` | 单个元素详情:构造型、属性、操作、连接线 |
| `add-element` | `-Name X -PackageID N [-Type Component]` | 创建元素(幂等) |
| `place` | `-ElementID N -DiagramID N -X -Y -Width -Height` | 上图 / 移动位置 |
| `connect` | `-ClientID N -SupplierID N [-ConnectorType] [-DiagramID]` | 创建连接线(箭头:client → supplier) |
| `reload` | `-DiagramID N` | 刷新 EA 中的图 |

## 附录 B — 本实验的知识地图

- **Skill 机制**:文件夹 + SKILL.md(frontmatter 的 `description` = 触发器)→ 会话启动时加载
- **封装思想**:把"复杂但可靠"的操作(CLI/脚本)包起来,让"灵活但不稳定"的一方(Claude)负责理解和调度
- **安全设计**:读操作放开,写操作加约束,删操作干脆不做
- **迭代方法**:最小改动 → 立即验证 → 按需扩展
