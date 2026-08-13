# LnnLore（PocketInn 特别版）

> 基于开源项目 [PocketInn](https://github.com/adoretes/PocketInn) 深度改造的 AI 聊天应用，兼容 SillyTavern 的角色卡、世界书、预设等数据格式。

**LnnLore** 是一个 Flutter 开发的 AI 聊天应用，偏向角色扮演与沉浸式对话体验。保留上游全部功能，并加入**角色状态面板系统（Tracker）**、**强制思维链**、**群聊**、**应用内自更新**等增强。

> 🤖 由 **DeepSeek AI** 辅助开发
> 📦 当前版本：`1.4.0-special.95`（special 系列持续迭代，不并入上游正式版）

## ✨ 功能亮点

### 🎴 角色状态系统（Tracker）

- **状态面板随卡**：角色卡通过 `data.extensions.tracker` 声明状态字段与 HTML 面板模板，App 运行时解析、校验、持久化、渲染
- **三种状态更新模式**（通用设置）：快速（单次 API）/ 后台精确（正文先显示、裁判后台补算）/ 严格（等待裁判）
- **单一写入者架构**：每轮只有一个状态决策者，杜绝重复叠加与双写入冲突
- **动态实体（群像卡，v89）**：支持"模板 + 预设角色 + 自动建档"——剧情中出现的新角色（含原创角色）自动建档、状态栏按角色分区，角色之间状态互不串扰
- **剧情化备注（v89）**：面板备注为剧情摘录（非裁判分析语言），自动过滤"本字段/本轮+增加"等元语言
- **语义驱动（v85）**：状态随剧情语义推进，不依赖关键词词表

### 🧠 强制思维链

回复前必须输出 `<think>...</think>` 思维链（模板可自定义），流式校验不合规自动重试，兼容 DeepSeek R1/V3 的 reasoning 字段。

### 👥 群聊

多角色群聊轮流发言，人设互不串台。

### ⚡ 其他增强

应用内自更新（国内镜像回退链）、上下文预算检查、API key 生命周期管理、世界书引用保护、备份恢复校验、发送可靠性修复、历史记忆联动、SSE 流式容错、未保存编辑保护、快捷指令系统、文本样式预设等。

## 📇 角色卡格式

兼容 **Chara Card V2**（JSON / PNG 卡，与 SillyTavern 互通）。

> **完整 tracker 协议规范（v76/v77 + v89 动态实体）与公共验证器见 [character-card-creator](https://github.com/xyy1124/character-card-creator) 仓库**——生成/校验角色卡 tracker 时调用 `scripts/verify_tracker_v76_v77.js`（入口按 schemaVersion 自动分流 v1/v2）。

简要结构：

```json
{
  "data": {
    "extensions": {
      "tracker": {
        "schemaVersion": "1.0",
        "stateSchema": {
          "energy": { "type": "number", "label": "体力", "min": 0, "max": 100 }
        },
        "initialState": { "energy": 80 },
        "actions": [
          { "id": "view", "label": "查看状态", "prompt": "查看当前状态" }
        ],
        "uiHints": { "order": ["energy"] },
        "template": "<details><summary>状态面板</summary><div>{{getvar::energy}}</div></details>"
      }
    }
  }
}
```

群像卡（schemaVersion 2）使用 `entityTemplates` / `initialEntities` / `entityDiscovery` / `migrations` 声明动态角色实体，详见 character-card-creator 仓库。

## ⬇️ 下载

最新版本从 [Releases](https://github.com/xyy1124/LnnLore/releases) 获取（`pocketinn-1.4.0-special.<版本>.apk`）。

> 建议始终安装**最新版**（置顶 Release）——历史版本仅作追溯，修复的问题不会出现在新版中。

## 🚀 开发环境

- Flutter / Dart 3
- 构建：`flutter run`（调试） / `flutter build apk --release`（Android 安装包）

## 🔗 相关项目

- **[character-card-creator](https://github.com/xyy1124/character-card-creator)**：引导式角色卡制作技能（ZCode 技能）——输出 Chara Card V2 兼容角色卡，含 tracker 状态协议（v76/v77 + v89 动态实体）的完整规范与公共验证器

## 🙏 致谢

- **上游项目 [PocketInn](https://github.com/adoretes/PocketInn)**：基于其源码改造，感谢上游作者的开源贡献
- **[SillyTavern](https://github.com/SillyTavern/SillyTavern)**：数据格式与生态兼容参考
- **DeepSeek AI**：本项目大量代码由 DeepSeek 辅助编写与调试

## 📄 开源协议

遵循上游的 **GNU Affero General Public License v3.0 (AGPL-3.0)**，详情见 [LICENSE](LICENSE)。

## 📝 说明

- 开发中项目，部分功能与界面可能继续调整
- iOS 版本因开发环境限制暂未适配
