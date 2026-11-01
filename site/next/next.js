// The new home page: the 24 points, each as it is. The page in one of
// the app's themes (themes.json, their colours as the app has them),
// picked here.

(() => {
  'use strict';

  // The points: the card's name, then why it takes BaoCode.
  const points = [
    { icon: 'target', name: 'goal / ask / plan 模式',
      title: '目标和计划，不再被滚屏冲走',
      body: '在终端里，计划和目标说完就往上滚，干到第几步得自己翻回去找。BaoCode 把 `/goal` 的目标和进度固定在输入框上方，plan 的方案单独呈现、看清楚再批准；切换模式只要点一下。' },
    { icon: 'code', name: '想要极速 IDE？',
      title: 'CLI 改完代码，你还得开个编辑器',
      body: 'CLI 只管改，想看看、想补两行，得切到另一个编辑器。BaoCode 把毫秒级打开的编辑器、终端、源代码管理放在对话旁边，改动当场就能看、当场就能接手。' },
    { icon: 'history', name: '原生检查点',
      title: '不是整段回滚，而是按文件挑着退',
      body: '在终端里回退，只能退回某个时间点，之后的全部撤掉。BaoCode 让你对着红绿对照，按文件逐个保留或撤销，好的留下、坏的退掉；检查点不进你的 `.git`。' },
    { icon: 'message-square-text', name: '原生一流 Markdown',
      title: '终端画不出来的，这里原样呈现',
      body: '终端里，表格只能拼成字符框，流程图是一段代码，公式是一串符号。BaoCode 原生渲染表格、代码高亮、数学公式和 Mermaid 图，智能体写的方案和报告，第一眼就能读懂。' },
    { icon: 'plug', name: '任意模型 API 接入',
      title: 'CLI 只认 Anthropic 的接口',
      body: '想让 CLI 用别家的模型，得自己搭转换代理、改环境变量。BaoCode 内置转换代理，OpenAI 兼容的上游填上地址和密钥就能用，Claude Code 的工具、技能、子代理一样不少；密钥存在系统钥匙串里。' },
    { icon: 'activity', name: '后台子代理 / Bash 任务',
      title: '终端一次只能看一处',
      body: '子代理并行、命令在后台跑，可终端里同一时间只能看一处输出。BaoCode 把每个子代理的进度、每个后台任务的输出都摆在眼前，随时展开，哪个卡住了一眼就知道。' },
    { icon: 'list', name: '10 万级消息列表',
      title: '长会话，从头到尾都在',
      body: '终端的滚动缓冲有上限，会话一长，往上翻要么翻不到，要么越翻越卡。BaoCode 的消息列表只绘制看得见的部分，十万条消息照样丝滑，跑了一整天的会话也能一拖到底。' },
    { icon: 'terminal', name: '原生终端',
      title: 'CLI 占着终端，你的命令往哪敲？',
      body: 'CLI 运行时霸占了整个终端，想自己跑个命令，就得再开一个窗口来回切。BaoCode 的终端就开在对话旁和 IDE 里，原生伪终端，TUI 程序、颜色、快捷键都正常。' },
    { icon: 'smartphone', name: '想要移动端？',
      title: '它在等你批准，你却不在电脑前',
      body: 'CLI 停下来等一个“允许”，你就得回到那台电脑前。手机扫码就和桌面配对，审批请求推到手机上，点一下它就接着干；进度和输出随时看。' },
    { icon: 'git-compare', name: 'Git 变更明细',
      title: '长 diff，不再一滚就没',
      body: '在终端里，改动的 diff 混在输出里，长一点就滚出屏幕。BaoCode 里每个文件都是左右红绿对照，逐个审阅；提交图、分支、提交说明也都在同一个窗口里。' },
    { icon: 'layers', name: '多项目工作区',
      title: '告别一排分不清的终端标签',
      body: '几个项目同时跑 CLI，就是一排长得一模一样的终端标签，谁在等你只能挨个点开看。BaoCode 按项目归拢所有对话，谁在跑、谁在等、谁干完了，侧边栏一目了然；两个对话还能并排对照。' },
    { icon: 'palette', name: 'VS Code 全主题兼容',
      title: '不止几套终端配色',
      body: 'CLI 只有几套内置配色，好看与否还取决于你的终端。BaoCode 直接装 VS Code 的配色和图标主题，对话、代码、侧边栏、整个窗口一起换装。' },
    { icon: 'server', name: 'SSH / WSL 一流支持',
      title: '远程开发，不只有一个 SSH 窗口',
      body: '在服务器上用 CLI，你面对的只有一个 SSH 终端。BaoCode 的窗口留在本地，Claude Code、文件、Git、搜索、终端、语言服务器都跑在远程 Linux 或 WSL 里，界面和本地项目完全一样。' },
    { icon: 'inbox', name: '随意队列消息',
      title: '排队的消息，看得见、改得了',
      body: '在终端里，智能体工作时打进去的话排在哪、能不能改，你都看不到。BaoCode 把排队的消息摆在输入框上方，可以改、可以撤回，也可以让它立刻插队。' },
    { icon: 'chrome', name: '全能浏览器插件',
      title: 'DevTools 那一套，它都会',
      body: '不只是点点页面、截个图：BaoCode 通过扩展连上你自己的 Chrome，带着你的登录状态；控制台、网络请求、性能分析、内存、断点调试，智能体都能直接用，问题在哪它亲眼看到。' },
    { icon: 'map', name: '对话地图缩略图',
      title: '再长的对话，也不会迷路',
      body: '在终端里找半小时前的某一步，只能一路往上翻。BaoCode 给对话配了一张缩略图，结构一眼看全，点哪跳哪，拖着就能快速回顾。' },
    { icon: 'bot', name: 'Stash 与 Bot',
      title: '终端外的灵感和伙伴',
      body: '灵感常在你不在终端里的时候来：Stash 用全局快捷键一呼即出，随手记下，回头一键“说清楚”交给智能体实施。Bot 让你捏一个有名字、有性格的智能体，像朋友一样聊天。这些在终端里都没有。' },
    { icon: 'app-window', name: '右键菜单 / 多窗口',
      title: '终端给不了的桌面体验',
      body: '终端里没有右键菜单，所有事都塞在一个窗口里。BaoCode 到处都有贴合场景的右键菜单，IDE 一个文件夹一个窗口，单个对话也能拎出来，放到另一块屏幕上。' },
    { icon: 'image', name: '图片生成',
      title: '终端里看不到的图，这里直接出',
      body: 'CLI 既画不了图，也显示不了图。BaoCode 接上图片模型后，智能体在对话里直接出图，所见即所得，存进项目就能用。' },
    { icon: 'bell', name: '任务通知',
      title: '不用盯着终端，也不用自己写 hook',
      body: '在终端里，要么时不时切回去看它是不是在等你，要么自己写 hook 配通知。BaoCode 开箱就有系统通知、提示音、角标；关掉窗口，它也在菜单栏里继续跑。' },
    { icon: 'puzzle', name: 'MCP / 插件 / 技能 / 规则管理',
      title: '不用再翻配置文件',
      body: '在 CLI 里，插件、MCP、技能、规则、钩子分散在各处的 JSON 和目录里，靠命令和手改维护。BaoCode 把它们集中到一个界面里管理，全局还是只给某个项目用，点一下就切换。' },
    { icon: 'keyboard', name: '多快捷键方案',
      title: '在对话里，也用你的肌肉记忆',
      body: '终端里编辑一段长提示词，只有终端那套有限的按键。BaoCode 内置 VS Code、IntelliJ、Sublime、Atom 键位方案，输入框和编辑器都按你习惯的来。' },
    { icon: 'gauge', name: '约 20 MB / 120 MB 内存 / 2 进程',
      title: '多一个窗口，几乎不多负担',
      body: '给 CLI 配一个完整的图形界面，代价只有：安装包约 20 MB，空闲约 120 MB 内存，2 个进程。原生应用，不带一整个浏览器。' },
    { icon: 'zap', name: 'GPU 渲染，跟满刷新率',
      title: '告别终端里的闪烁和跳动',
      body: '终端界面靠一行行字符重绘，输出一多就闪、就跳。BaoCode 自己绘制每一个像素，直接交给 GPU，帧率跟满你的屏幕，高刷屏上可达 460fps 以上；滚动、动画、打字都跟手。' },
  ];

  const $ = (s) => document.querySelector(s);
  const escape = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const rich = (s) => escape(s).replace(/`([^`]+)`/g, '<code>$1</code>');

  // --- The cards ---------------------------------------------------------------------

  const list = $('.cards');
  points.forEach((point, i) => {
    const card = document.createElement('article');
    card.className = 'card';
    card.innerHTML =
      `<div class="card-head"><svg class="ic" aria-hidden="true"><use href="#ic-${point.icon}"/></svg>` +
      `<span>${rich(point.name)}</span><span class="card-no">${String(i + 1).padStart(2, '0')}</span></div>` +
      `<h2>${rich(point.title)}</h2><p>${rich(point.body)}</p>`;
    list.appendChild(card);
  });

  // --- Themes -------------------------------------------------------------------------

  let themes = [];
  let themeId = null;
  const vars = (c) => ({
    '--bg': c['sideBar.background'] || c['editor.background'],
    '--surface': c['editor.background'],
    '--raised': c['editorWidget.background'] || c['sideBar.background'],
    '--fg': c['foreground'],
    '--fg-strong': c['editor.foreground'] || c['foreground'],
    '--muted': c['descriptionForeground'] || c['foreground'],
    '--border': c['widget.border'] || c['panel.border'] || c['sideBar.border'] || 'rgba(128,128,128,.28)',
    '--accent': c['button.background'] || c['focusBorder'],
    '--accent-fg': c['button.foreground'] || '#fff',
    '--link': c['textLink.foreground'] || c['button.background'],
    '--hover': c['list.hoverBackground'] || 'rgba(128,128,128,.12)',
    '--sel': c['list.activeSelectionBackground'] || c['list.hoverBackground'],
    '--sel-fg': c['list.activeSelectionForeground'] || c['foreground'],
    '--focus': c['focusBorder'] || c['button.background'],
    '--green': c['terminal.ansiGreen'] || '#3fb950',
    '--blue': c['terminal.ansiBlue'] || '#58a6ff',
  });

  const menu = $('.theme-menu');
  const menuButton = $('.theme-button');

  // [id] on the page; [keep] when picked.
  const applyTheme = (id, { keep = false } = {}) => {
    const theme = themes.find((t) => t.id === id);
    if (!theme) return;
    themeId = id;
    const v = vars(theme.colors);
    const root = document.documentElement.style;
    for (const [k, value] of Object.entries(v)) if (value) root.setProperty(k, value);
    root.setProperty('color-scheme', theme.dark ? 'dark' : 'light');
    $('[data-theme-label]').textContent = theme.label;
    for (const li of menu.children) li.setAttribute('aria-selected', String(li.dataset.id === id));
    if (keep) localStorage.setItem('baocode.site.theme', JSON.stringify({ id, vars: v }));
  };

  const openMenu = (open) => {
    menu.hidden = !open;
    menuButton.setAttribute('aria-expanded', String(open));
  };
  menuButton.addEventListener('click', (e) => {
    e.stopPropagation();
    openMenu(menu.hidden);
  });
  document.addEventListener('click', () => openMenu(false));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') openMenu(false);
  });

  const saved = (() => {
    try { return JSON.parse(localStorage.getItem('baocode.site.theme') || 'null'); } catch (_) { return null; }
  })();

  fetch('themes.json')
    .then((r) => r.json())
    .then((data) => {
      themes = data.themes;
      for (const t of themes) {
        const li = document.createElement('li');
        li.setAttribute('role', 'option');
        li.dataset.id = t.id;
        li.style.setProperty('--s-bg', t.colors['editor.background']);
        li.style.setProperty('--s-accent', t.colors['button.background'] || t.colors['focusBorder']);
        li.innerHTML = `<span class="swatch"></span>${escape(t.label)}<svg class="ic"><use href="#ic-check"/></svg>`;
        li.addEventListener('click', () => applyTheme(t.id, { keep: true }));
        menu.appendChild(li);
      }
      const start = saved && themes.some((t) => t.id === saved.id) ? saved.id : data.default;
      applyTheme(start);
    });

})();
