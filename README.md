# LnnLore（PocketInn 特别版）

> **基于开源项目 [PocketInn](https://github.com/adoretes/PocketInn)（上游）深度改造的 AI 聊天应用**，兼容 SillyTavern 的角色卡、世界书、预设等数据格式。

**LnnLore** 是一个基于 Flutter 开发的 AI 聊天应用，偏向角色扮演与沉浸式对话体验。它保留了上游 PocketInn 的全部功能，并在此基础上加入了**角色状态面板系统**、**强制思维链**、**群聊**等大量增强功能。

> 🤖 本项目由 **DeepSeek AI** 辅助开发。

## 📇 角色卡格式

本应用兼容 **Chara Card V2** 格式的角色卡（JSON / PNG 卡，与 SillyTavern 互通）。状态系统由角色卡通过 `data.extensions.tracker` 声明，App 运行时负责解析、校验、持久化与渲染。

### 1. 基础字段（必需）

```json
{
  "data": {
    "name": "角色名",
    "description": "角色描述",
    "personality": "性格",
    "scenario": "场景",
    "mes_example": "对话示例",
    "post_history_instructions": "角色输出规则（含状态面板模板）"
  }
}
```

### 2. 状态声明（tracker 协议）

```json
{
  "data": {
    "extensions": {
      "tracker": {
        "schemaVersion": "1.0",
        "stateSchema": {
          "energy": { "type": "number", "label": "体力", "min": 0, "max": 100 },
          "mood": { "type": "string", "label": "心情" }
        },
        "initialState": { "energy": 80, "mood": "平静" },
        "actions": [
          { "id": "view", "label": "查看状态", "prompt": "查看当前状态" },
          { "id": "play", "label": "玩法动作", "prompt": "触发玩法" }
        ],
        "uiHints": { "order": ["energy", "mood"] },
        "template": "<div>自定义面板模板</div>",
        "defaultExpanded": false
      }
    }
  }
}
```

| 字段 | 说明 |
|---|---|
| `stateSchema` | 状态字段定义：`type`（number/string）、`label`（显示名）、`min`/`max`（数值范围，自动 clamp） |
| `initialState` | 初始值（**只存短值**，长描述放在 presentation 里） |
| `actions` | 决策动作（≥2 个：查看状态/重置状态 + 玩法动作） |
| `uiHints.order` | 状态栏显示顺序 |
| `template` | 自定义面板 HTML 模板（也兼容 `uiHints.template`） |
| `defaultExpanded` | 状态面板初始是否展开（默认收起） |

### 3. 阶段描述（presentation，推荐）

每个字段可声明阶段描述——App 按当前值**确定性渲染**阶段标题/颜色/长描述，数值跨段时文字自动变化，不依赖模型临时编造：

```json
"energy": {
  "type": "number", "label": "体力", "min": 0, "max": 100,
  "presentation": {
    "ranges": [
      { "gte": 0,  "lt": 20, "title": "疲惫", "color": "#78909C", "text": "体力所剩无几，行动迟缓。" },
      { "gte": 20, "lt": 40, "title": "乏力", "color": "#66BB6A", "text": "开始感到疲倦，需要休息。" },
      { "gte": 40, "lt": 60, "title": "平稳", "color": "#FFA726", "text": "状态正常，可以继续行动。" },
      { "gte": 60, "lt": 80, "title": "充沛", "color": "#EF5350", "text": "精神饱满，活力十足。" },
      { "gte": 80,             "title": "满盈", "color": "#AB47BC", "text": "状态达到巅峰，精力旺盛。" }
    ]
  }
}
```

- **number 字段**：`presentation.ranges`（≥3 段）——`gte ≤ 值 < lt` 匹配，最后一段可省略 `lt`
- **string 字段**：`presentation.states`（≥2 枚举）——值精确匹配 `{title, color, text}`

### 4. 状态面板模板与变量

`post_history_instructions` 中用 `<!--panel-->` 标记声明 HTML 面板模板（App 渲染，样式随卡）：

```html
<!--panel-->
<details><summary>🖤 卡名·状态面板</summary>
<div style="padding:10px;background-color:#171020;border:2px solid #8e44ad;border-radius:10px;color:#e8e8e8;line-height:1.8">
  <span style="color:#8e44ad">体力</span>：<b>【{{getvar::energy}}/100】</b> <span style="color:{{getcolor::energy}};font-weight:bold">· {{gettitle::energy}}</span><br>
  <span style="color:#a8a098;font-size:11px">{{gettext::energy}}</span><br>
  <span style="color:#8e44ad">心情</span>：<b>【{{getvar::mood}}】</b>
</div>
</details>
<!--/panel-->
```

| 模板变量 | 含义 |
|---|---|
| `{{getvar::key}}` | 当前原始值（如 `45`） |
| `{{gettitle::key}}` | 当前阶段标题（如 `明显改造`） |
| `{{gettext::key}}` | 当前阶段长描述 |
| `{{getcolor::key}}` | 当前阶段颜色 |
| `{{getpercent::key}}` | number 字段百分比（min/max 归一） |

支持的 HTML：`div/span/b/strong/br/p/table/tr/td/th/details/summary/img`；CSS：`color/background-color/border/border-radius/padding/margin/font-size/font-weight/text-align/width/height`。**不执行 JavaScript、不加载外部样式**（安全清洗：script/iframe/object/embed/事件属性/固定定位一律剥离）。

### 5. 状态更新方式

| 方式 | 示例 | 说明 |
|---|---|---|
| 旁白（本地确定性） | `（体力+10）`、`（体力=35）`、`体力提高40%` | 发送时立即落地，自动 clamp，不依赖模型 |
| 模型 JSON patch | `{"patch":{"set":{},"add":{"energy":10}}}` | 模型每轮输出（支持 `{reply, patch}` 结构，中文 label 自动映射回 key） |
| `<STATE>` 兜底 | `<STATE> energy=+10 </STATE>` | 兼容协议 |
| setvar 宏 | `{{setvar::energy::5}}` | 统一经过 tracker 校验（受保护字段过滤 + clamp） |

## ✨ 特别版功能

### 🎴 角色状态系统（Tracker）

- 状态声明、HTML 面板、确定性旁白修改、模型状态协议、消息级状态快照、阶段描述（presentation）、进度条、面板折叠、分支状态回滚

### 🧠 强制思维链

- 回复前必须输出 `<think>...</think>` 思维链（模板可自定义），流式校验不合规自动重试（上限 10 次），兼容 DeepSeek R1/V3 的 reasoning 字段

### 👥 群聊

- 多角色群聊轮流发言，人设互不串台

### ⚡ 其他增强

- 瞬时错误自动重试、默认预设可删除、快捷指令系统（含插入型指令一键删除）、文本样式预设、键盘安全编辑面板、角色 AI 通读介绍、调色板扩充、输出时界面不动、版本检查与更新日志、顶部通知

## 🚀 开发环境

- Flutter / Dart 3
- 构建：`flutter run`（调试） / `flutter build apk --release`（Android 安装包）

## 🙏 致谢

- **上游项目 [PocketInn](https://github.com/adoretes/PocketInn)**：本项目基于其源码改造，特别感谢上游作者的开源贡献——一切新增功能都建立在它的坚实基础之上
- **[SillyTavern](https://github.com/SillyTavern/SillyTavern)**：数据格式与生态兼容参考
- **DeepSeek AI**：本项目大量代码由 DeepSeek 辅助编写与调试

## 📄 开源协议

本项目继续遵循上游的 **GNU Affero General Public License v3.0 (AGPL-3.0)**，详情见 [LICENSE](LICENSE)。

## 📝 说明

- 这是一个仍在开发中的项目，部分功能和界面可能会继续调整
- iOS 版本因开发环境限制暂未适配，敬请谅解
- 自定义字体：支持字体族名称或 .ttf / .otf 字体文件，推荐[霞鹜文楷屏幕阅读版](https://github.com/lxgw/LxgwWenKai-Screen)
