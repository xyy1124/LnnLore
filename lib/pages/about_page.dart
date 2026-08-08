import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/error_handler.dart';
import '../services/version_check_service.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  // v57：源码提交与构建日期改为构建时注入（--dart-define），不再硬编码——
  // 构建命令：flutter build apk --release \
  //   --dart-define=SOURCE_COMMIT=<git hash> --dart-define=BUILD_DATE=<日期>
  static const String _kSourceCommit = String.fromEnvironment(
    'SOURCE_COMMIT',
    defaultValue: 'unknown',
  );
  static const String _kBuildDate = String.fromEnvironment(
    'BUILD_DATE',
    defaultValue: 'unknown',
  );

  static final Uri _githubUri = Uri.parse(
    'https://github.com/adoretes/PocketInn',
  );

  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 应用信息卡片
          _AppInfoCard(colorScheme: colorScheme),
          const SizedBox(height: 16),

          // 版本信息
          _SectionCard(
            title: '版本信息',
            subtitle: '当前应用版本详情',
            child: FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                final packageInfo = snapshot.data;

                return Column(
                  children: [
                    _InfoRow(
                      label: '版本号',
                      value: packageInfo?.version ?? '读取中...',
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: '构建号',
                      value: packageInfo?.buildNumber ?? '读取中...',
                    ),
                    const SizedBox(height: 8),
                    // v56：便于确认手机安装包对应哪份源码
                    _InfoRow(
                      label: '源码提交',
                      value: _kSourceCommit,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: '构建日期',
                      value: _kBuildDate,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 检查更新
          _SectionCard(
            title: '检查更新',
            subtitle: '自动检查 GitHub 发布的新版本（特别版）',
            child: _VersionCheckCard(colorScheme: colorScheme),
          ),
          const SizedBox(height: 16),

          // 更新日志
          _SectionCard(
            title: '更新日志',
            subtitle: '最近更新内容',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UpdateLogItem(
                  version: 'v1.4.0-special.70',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】三种模式改为"每轮只有一个状态决策者"：快速=主模型（唯一写入者）；后台/严格=主模型**只输出正文**（状态由独立裁判决定，不再输出 patch/narrative/HTML/纯文本状态栏——彻底消除主模型 patch 与裁判 patch 相互覆盖、重复增加、状态栏泄漏正文）',
                    '【特别版】快速模式协议分离：正文正常输出（不再把长篇剧情塞进 JSON reply——转义/截断导致整个对象无法解析的根因），末尾追加 `<TRACKER_UPDATE>...</TRACKER_UPDATE>` 标记块（短状态协议，解析成功率大幅提升）；模型偶尔失败时正文仍完整，只丢这轮状态',
                    '【特别版】后台裁判按会话串行：每会话任务队列 `_pendingTrackerJudges`——正文立即显示、状态稍后更新，但用户下一次发送前**必须等待上一轮状态结算完成**（不再因"裁判返回太晚"整轮状态被丢弃；全局轮次令牌保留作过期兜底）',
                    '【特别版】裁判可选输出最终状态：`{"state":{"字段key":最终值}}` 一次性保存（校验 key/类型/范围后 set，不再增量叠加，从根源消除重复增加）；未输出 state 时仍用 patch 增量（兼容）',
                    '【特别版】历史消息入模前清洗：assistant 历史消息发送给模型前走显示清洗（旧版本已入库的 HTML/纯文本状态栏、状态协议块不再进入模型上下文——模型看到历史每轮输出面板就会继续模仿）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.69',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】后台模式 UI 刷新竞态修复：后台裁判完成写库后，ViewModel 之前因 _isSending 拦截了所有数据库通知（状态已写库但状态栏显示旧值）——variables/choices 通知现在不受发送中状态限制（只刷轻量变量缓存），_isSending 保护仅作用于 messages/session 重载',
                    '【特别版】从模型上下文彻底移除"输出状态栏"角色卡指令：stripPanelTemplates 现在同时剥离面板外的"每次回复末尾输出状态栏/请在正文末尾附带状态面板"等指令句——模型不再收到两套互相矛盾的要求（之前角色卡要求输出面板、App 要求只输出 JSON，导致面板混进正文）',
                    '【特别版】协议明确禁止状态栏混入正文：reply 只写剧情正文；禁止输出 <details>/<summary>/<!--panel--> 状态栏 HTML；禁止输出"当前状态：""状态面板："等纯文本状态栏；状态栏由 App 根据最终状态自动渲染；patch/narrative/consequence 必须在同一 JSON 对象',
                    '【特别版】纯文本状态栏尾部识别（兼容模型犯错）：stripTrailingPlainTrackerPanel 识别正文末尾的"状态栏：\n堕落进度：27/100\n当前状态：压制中"（≥2 行命中 tracker label、每行含冒号，防误删剧情正文），剥离并作为兼容状态来源回写变量（不覆盖模型 patch/setvar 已更新的字段）',
                    '【特别版】诊断日志：[TRACKER_MODE] 每轮打印 mode/mainProtocol/mainPatch/mainNarrative/panelDetected/judgeCalled——快速模式看不到更新时一行确认是哪层失败',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.68',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】状态更新模式持久化修复：TrackerUpdateMode（快速/后台/严格）之前只在内存生效、重启回默认——AppSettingsService 现在读取与保存（重启保持用户选择）',
                    '【特别版】删除旧 tracker_judge_enabled 总开关对后台/严格模式的隐藏拦截：是否调用裁判由状态更新模式决定，旧开关不能拥有第二次否决权（旧开关曾关闭的升级用户后台/严格模式恢复正常）',
                    '【特别版】协议 JSON 示例修正：之前 {"add":{"字段key":数值变化}} 是非法 JSON（模型照抄导致 jsonDecode 失败、patch 提取不到）——改为始终合法的空协议示例（reply/patch/narrative/consequence 全空对象），并在代码块外说明 number 字段写 add、string 字段写 set',
                    '【特别版】状态裁判输出上限动态分配：patch+narrative+consequence 三件套在字段多时 256 tokens 会被截断（isPartial 直接 null → 模式失效）——按字段数分配 (384+字段数*128) 钳到 512-1024；截断/未输出合法协议时自动重试一次（压缩输出），仍失败保留主模型结果',
                    '【特别版】数据库通知分类（ChatDatabaseChange）：messages/session 才重载消息树；variables（Tracker 变量/状态快照）只刷新变量缓存与状态面板、不重载列表；choices 只刷新该消息动作按钮——后台状态裁判写入快照不再触发整树重载',
                    '【特别版】跳底回归修复：后台裁判完成后的变量/快照写入走 variables 通知 → 只刷变量缓存（notifyListeners 不重建 ListView 结构），视口完全不动；不再把任何数据库写入都当消息树变化全量重载',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.67',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】状态系统升级为"剧情驱动器"：上一轮完整动态解读（narrative）与下一轮剧情影响指令（consequence）注入下一轮主模型——模型不只读到"压制中"标签，还读到"反抗正在失去效果"与"除非成功脱身，否则保持行动受限"等剧情约束，正文持续体现状态（原来 narrative 只进消息快照供状态栏显示，下一轮正文读不到）',
                    '【特别版】consequence 协议：状态裁判/主模型输出 `{"consequence":{"字段key":"该状态下一轮应如何影响角色行为"}}`——narrative 解释状态为什么形成，consequence 说明下一轮应如何持续体现（行动限制/心理反应/连续状态保持/反转条件）',
                    '【特别版】状态约束指令（kTrackerStoryInfluenceSuffix）：当前状态是已发生的剧情事实、正文必须自然体现、不得无视/重置/无理由逆转、状态变化必须有实际事件支撑、服装/伤势/关系/位置等连续状态必须保持（无明确恢复事件时）',
                    '【特别版】消息快照升级 v5（state + narrative + consequence）：v5 优先读取、v4 回退；consequence 合并规则同 narrative——已变化字段必须有影响指令（裁判漏写回退该字段 narrative，都没有则确定性兜底）',
                    '【特别版】清理 Tracker prompt 的 ** 残留：formatTrackerInstruction/裁判提示中的 Markdown 粗体标记不再进入发送给模型的系统提示（污染协议文本）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.66',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】状态更新三档模式（通用设置 → 状态更新模式，默认快速）：',
                    '· 快速（单次 API）：主模型回复同时输出 reply+patch+narrative，不再等待第二次裁判请求——正文立即显示，速度最快',
                    '· 后台精确：正文先显示、状态裁判后台补算（轮次令牌防旧裁判覆盖新状态，状态栏稍后更新）',
                    '· 严格：等待状态裁判完成后再显示正文（最高一致性，最慢）',
                    '【特别版】状态裁判提速：专用精简预设（maxTokens 256、temperature 0、关闭思维链）+ 输入正文裁剪（用户消息 ≤1000 字、角色回复 ≤3000 字，命中语义提示关键词的段落优先保留——selectRelevantText）',
                    '【特别版】裁判防重复叠加：主模型已通过 patch 更新的字段，裁判不得再次增加同一事件（避免 20→主+2→裁判+2→24）；裁判只补充主模型遗漏的变化',
                    '【特别版】主模型协议扩展：narrative 纳入 {reply, patch, narrative} 输出要求（patch 修改的字段必须给解读、只能使用字段 key）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.65',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】动态解读（narrative）完整修复——"值变了、点号还在、解释却空了"根因：① narrative key 未规范化（patch 会映射中文 label→key，narrative 不会——模型用"当前状态"作键时模板读不到）；② 裁判允许省略已变化字段的解读；③ v4 快照只存裁判本轮 partial narrative，不继承上一轮；④ 字符串新值不在 presentation.states 枚举时 gettitle/gettext 空白。',
                    '【特别版】narrative 与 patch 共用同一 key 规范化（canonicalTrackerKey：真实 key > label > aliases）——模型输出中文 label/别名作 narrative 键也能正确显示',
                    '【特别版】裁判 prompt 强制规则：patch.set/add 全部字段、主模型修改的全部候选字段、数值没变但含义明显改变的字段——凡是状态变化的字段禁止省略 narrative、禁止空字符串、只能使用字段 key',
                    '【特别版】App 补齐 narrative（changedKeys + mergeNarrative）：未变化字段且裁判没新解读→继承上一轮完整解读；已变化字段有裁判解读→用新解读；已变化字段裁判漏写→不得继承旧描述，回退新阶段静态描述；连静态描述也没有→确定性兜底（"X已变为…，具体表现以本轮剧情为准"）——v4 快照保存合并后的完整解读，不再整包覆盖成 partial',
                    '【特别版】渲染兜底：string 字段未匹配 presentation.states 时 gettitle/getnarrative 回退原始值（"压制中""乳贴脱落、衣物凌乱"等模型自创状态也能显示，不再留下空分隔符）',
                    '【特别版】string 字段新增 `allowCustomValues` 协议（默认 true 兼容旧卡）：声明 false 的有限状态字段只接受 presentation.states 枚举值——模型自创未声明状态被拒绝写入；指令注入 allowedValues 列表（自由组合字段如服装状态保持 true）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.64',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】消息长按菜单架构重构：从"每条消息一个 OverlayPortalController + 全局 owner + 下一帧延迟显示"改为 **showMenu() Navigator 路由**——旧方案的排队回调在菜单关闭后仍会执行（偶尔不弹/弹过一次后要等几秒才能再弹），且菜单附着在列表消息组件上、列表重建时 Overlay 状态竞争；现在菜单由 Navigator 管理，不随消息组件重建，菜单外点击由路由自带关闭，关闭后下一次长按立即可用',
                    '【特别版】长按菜单防重入：`_openingActionMenu` 标志 + finally 释放——showMenu 弹出期间忽略同消息的重复长按请求，任何异常也不会卡死后续长按',
                    '【特别版】保留输入框 TapRegion 组：点击菜单项（复制/编辑/删除）不收起输入框键盘',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.63',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】状态裁判基线修复：裁判 patch 改为在**候选状态**（旁白 + 主模型 patch）上叠加——之前以旁白基线重新应用裁判 patch，裁判看到的状态与实际应用基线不一致（原始 20 → 主 +3 → 裁判看到 23 → 裁判 +2 → 基线 20+2=22 丢 +3），且主模型更新多字段时裁判只返回一个字段会导致其余字段丢失',
                    '【特别版】本轮动态解读（narrative）：状态裁判除 patch 外返回 `narrative`（每字段结合本轮剧情的一句话解读）——数值没跨阶段文字也能随剧情变化，不再永远重复同一段固定描述；保存到消息级快照 v4（`__msg_tracker_state_v4__:<id>` 含 state + narrative，历史消息显示消息时刻的解读）；新增模板变量 `{{getnarrative::key}}`（动态解读优先，无则回退静态 gettext）',
                    '【特别版】字段语义提示（semanticHints）：卡可声明 meaning / positiveSignals / negativeSignals / neutralSignals——提供"理解方向"而非死规则，注入状态指令与裁判（neutral 中的行为不得触发变化）；App 仍限制未知字段/上下限/单轮上限/重复事件',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.62',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】消息操作菜单手势修复（长按专属）：普通点击不再弹菜单（点击只关闭已打开的菜单），**长按**才打开应用操作菜单——之前 onTapDown 让普通点击也可能弹菜单',
                    '【特别版】关闭消息正文原生文本选择（selectable: false）：ChatMarkdownBody 默认包 SelectionArea，长按时系统复制菜单与应用菜单同时争抢长按手势——现在长按只由应用菜单处理，复制由菜单内"复制"按钮负责（复制整条消息）',
                    '【特别版】didUpdateWidget 不再无条件关闭菜单：只有消息身份/内容或交互状态真正变化时才关闭——之前每次父组件重建（状态栏刷新/变量刷新/普通列表重建）都在下一帧隐藏菜单，刚弹出就被关闭',
                    '【特别版】菜单上下自适应：下方空间不足（靠近屏幕底部/输入框）时显示在消息上方，不再被遮挡',
                    '【特别版】打开请求防重复：长按识别与列表重建在同一帧重复触发时只放行最后一次（令牌保护）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.61',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】上下文用量计入 Tracker 每轮常驻指令：状态字段 + 更新规则 + JSON patch 输出协议（抽为共享常量，chat_service 与用量估算同源）——发送后详细统计与会话打开估算都补算 Tracker，不再漏算后置注入',
                    '【特别版】主界面用量胶囊改为"约 X / 可用 Y（预计 Z%）"——估算值明确标注"约"，不再显示成伪精确的"已用"',
                    '【特别版】安全输入上限：进度条分母与"可用"从"模型窗口"改为"窗口 - 输出预留 8K - 安全余量 2K"——剩余 10K 不再误导为还能安全输入 10K（输出也要占空间）',
                    '【特别版】用量详情页分三组：下轮预计输入（约）/ 上轮实际输入与输出（实，API usage）/ 安全输入上限与预计剩余',
                    '【特别版】Tracker 常驻精简确认：每轮只发送字段 key/label/范围/当前值/模糊程度增量/单轮上限/输出协议——HTML、CSS、阶段长描述等仅用于 App 渲染的内容不进模型上下文',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.60',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】剧情自主状态判断（状态裁判·双阶段）：剧情生成后**独立调用一次状态判断请求**（只输出 JSON patch）——剧情模型专心写剧情，状态由裁判按规则确定性判断；裁判 patch 优先（在旁白基线上应用，忽略主模型 patch 防同 key 叠加），普通发送/重生成/继续/群聊四入口统一接入',
                    '【特别版】字段协议扩展：`updatePolicy`（mode: explicit/conservative/active + qualitativeDeltas 程度词→增量 + maxAutoDeltaPerTurn 每轮上限）与 `aliases`（字段别名：好感/亲密感等口语说法）——角色卡可声明"一点=1、明显=5、大幅=10"等量化规则',
                    '【特别版】本地模糊解析："好感提升一点" / "好感明显提高" / "好感稍微下降"（无数字）按卡 updatePolicy 确定性量化（支持"程度词+动词"与"动词+程度词"两种语序）；**无卡声明不猜数字**',
                    '【特别版】状态指令注入定性规则：模型/裁判收到 qualitative 程度词映射 + mode + 每轮上限，并明确要求"剧情明确表示上升/下降时即使无数字也必须输出 patch，不得因无数字返回空 patch；同一事件每轮最多更新一次"',
                    '【特别版】设置页新增"状态更新"入口：状态裁判开关（默认开）+ 三档模式（仅明确指令/保守剧情判断-默认/积极剧情判断）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.59',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】滚动竞态修复（"流式输出有时跳底、有时不跳"）：统一取消入口 `_cancelAutomaticScrollWork`——生成开始（isSending 上升沿）/用户拖动/会话切换时一次性取消跳底、位置恢复与 pending restore 全部待执行任务',
                    '【特别版】`_scheduleScrollRestore` 加统一令牌 + isSending/frozen/sessionId 检查（之前无令牌，等待布局期间开始生成/手动滚动后仍会突然 jumpTo）；跳底循环每次 jumpTo/ensureVisible 前再查令牌与生成状态',
                    '【特别版】解冻后显式恢复像素位置（`_preserveOffsetAfterUnfreeze`）：解冻通知发生、新列表布局前保存 pixels，下一帧恢复——用户流式期间手动滚动到哪里，完成后停在哪里（不再依赖"尾部追加不会动"假设）',
                    '【特别版】移除消息列表 `ValueKey(sessionId)`：草稿会话第一次发送创建正式会话并更换 ID，key 变化重建整棵列表、新 ID 被当成首次打开触发可靠跳底（"有时跳底"来源之一）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.58',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】渲染回归修复（根因）：模板选择从"第一个非 null"改为"第一个**有效**"——角色卡 uiHints.template 常是 "{label}：{value}" 占位文本（不含 get 变量），v54 兼容读取后它会截断 post_history_instructions 的真实 HTML 面板、所有卡掉进统一内置面板（"面板样式丢失/每张卡一样"回归根因）；新增 TRACKER_RENDER 诊断日志（source=tracker.template/post_history_instructions/StatusFallback/builtin）',
                    '【特别版】Safe HTML 外层恢复透明：状态面板不再套统一深色外框（v50 兜底造成"双层卡片"并裁剪卡自定义圆角）——面板外观完全由角色卡 HTML 控制；标题栏单独带轻底色由 App 控制',
                    '【特别版】折叠偏好三态判断：\'1\' 展开 / \'0\' 收起 / 未保存回退卡 defaultExpanded——之前 \'0\' 与未保存等同，defaultExpanded=true 时用户手动收起后重建又被展开',
                    '【特别版】状态事务完整化：_processAssistantOutput 改为**纯计算不写库**（解析 + 应用 setvar/patch/面板回写），最终变量表由调用方在 assistant 消息保存成功后统一提交（sendMessage/重生成/继续/群聊四个入口一致）——消息保存失败/取消时状态不再单独前进',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.57',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】setvar 保护顺序修正：先 canonicalize（中文 label → 真实 key）再过滤受保护字段，`{{setvar::烙印值::5}}` 不再覆盖旁白（（烙印值+10））已落地的结果',
                    '【特别版】关于页源码提交/构建日期改为构建时注入（--dart-define=SOURCE_COMMIT / BUILD_DATE），不再硬编码',
                    '【特别版】更新检查默认指向本分支发布仓库 xyy1124/LnnLore，并与本地安装版本比较（可配置回上游 adoretes/PocketInn）',
                    '【特别版】8 张角色卡全部补齐阶段描述（母猪教 mz_drug/mz_serv 补 states + 模板阶段行；新卡"一觉睡醒"已达标）；角色卡生成技能约束升级（string 字段 states 逐字段强制、verify 扩到 10 项）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.56',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】状态事务（核心）：旁白（（烙印值+10）等）改为**内存延迟提交**——发送前只在内存应用（模型状态注入/快照用），模型回复成功、assistant 消息保存后与 patch/setvar 一起写入；取消生成/API 失败/思维链重试耗尽/崩溃时状态保持原样，不再出现"状态变了但剧情没保存"',
                    '【特别版】模型回复成功但未输出状态协议时，仍提交内存中的旁白状态（用户确定性指令不依赖模型输出）',
                    '【特别版】setvar 统一 canonicalize：`{{setvar::烙印值::30}}` 与 `{{setvar::yw_brand::30}}` 现在结果一致（中文 label 映射回真实 key，未知字段丢弃）——之前只有 JSON patch 走 canonicalize，setvar 直接进 reducer',
                    '【特别版】删除消息分支时同步清理对应的状态快照（`__msg_tracker_state_v3__:<id>`），不再残留孤儿数据污染变量表',
                    '【特别版】状态面板折叠偏好持久化：用户手动展开/收起按"会话+角色卡"记忆（`__tracker_expanded__:<角色id>`），优先级：手动偏好 > 卡 defaultExpanded > 默认收起；面板加稳定 key，列表重建时折叠状态不再串消息',
                    '【特别版】关于页新增"源码提交 + 构建日期"显示，方便确认手机安装包对应的源码版本',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.55',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】模型面板回写统一走 reducer：旧卡兼容的 HTML 面板解析结果之前直接写变量表（模型输出"烙印值：999/100"会把 999 绕过 min/max 直接入库）——现在转 StatePatch → canonicalize → reduce（类型校验 + clamp），所有状态来源统一入口',
                    '【特别版】StatePatch.protocolDetected：现在能严格区分"模型输出了合法空 patch（判断无变化）"与"模型完全没输出协议"——空 patch（`{"patch":{"set":{},"add":{}}}`）protocolDetected=true；TRACKER_RESPONSE 日志改用该字段',
                    '【特别版】继续生成按消息链恢复分支基线：continueAssistantResponse 之前直接读全局最新状态（从记忆树/分支切换后"继续"会状态错位）——现在与重生成共用 `_restoreTrackerBaselineForHistory`（历史快照恢复 + 旁白重应用 + replace 写入）',
                    '【特别版】群聊变量读取顺序统一：generateGroupReply 之前用 session.id（草稿 id）读变量、之后才建立正式会话——新建群聊第一轮会读到空草稿状态；现在先建立正式会话再读变量（与 sendMessage 一致）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.54',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】setvar 统一经过 tracker 保护与校验：模型同一轮输出 `{{setvar::yw_brand::5}}` 之前会直接覆盖旁白（烙印值+10）已落地的值——现在受保护字段（旁白已落地）过滤、tracker 声明字段走 reducer（类型校验 + min/max clamp）、其余字段直接写入，所有状态来源不再绕过统一入口',
                    '【特别版】`uiHints.template` 兼容读取：早期注释示例把 template 写在 uiHints 里、实际解析只读 tracker 顶层——现在两个位置都读（tracker.template 优先），照旧注释写法做的卡也能生效；注释示例已修正',
                    '【特别版】内置状态面板进度条：number 字段（带 min/max）自动渲染进度条（百分比宽度 + 阶段色/默认紫）——即使卡没写模板也能看到"值/max + 进度 + 阶段"',
                    '【特别版】状态面板初始展开跟随卡声明 `tracker.defaultExpanded`（默认收起）——卡作者可控制面板默认状态',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.53',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】插入型快捷指令占位标记一键删除：Backspace/Delete 删到标记（`\uE000指令名\uE001`）任意一个字符时一次性删除整个标记——之前按一次只删一个码元，留下半截标记（渲染异常），还要删很多下才能删完（用户反馈）',
                    '【特别版】其余 6 张角色卡批量升级阶段描述系统（presentation）：夜无央/洗脑女仙/芭蕾三姐妹/苏蕴泠/蜜欧拉/假小子青梅全部字段声明 ranges/states 并接入 `{{gettitle}}`/`{{gettext}}`/`{{getcolor}}` 模板变量（母猪教 v52 已升级）——7 张卡全部支持"数值跨段自动切换阶段标题与长描述"',
                    '【特别版】角色卡生成技能（character-card-creator）强制要求升级：stateSchema 每个字段必须声明 presentation（number 字段 ranges≥3 段、string 字段 states≥2 枚举）、面板模板必须含阶段描述行、verify 检查扩到 8 项——后续新生成的卡自动带阶段描述系统',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.52',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】状态阶段描述系统（presentation）：角色卡可在字段上声明 `presentation.ranges`（数值分段：gte/lt + 标题/颜色/长描述）与 `presentation.states`（字符串枚举描述）——App 按当前值**确定性渲染**阶段标题/颜色/长描述，不再依赖模型每轮编造，数值变化文字自动变化',
                    '【特别版】新增模板变量：`{{gettitle::key}}`（阶段标题）、`{{gettext::key}}`（长描述）、`{{getcolor::key}}`（阶段颜色）、`{{getpercent::key}}`（min/max 归一百分比）——旧角色卡只用 `{{getvar::key}}` 完全不受影响；内置兜底面板也升级（带阶段描述的字段显示"值 · 阶段标题 + 描述"块）',
                    '【特别版】变量值 HTML 转义：所有插入模板的文本（getvar/gettitle/gettext/getcolor）统一转义 `< > & 引号`——长描述/阶段标题含这些字符不再破坏模板结构或注入样式',
                    '【特别版】角色卡试点：母猪教叙事者 mz_nano 增加 5 段数值描述（尚未启动/初步适应/明显改造/深度重构/完全接管）、mz_rank 增加 4 段枚举描述（新收/见习/正式/核心），模板已接入新变量——验证后其他六张卡按同格式批量升级',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.51',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】编辑/重生成后 tracker 状态按消息分支回滚（核心修复）：消息树是分支化的、状态却是会话级单份——重生成/编辑重发前先从历史最近角色消息的 v3 快照恢复基线，再重新应用本条用户消息的旁白，用 replace 写入（清除旧分支残留字段），新分支不再从旧分支推进后的状态继续（"编辑像新消息"根因）',
                    '【特别版】切换分支/删除分支/重开会话同步恢复状态：_loadSession 加载后按当前消息链恢复 tracker 基线（最后一条是用户消息时不回滚，避免旁白丢失）；replaceSessionVariables 新增（先删后插，纯 upsert 无法清除旧分支字段）',
                    '【特别版】编辑弹窗按钮改两层布局：快捷指令一行、"取消/保存/发送"一行固定在底部——手机宽度不够时"保存并发送"之前被横向滚动藏到屏幕外，看起来像没有发送按钮；按钮文案改为"发送"',
                    '【特别版】顶部提示（AppTopNotice）：角色导入/删除等操作反馈从屏幕顶部滑入滑出（OverlayEntry 实现，不依赖底部 SnackBar——键盘/横屏/不同屏高下不错位）；角色列表的导入成功/失败/同名跳过/删除成功全部替换',
                    '【特别版】流式输出视口冻结加固：消息操作区"显示"与"可用"分离——生成/冻结期间按钮保留布局（淡出+禁用点击），不再因按钮消失导致消息高度变化、视口跳动；自动跳底循环增加 isSending 检查（打开会话后的跳底任务不再在发送期间抢滚动）；发送/重生成/继续完成时改为先加载（保持冻结）再解冻，避免多次中间重建',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.50',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】状态注入显式列出真实 key 映射：`key=yw_brand | label=烙印值 | type=number | range=0..100 | current=0`——之前只注入中文 label，模型即使按剧情输出 `{"add":{"烙印值":10}}` 也会被当成新变量保存、面板仍读 yw_brand（"剧情推进不更新"根因）',
                    '【特别版】patch 字段名规范化（canonicalizePatch）：模型输出中文 label 自动映射回真实 key；完全未知字段丢弃并记录日志（不再宽松存成新变量污染变量表）；卡未启用 tracker 时保持宽松（自定义变量场景）',
                    '【特别版】状态指令从"独立末尾 system"改为合并进**最后一条** system：末尾突兀追加 system 对部分 OpenAI 兼容接口/本地模板不稳定（可能被忽略），合并既不靠近开头被冲淡、也保持消息结构稳定',
                    '【特别版】TRACKER_RESPONSE 诊断日志始终打印：`protocol=有/无`（模型是否输出 patch 块）`set=... add=...`——可靠区分"模型没遵守协议"与"模型判断无变化"（空 patch 之前被解析器当"没有协议"）',
                    '【特别版】状态面板默认收起：标题栏兜底"状态面板"（无 summary 的面板也有可点击标题栏），点击展开/收起；面板外层加统一深色底 + 细边框（收起时标题栏也有底色，不再透明悬浮）',
                    '【特别版】7 张角色卡面板根节点增加每卡专属 background-color（夜无央 #171020 / 母猪教 #17120d / 洗脑女仙 #101b26 / 芭蕾三姐妹 #21101c / 苏蕴泠 #151725 / 蜜欧拉 #1b130d / 假小子青梅 #10201d），渐变保留——渲染器支持渐变显示渐变，不支持则纯色兜底',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.49',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】快捷指令状态更新修复：快捷指令的界面输入只是指令名（如"旁白"），用户补充内容（如"烙印值提高40%"）之前只送给了模型、本地状态解析看不到——v49 新增 trackerText 参数，快捷指令把补充文本单独交给旁白解析器，状态本地确定性落地（"快捷指令下状态不更新"根因）',
                    '【特别版】旁白解析支持自然语言：`烙印值提高40%` / `体力增加10` / `体力减少5` / `降低/上升/下降/加/减` 等直接识别为增减量（% 忽略、数值为增量，与 0-100 百分制一致）；括号格式仍优先',
                    '【特别版】修复 `（烙印值-5）` 被当成"增加 5"的 bug：负号被正则捕获在运算符里、数值解析时丢失——现在符号与数值合并，减法正确落地（clamp 到 schema min）',
                    '【特别版】状态面板支持折叠：`<summary>` 标题不再删除，提取为 Flutter 原生标题栏（箭头指示），点击收起/展开——折叠由 StatefulWidget 控制，不再依赖 HtmlWidget 对 `<details>` 的不可靠渲染；无 summary 的面板行为与旧版一致',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.48',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】角色卡状态指令真正送达模型：默认预设（assets/Default.json）里 Post-History 的 identifier 是 `jailbreak` 而非 `post_history_instructions`——v47 只改了后者、默认路径下角色卡规则仍然没发出去（"状态不更新"主因）。v48 两个 case 都合并注入角色卡 post_history_instructions（预设文本在前、卡规则在后）',
                    '【特别版】状态指令改为独立最后一条 system 消息：不再追加到第一条 system（后面大量角色卡/预设内容会冲淡指令）；并要求模型**每轮都输出 patch**（无变化也输出空 patch {"patch":{"set":{},"add":{}}}），日志可区分"模型判断无变化"与"模型没遵守协议"',
                    '【特别版】面板提取边界修复：`<!--panel-->` 标记必须**独占整行**才算面板边界（原非贪婪正则把说明句里提到的字面 `<!--panel-->` 当起点，把"标记；数值用…"说明尾巴截进模板）；提取与提示词剥离共用同一解析器',
                    '【特别版】面板 summary 清洗修复：删除整个 `<summary>…</summary>` 元素（含标题文字）——原只删标签导致"🧡 母猪教·教廷状态面板"等标题变成普通正文显示在面板外',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.47',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】状态面板真正按角色卡 HTML 模板渲染：每张卡的深色 HTML 面板（`<details><summary>…</summary><div style=…>` 卡片）定义在 `post_history_instructions` 的 `<!--panel-->` 段——v47 新增提取（优先级 tracker.template → post_history_instructions 的 panel HTML → StatusFallback 纯文本 → 内置），各卡显示各自的面板样式（不再统一套紫色文字容器"每张卡样式都一样"）',
                    '【特别版】角色卡 post_history_instructions 真正注入模型：之前该字段被列为 unused、模型完全收不到卡的状态面板/字段变化指令（"状态永远不更新"根因）——v47 预设与角色卡内容合并注入；`<!--panel-->` HTML 模板块注入前剥离（App 按最终状态自己渲染面板，模型只输出 JSON patch，避免"输出 HTML 面板"与"只输出 JSON patch"指令冲突）',
                    '【特别版】消息快照改为 v3 结构化状态 JSON（`__msg_tracker_state_v3__:<id>`）：只保存该消息时刻的 tracker 状态值，不再保存预渲染 HTML——显示时用消息对应角色卡 + 当前 HTML 模板动态渲染（样式永远与卡一致、改模板无需迁移历史数据）；旧 v2/v1 HTML 快照与全局 `__special_status_html__` 全部忽略',
                    '【特别版】TRACKER_FLOW 排查日志：旁白（烙印值+10）应用链路每步打印（tracker 是否解析/正则是否匹配/写入前后值），装日志包后 adb logcat 过滤 [TRACKER_FLOW] 即可定位"数值不更新"断在哪一环',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.46',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】统一角色卡扩展读取器（CharacterCardExtensionsReader）：TrackerConfig / StatusFallback 模板 / 正则脚本全部改用统一读取——兼容真实手机导入链路的运行时 map 类型（Map<dynamic,dynamic>、顶层已展开 data 等），不再因类型检查过严导致某张卡静默降级为统一内置面板（"每张卡样式都一样"根因修复）',
                    '【特别版】StatusFallback 查找放宽：脚本名大小写不敏感、容忍首尾空格、兼容 script_name/name 键名与 replace_string 字段',
                    '【特别版】模板渲染不依赖 tracker 是否启用：只要卡有 StatusFallback 模板就按模板渲染（即使 tracker 声明缺失/畸形），避免所有卡退化成同一个内置面板；旁白解析随 TrackerConfig 放宽同步恢复',
                    '【特别版】修复草稿会话状态丢失：发送时先建立正式会话（persistSession 提前），旁白/变量写入正式会话 id（原逻辑写入草稿 id，第一轮"（烙印值+10）"等状态更新会全部丢失）',
                    '【特别版】变量刷新显式等待：会话加载/发送/重生成/继续/群聊后 await 变量表刷新（原 unawaited 可能让状态栏显示旧值直到下一次 notify）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.45',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】规范消息快照体系：消息级快照改为 v2（`__msg_status_html_v2__:<id>`）——每条助手消息都用"该消息处理后的最终状态 + 角色卡 StatusFallback 模板"生成规范 HTML（模型只输出 JSON patch 也有快照；数值=消息时刻状态，历史消息不再被后续轮次的最新状态污染）；模型原始 HTML 不再作为显示快照（仅保留解析状态用途），旧 v1 快照一律忽略',
                    '【特别版】旁白字段本轮去重：用户输入（烙印值+10）等旁白确定性落地后，模型若再对同一字段输出 patch 会被过滤（防止 20→旁白+10→模型add+10→40 的重复叠加）；重生成时从原用户消息解析保护字段（只阻止重复更新，不重新应用）',
                    '【特别版】群聊状态面板按发言人角色渲染：每条消息用各自 resolvedSpeaker 的角色卡模板/tracker 配置/正则脚本（不再套用全局 activeCharacter）',
                    '【特别版】状态面板渲染尊重卡样式：卡模板是富 HTML 时直接渲染（不再强制套 App 紫色容器），纯文本模板才套默认容器；getvar 检测改为大小写不敏感',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.44',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】旁白 = 赋值越界保护：number 字段直接赋值（烙印值=999）也走 reducer 按 min/max clamp，字符串字段直接写入',
                    '【特别版】移除全局旧 HTML 面板兜底：模型已改为输出 JSON patch，旧全局面板（`__special_status_html__`）里写死的数值不再显示在每轮消息上',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.43',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】版本号与功能对齐：1.4.0-special.43+98（状态栏/快照链路持续收敛，为 v44 的旁白 clamp 与全局兜底移除做准备）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.42',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】状态栏"未更新"字样根因修复：输出指令让模型"按模板原样输出"导致 {{match}} 与"状态栏未更新"前缀被原样带进面板——显示层统一清洗（去前缀 + 去 {{match}} + 剥 details/summary）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.41',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】状态不更新真正根因修复：变量表为空时不再拦截状态注入（用 initialState 兜底），新会话也会给模型输出面板指令；各卡状态栏显示各自字段（不再顶着"状态栏未更新"怪文案）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.14',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】角色立绘清晰度修复：列表缩略图 256→1024（书架封面/头像放大不糊）；导入与同名覆盖的头像超预算不再丢弃，自动降采样 ≤2048 保存（不管多大图都能加载成功）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.13',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】消息动作按钮（choices）：模型输出 {reply, patch, choices} 时 choices 解析入库，显示为消息下方可点击动作条（ActionChip），点击把动作发送给模型；ProcessedAssistantOutput 结构体重构（正文+patch+choices 一体化）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.12',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】修复消息显示协议内容：开场消息（first_mes）与流式输出均走状态块/协议 JSON 剥离，模型流式吐 {reply,patch} 时界面不再露出协议原文；协议 JSON 解析失败也不显示原文',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.11',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】角色列表书架卡片改竖版：双列网格 16:9 竖封面（头像铺满+底部角色名），长按菜单不变',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.10',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】修复消息正文丢失：模型输出 {reply, patch} 结构时 reply 字段提取为正文（不再整块剥离只剩状态），含 \\n/转义还原',
                    '【特别版】角色列表改书架式：长方形封面卡片（头像铺满+底部角色名），点击进编辑，长按弹菜单（开始聊天/AI 通读/导出/删除）',
                    '【特别版】AI 通读入口移到角色列表顶部按钮行（auto_awesome 图标），点击后选择角色进入 AI 通读介绍',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.9',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】修复导入新角色卡后发消息报"未知错误"：tracker 声明强转崩溃（schemaVersion 为字符串、template 畸形、ST 正则数组字段等）全部改为安全读取+顶层兜底，任何卡结构都不再崩',
                    '【特别版】导入角色卡同名改为覆盖：保留原 id 与会话关联，替换卡内容/头像/内嵌世界书（旧图清理，无新图保留旧头像）',
                    '【特别版】压缩包/多选导入与文件夹导入统一：只收角色卡（json/png），配套世界书一律走角色卡内嵌 character_book 自动创建关联',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.8',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】状态跟踪（Tracker）协议体系：角色卡 data.extensions.tracker 声明 stateSchema/initialState/uiHints；模型只输出结构化 patch（JSON patch set/add 或 <STATE> 兜底），App 解析+校验（类型/clamp）+reducer 叠加后持久化，副作用块不入库不显示',
                    '【特别版】下一轮自动把当前状态注入 prompt（【当前状态】自然文本段，按 schema 中文标签）；聊天页顶部原生状态栏实时显示（App 渲染，非模型 HTML），可折叠',
                    '【特别版】协议与既有 setvar/getvar 变量持久化互通：同一会话变量表，状态栏、{{getvar}} 注入、正则脚本共用一套状态',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.7',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】ST 变量宏跨轮持久化：AI 回复中的 {{setvar::key::value}} 自动写入会话变量表（DB v7），下一轮 {{getvar::key}} 注入角色卡/世界书/预设时取真实值；状态栏数值跨轮更新生效，setvar 副作用文本不入库不显示',
                    '【特别版】正则脚本系统：角色卡自带 ST extensions.regex_scripts 自动执行（AI 输出显示阶段，支持捕获组替换/删除/trim/禁用），状态栏兜底等正则原样可用；设置页新增总开关',
                    '【特别版】HTML 面板完善：div/table/span/font/style 标签保留内容渲染，状态栏面板可直接展示（配合 {{getvar}} 动态数值）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.6',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】快捷指令占位符体系：插入型/询问型在输入框以斜体彩色【快捷指令：名】占位显示，发送时才展开提示词给模型（界面/复制/预览均不暴露提示词原文）；编辑消息时可再插入快捷指令；编辑重发后消息仍显示占位形式',
                    '【特别版】输入区 UI 重做（E 方案）：发送键内嵌输入框右下角圆形渐变（发送/停止切换、禁用点击穿透）；快捷指令入口改输入框上方左侧胶囊；工具按钮（用户设定/世界书/预设）统一圆角胶囊靠左一组，长名自动限字省略不超界；输入栏默认两行高度',
                    '【特别版】版本号与功能对齐：1.4.0-special.6+61（覆盖安装必生效，请在关于页核对版本号）',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.5',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】群聊上下文上限修复：群聊会话未记录预设时继承全局预设，上下文用量不再回退模型默认 128K（与单聊 1M 一致）；新建群聊自动携带当前预设',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.4',
                  date: '2026-08-08',
                  changes: [
                    '【特别版】上下文用量常驻显示：每个聊天输入框右上侧始终显示用量条（环形进度 + 已用/总量），打开会话即估算，发送后更新为接口精确值',
                    '【特别版】正文支持角色状态栏 HTML：列表（ul/li）转 markdown、表格降级为 | 分隔文本、span/font/center 等剥标签保留内容、br 换行',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.3',
                  date: '2026-08-07',
                  changes: [
                    '【特别版】DeepSeek 原生思考模式：设置新增档位（关闭/高/最高，默认最高 max），仅官方端点发送 thinking + reasoning_effort；原生思考走宽松校验，不再 10 次退回烧 token',
                    '【特别版】思维链模板强化：明确第三方导演/编剧/审稿人视角，严禁角色第一人称替角色思考；开关语义理清为"严格校验/仅引导"',
                    '【特别版】回底/到底稳定性重做：列表末尾真实底部锚点，打开会话与"到底"按钮统一 Scrollable.ensureVisible 对齐真实底部（不再误信 maxScrollExtent 假底部白空白）；浏览位置保存 wasAtBottom，上次在底部时重新可靠跳底',
                    '【特别版】用户滚动位置仅在真实手势时保存（NotificationListener），自动跳底/布局校正不再污染；Markdown 图片固定宽度 + 加载期占位高度，抑制高度抖动',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.2',
                  date: '2026-08-06',
                  changes: [
                    '【特别版】快捷指令新增"插入输入框"类型：点击插入光标处可多次累计；编辑询问型消息可直接改补充内容；菜单改三组网格卡片；类型选择即时高亮',
                    '【特别版】群聊人设修复：历史消息带发言人前缀并转 user 角色（模型不再把他人发言当自己说的），每次请求注入当前发言者自己的角色卡',
                    '【特别版】历史会话滚动位置：记住每个会话浏览位置，切换恢复；无记录时多帧校准可靠跳底；"到底"按钮循环校准一次到位（AI 输出中/完成后界面保持不动）',
                    '【特别版】上下文用量口径理清：按最终发送的 prompt 统计（世界书按实际注入文本、未分类来源不静默丢失），接入接口真实 usage（流式 stream_options）展示校准',
                    '【特别版】长期记忆提取修复：assistant 计数语义明确、合并所有记忆去重（手动添加记忆不再导致每次都提取）',
                    '【特别版】DeepSeek 余额修复：host 精确匹配、金额字符串兼容、加载/不可用状态展示、配置变化自动重查',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.4.0-special.1',
                  date: '2026-08-04',
                  changes: [
                    '【特别版】强制思维链：最高优先级 12 步模板（可多方案编辑），兼容 DeepSeek reasoning 思考（CoT 抑制模型不再误退），违规自动退回/摧毁重试',
                    '【特别版】群聊：多角色创建、轮流回复、发言人标识',
                    '【特别版】角色 AI 通读介绍：深度解读 + Markdown 渲染，可独立选择模型',
                    '【特别版】快捷指令、文本样式预设、48 色调色板、键盘安全编辑面板、503 自动重试',
                    '【特别版】GitHub 新版本自动检查提示',
                  ],
                ),
                _UpdateLogItem(
                  version: 'v1.3.2',
                  date: '2026-07-30',
                  changes: ['为聊天消息列表添加渐变遮罩效果，提升视觉体验', '优化 ResolvedApiConfig 的请求体构建，支持合并自定义消息'],
                ),
                _UpdateLogItem(
                  version: 'v1.3.1',
                  date: '2026-07-25',
                  changes: ['修复上传和恢复错误时静默略过的问题', '优化备份和恢复功能，增加进度反馈和状态更新', '调整预设温度参数为可选，并更新相关处理逻辑', '角色编辑页支持创建并绑定世界书'],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 开源许可
          _SectionCard(
            title: '开源许可',
            subtitle: '第三方开源库',
            child: Column(
              children: [
                _LicenseItem(
                  name: 'Flutter',
                  license: 'BSD-3-Clause',
                  onTap: () =>
                      _showLicenseDialog(context, 'Flutter', flutterLicense),
                ),
                const SizedBox(height: 8),
                _LicenseItem(
                  name: 'Dart',
                  license: 'BSD-3-Clause',
                  onTap: () => _showLicenseDialog(context, 'Dart', dartLicense),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 联系方式
          _SectionCard(
            title: '联系方式',
            subtitle: '反馈与支持',
            child: Column(
              children: [
                _ContactItem(
                  icon: Icons.code_rounded,
                  label: 'GitHub',
                  value: _githubUri.toString(),
                  onTap: _openGitHub,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 版权信息
          Center(
            child: Text(
              '© 2026 PocketInn Team. All rights reserved.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showLicenseDialog(BuildContext context, String name, String license) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name 许可证'),
        content: SingleChildScrollView(
          child: Text(
            license,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _openGitHub() async {
    var launched = false;

    try {
      launched = await launchUrl(
        _githubUri,
        mode: LaunchMode.externalApplication,
      );
    } on Object catch (error) {
      debugPrint('about_page: launchUrl failed: $error');
      launched = false;
    }

    if (!launched && mounted) {
      handleAppException(
        context,
        toAppException(
          StateError('launchUrl returned false'),
          fallbackMessage: '无法打开 GitHub 链接',
        ),
      );
    }
  }
}

class _AppInfoCard extends StatelessWidget {
  static const _appIconAsset = 'assets/PInn.png';

  const _AppInfoCard({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 应用图标
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Image.asset(
                  _appIconAsset,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 应用名称
            const Text(
              'LnnLore',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'PocketInn 是一款基于 Flutter 开发的类SillyTavern AI 聊天应用，支持多种 AI 模型接口配置，提供角色扮演、世界书、预设等核心功能，让您与 AI 角色进行沉浸式对话体验。',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _UpdateLogItem extends StatelessWidget {
  const _UpdateLogItem({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;
  final String date;
  final List<String> changes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                version,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              date,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...changes.map(
          (change) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    change,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 特别版：版本检查卡片（开关、发布仓库配置、手动检查、结果展示）。
class _VersionCheckCard extends StatefulWidget {
  const _VersionCheckCard({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  State<_VersionCheckCard> createState() => _VersionCheckCardState();
}

class _VersionCheckCardState extends State<_VersionCheckCard> {
  bool _enabled = true;
  String _owner = VersionCheckService.defaultOwner;
  String _repo = VersionCheckService.defaultRepo;
  String? _lastCheckedText;
  bool _checking = false;
  String? _resultText;

  // v57：检查更新需要与本地安装版本比较
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
    _load();
  }

  Future<void> _load() async {
    final service = VersionCheckService.instance;
    final enabled = await service.isEnabled();
    final owner = await service.getOwner();
    final repo = await service.getRepo();
    final lastChecked = await service.getLastChecked();
    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = enabled;
      _owner = owner;
      _repo = repo;
      _lastCheckedText = lastChecked == null
          ? null
          : '${lastChecked.year}-${lastChecked.month.toString().padLeft(2, '0')}-'
                '${lastChecked.day.toString().padLeft(2, '0')} '
                '${lastChecked.hour.toString().padLeft(2, '0')}:'
                '${lastChecked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _check() async {
    final service = VersionCheckService.instance;
    setState(() {
      _checking = true;
      _resultText = null;
    });
    try {
      final latestTag = await service.fetchLatestTag();
      if (!mounted) {
        return;
      }
      if (latestTag == null) {
        setState(() {
          _checking = false;
          _resultText = '未获取到远程版本信息（网络问题或仓库无 release）';
        });
        return;
      }
      // v57：默认仓库为自己的发布仓库——比较本地安装版本与最新 tag；
      // 仅当发布仓库配置回上游时走上游锚点比较。
      final packageInfo = await _packageInfoFuture;
      final hasUpdate = (VersionCheckService.defaultOwner == 'xyy1124' &&
              VersionCheckService.defaultRepo == 'LnnLore')
          ? VersionCheckService.isNewerThan(
              latestTag,
              packageInfo.version,
            )
          : VersionCheckService.isUpstreamUpdateAvailable(latestTag);
      await _load(); // 刷新上次检查时间显示
      if (!mounted) {
        return;
      }
      setState(() {
        _checking = false;
        if (!hasUpdate) {
          _resultText = '已是最新版本（最新 $latestTag，当前 '
              '${packageInfo.version}）';
        } else {
          _resultText = '发现新版本：$latestTag（当前 '
              '${packageInfo.version}），可前往 GitHub 查看更新说明并获取新版本';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checking = false;
        _resultText = '检查失败：$error';
      });
    }
  }

  Future<void> _editConfig() async {
    final nameController = TextEditingController(text: _owner);
    final repoController = TextEditingController(text: _repo);
    final service = VersionCheckService.instance;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('发布仓库设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'GitHub 用户名（owner）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: repoController,
                decoration: const InputDecoration(
                  labelText: '仓库名（repo）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '新版本提示将查询 https://api.github.com/repos/{owner}/{repo}/releases/latest',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                nameController.dispose();
                repoController.dispose();
                Navigator.pop(context);
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await service.setOwner(nameController.text.trim());
                await service.setRepo(repoController.text.trim());
                nameController.dispose();
                repoController.dispose();
                if (context.mounted) {
                  Navigator.pop(context);
                }
                await _load();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启动时自动检查更新'),
          subtitle: const Text('发现新版本时自动提示'),
          value: _enabled,
          onChanged: (value) async {
            await VersionCheckService.instance.setEnabled(value);
            if (!mounted) {
              return;
            }
            setState(() {
              _enabled = value;
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          '发布仓库：$_owner/$_repo',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (_lastCheckedText != null)
          Text(
            '上次检查：$_lastCheckedText',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8A8A8A),
            ),
          ),
        if (_resultText != null) ...[
          const SizedBox(height: 8),
          Text(
            _resultText!,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _checking ? null : _check,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_checking ? '检查中…' : '检查更新'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _editConfig,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('发布仓库设置'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LicenseItem extends StatelessWidget {
  const _LicenseItem({
    required this.name,
    required this.license,
    required this.onTap,
  });

  final String name;
  final String license;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: const TextStyle(fontSize: 14)),
            Row(
              children: [
                Text(
                  license,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  const _ContactItem({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLink = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: isLink ? colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
            if (isLink) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const String flutterLicense = '''
Copyright 2014 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following
disclaimer in the documentation and/or other materials provided
with the distribution.
   * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived
from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';

const String dartLicense = '''
Copyright 2012, the Dart project authors. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following
disclaimer in the documentation and/or other materials provided
with the distribution.
   * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived
from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';
