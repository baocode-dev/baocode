/* 1:1 Flutter BaoCode Window Component (Mode 1 IDE + Mode 2 Islands + Live Animations) */
// Narrow screens show pictures of the window instead (.window-shots), so the
// live one is built only once the page is wide enough for it.
(function () {
  const narrow = window.matchMedia("(max-width: 860px)");
  const start = () => { window.baoWindowLive = true; init(); };
  if (!narrow.matches) { start(); return; }
  narrow.addEventListener("change", function wide(e) {
    if (e.matches) return;
    narrow.removeEventListener("change", wide);
    start();
  });

function init() {
  "use strict";
  const mount = document.getElementById("baocodeWindowMount");
  if (!mount) return;
  mount.innerHTML = "<!-- Single Unified BaoCode macOS Window (1:1 Flutter Source Fidelity) -->\n        <div class=\"app-window is-ide\" id=\"desktopWindow\" data-app-theme=\"carbon\">\n          <!-- ==================== MODE 1: IDE + AGENT (Flutter IdeWorkbench + ChatScreen) ==================== -->\n          <div class=\"win-mode win-mode-ide is-active\" data-workspace=\"ide\">\n            <!-- IDE Titlebar (34px #212120) -->\n            <div class=\"app-titlebar\">\n              <div class=\"tb-left\">\n                <span class=\"traffic-lights\" aria-hidden=\"true\">\n                  <i class=\"tl-r\"></i><i class=\"tl-y\"></i><i class=\"tl-g\"></i>\n                </span>\n                <iconify-icon icon=\"codicon:layout-sidebar-left\" width=\"15\" height=\"15\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n              </div>\n\n              <div class=\"tb-center\">\n                <span class=\"tb-nav-arrows\">\n                  <iconify-icon icon=\"codicon:arrow-left\" width=\"14\" height=\"14\"></iconify-icon>\n                  <iconify-icon icon=\"codicon:arrow-right\" width=\"14\" height=\"14\"></iconify-icon>\n                </span>\n                <div class=\"tb-search\">\n                  <iconify-icon icon=\"codicon:search\" width=\"13\" height=\"13\"></iconify-icon>\n                  <span>BaoCode</span>\n                </div>\n              </div>\n\n              <div class=\"tb-right\">\n                <span class=\"tb-icon-group\">\n                  <iconify-icon icon=\"codicon:layout-sidebar-left\" width=\"15\" height=\"15\"></iconify-icon>\n                  <iconify-icon icon=\"codicon:layout-panel\" width=\"15\" height=\"15\"></iconify-icon>\n                  <iconify-icon icon=\"codicon:pin\" width=\"14\" height=\"14\"></iconify-icon>\n                </span>\n                <button class=\"fl-open-ide-btn\" id=\"tbToUsage\" type=\"button\">\n                  <iconify-icon icon=\"codicon:comment-discussion\" width=\"13\" height=\"13\"></iconify-icon>\n                  <span>Show Chat Window</span>\n                </button>\n              </div>\n            </div>\n\n            <!-- IDE Body (ActivityBar + Explorer + Monaco + Flutter ChatScreen) -->\n            <div class=\"ide-body\">\n              <!-- Activity Bar (#212120 + #373633 active square) -->\n              <aside class=\"ide-activity\" aria-hidden=\"true\">\n                <span class=\"act-btn is-active\"><iconify-icon icon=\"codicon:files\" width=\"21\" height=\"21\"></iconify-icon></span>\n                <span class=\"act-btn\"><iconify-icon icon=\"codicon:search\" width=\"21\" height=\"21\"></iconify-icon></span>\n                <span class=\"act-btn\">\n                  <iconify-icon icon=\"codicon:source-control\" width=\"21\" height=\"21\"></iconify-icon>\n                  <span class=\"act-badge\">14</span>\n                </span>\n                <span class=\"act-btn\"><iconify-icon icon=\"codicon:extensions\" width=\"21\" height=\"21\"></iconify-icon></span>\n                <span class=\"act-btn\" style=\"margin-top:auto;\"><iconify-icon icon=\"codicon:settings-gear\" width=\"20\" height=\"20\"></iconify-icon></span>\n              </aside>\n\n              <!-- Explorer Sidebar with real Material Icon Theme SVGs -->\n              <aside class=\"ide-explorer\">\n                <div class=\"pane-cap\">\n                  <span>Explorer</span>\n                  <iconify-icon icon=\"codicon:ellipsis\" width=\"14\" height=\"14\"></iconify-icon>\n                </div>\n                <div class=\"tree-list\">\n                  <div class=\"tree-row\" style=\"font-weight:600;\">\n                    <iconify-icon icon=\"codicon:chevron-down\" width=\"13\" height=\"13\"></iconify-icon>\n                    <span>BaoCode (Workspace)</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-client.svg\" alt=\"\" />\n                    <span>browser</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-views.svg\" alt=\"\" />\n                    <span>chat</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-custom.svg\" alt=\"\" />\n                    <span>customize</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-debug.svg\" alt=\"\" />\n                    <span>debug</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-plugin.svg\" alt=\"\" />\n                    <span>extensions</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-theme.svg\" alt=\"\" />\n                    <span>icons</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-down\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-lib-open.svg\" alt=\"\" />\n                    <span>ide</span>\n                  </div>\n                  <div class=\"tree-row indent-2\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-git.svg\" alt=\"\" />\n                    <span>git</span>\n                  </div>\n                  <div class=\"tree-row indent-2\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-tools.svg\" alt=\"\" />\n                    <span>lsp</span>\n                  </div>\n                  <div class=\"tree-row indent-2\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-scripts.svg\" alt=\"\" />\n                    <span>terminal</span>\n                  </div>\n                  <div class=\"tree-row indent-2\">\n                    <iconify-icon icon=\"codicon:chevron-down\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-base-open.svg\" alt=\"\" />\n                    <span>workbench</span>\n                  </div>\n                  <div class=\"tree-row indent-3\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>editor_worker.dart</span>\n                  </div>\n                  <div class=\"tree-row indent-3\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>file_index.dart</span>\n                  </div>\n                  <div class=\"tree-row indent-3 is-selected\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>file_service.dart</span>\n                    <span class=\"git-m\">M</span>\n                  </div>\n                  <div class=\"tree-row indent-3\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>tunnel_mux.dart</span>\n                    <span class=\"git-a\">A</span>\n                  </div>\n                  <div class=\"tree-row indent-3\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>adb_bridge.dart</span>\n                    <span class=\"git-a\">A</span>\n                  </div>\n                  <div class=\"tree-row indent-3\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>wheel_glide.dart</span>\n                  </div>\n                  <div class=\"tree-row indent-1\">\n                    <iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                    <img class=\"micon\" src=\"/assets/micons/folder-server.svg\" alt=\"\" />\n                    <span>remote</span>\n                  </div>\n                </div>\n                <div class=\"explorer-foot-row\"><iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\"></iconify-icon> Outline</div>\n                <div class=\"explorer-foot-row\"><iconify-icon icon=\"codicon:chevron-right\" width=\"13\" height=\"13\"></iconify-icon> Timeline <span style=\"font-weight:400;color:var(--x-dim, #7e7d78);\">file_service.dart</span></div>\n              </aside>\n\n              <!-- Center: Monaco Editor (#282827) -->\n              <div class=\"ide-editor\">\n                <div class=\"editor-tabs\">\n                  <div class=\"ed-tab is-active\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>file_service.dart</span>\n                    <iconify-icon icon=\"codicon:close\" width=\"13\" height=\"13\" style=\"color:var(--x-icon, #a09f98);\"></iconify-icon>\n                  </div>\n                  <div class=\"ed-tab\">\n                    <img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                    <span>tunnel_mux.dart</span>\n                  </div>\n                  <div class=\"ed-tab\">\n                    <img class=\"micon\" src=\"/assets/micons/readme.svg\" alt=\"\" />\n                    <span>README.md</span>\n                  </div>\n                </div>\n                <div class=\"editor-crumb\">\n                  <span>baocode</span><iconify-icon icon=\"codicon:chevron-right\" width=\"12\" height=\"12\"></iconify-icon>\n                  <span>lib</span><iconify-icon icon=\"codicon:chevron-right\" width=\"12\" height=\"12\"></iconify-icon>\n                  <span>ide</span><iconify-icon icon=\"codicon:chevron-right\" width=\"12\" height=\"12\"></iconify-icon>\n                  <img class=\"micon\" style=\"width:13px;height:13px;\" src=\"/assets/micons/dart.svg\" alt=\"\" />\n                  <strong>file_service.dart</strong><iconify-icon icon=\"codicon:chevron-right\" width=\"12\" height=\"12\"></iconify-icon>\n                  <iconify-icon icon=\"codicon:symbol-interface\" width=\"13\" height=\"13\" style=\"color:#75beff;\"></iconify-icon>\n                  <span style=\"color:var(--x-fg, #e1e0dc);\">IdeHostFiles</span>\n                </div>\n                <div class=\"code-wrap\">\n                  <div class=\"code-body\">\n                    <div class=\"code-line\"><span class=\"ln\">41</span><span>  <span class=\"tok-cm\">/// Copies [from] to [to] over local or remote SSH host.</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">42</span><span>  <span class=\"tok-ty\">Future</span><span class=\"tok-op\">&lt;</span><span class=\"tok-mod\">void</span><span class=\"tok-op\">&gt;</span> <span class=\"tok-fn\">copy</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">from</span><span class=\"tok-op\">,</span> <span class=\"tok-ty\">String</span> <span class=\"tok-var\">to</span><span class=\"tok-op\">);</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">43</span><span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">44</span><span>  <span class=\"tok-cm\">/// Deletes [path] on the target machine for good.</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">45</span><span>  <span class=\"tok-ty\">Future</span><span class=\"tok-op\">&lt;</span><span class=\"tok-mod\">void</span><span class=\"tok-op\">&gt;</span> <span class=\"tok-fn\">delete</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">path</span><span class=\"tok-op\">);</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">46</span><span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">47</span><span>  <span class=\"tok-cm\">/// Writes raw bytes directly across the bidirectional tunnel.</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">48</span><span>  <span class=\"tok-ty\">Future</span><span class=\"tok-op\">&lt;</span><span class=\"tok-mod\">void</span><span class=\"tok-op\">&gt;</span> <span class=\"tok-fn\">writeBytes</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">path</span><span class=\"tok-op\">,</span> <span class=\"tok-ty\">Uint8List</span> <span class=\"tok-var\">bytes</span><span class=\"tok-op\">);</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">49</span><span><span class=\"tok-op\">}</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">50</span><span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">51</span><span><span class=\"tok-cm\">/// A file service on another machine (Linux / macOS / Windows):</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">52</span><span><span class=\"tok-cm\">/// bridges remote Claude Code seamlessly back to your desktop.</span></span></div>\n                    <div class=\"code-line is-active-line\"><span class=\"ln\"><iconify-icon icon=\"codicon:lightbulb\" width=\"13\" height=\"13\" style=\"color:#f4bf4f;\"></iconify-icon>53</span><span><span class=\"tok-kw\">abstract interface class</span> <span class=\"tok-ty\">IdeHostFiles</span> <span class=\"tok-kw\">implements</span> <span class=\"tok-ty\">IdeFileService</span> <span class=\"tok-op\">{</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">54</span><span>  <span class=\"tok-cm\">/// [path]'s bytes, streamed with zero base64 overhead.</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">55</span><span>  <span class=\"tok-ty\">Future</span><span class=\"tok-op\">&lt;</span><span class=\"tok-ty\">Uint8List</span><span class=\"tok-op\">&gt;</span> <span class=\"tok-fn\">readBytes</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">path</span><span class=\"tok-op\">);</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">56</span><span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">57</span><span>  <span class=\"tok-cm\">/// Watches live file changes at 360Hz frame-paced sync.</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">58</span><span>  <span class=\"tok-ty\">Stream</span><span class=\"tok-op\">&lt;</span><span class=\"tok-mod\">void</span><span class=\"tok-op\">&gt;</span> <span class=\"tok-fn\">watchDirectory</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">directory</span><span class=\"tok-op\">);</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">59</span><span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">60</span><span>  <span class=\"tok-cm\">/// Lists project files or delegates search straight to host.</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">61</span><span>  <span class=\"tok-ty\">Future</span><span class=\"tok-op\">&lt;</span><span class=\"tok-ty\">IdeFileListing</span><span class=\"tok-op\">&gt;</span> <span class=\"tok-fn\">listProject</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">root</span><span class=\"tok-op\">, {</span><span class=\"tok-ty\">int</span> <span class=\"tok-var\">limit</span> <span class=\"tok-op\">=</span> <span class=\"tok-num\">5000</span><span class=\"tok-op\">});</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">62</span><span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">63</span><span>  <span class=\"tok-ty\">Stream</span><span class=\"tok-op\">&lt;</span><span class=\"tok-ty\">MatchHit</span><span class=\"tok-op\">&gt;</span> <span class=\"tok-fn\">searchText</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">root</span><span class=\"tok-op\">,</span> <span class=\"tok-ty\">IdeTextQuery</span> <span class=\"tok-var\">query</span><span class=\"tok-op\">);</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">64</span><span><span class=\"tok-op\">}</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">65</span><span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">66</span><span><span class=\"tok-cm\">/// Reads a range without holding up agent output or UI frames.</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">67</span><span><span class=\"tok-kw\">abstract interface class</span> <span class=\"tok-ty\">IdeRangeFiles</span> <span class=\"tok-op\">{</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">68</span><span>  <span class=\"tok-ty\">Future</span><span class=\"tok-op\">&lt;({</span><span class=\"tok-ty\">Uint8List</span> <span class=\"tok-var\">bytes</span><span class=\"tok-op\">,</span> <span class=\"tok-ty\">int</span> <span class=\"tok-var\">size</span><span class=\"tok-op\">})&gt;</span> <span class=\"tok-fn\">readRange</span><span class=\"tok-op\">(</span><span class=\"tok-ty\">String</span> <span class=\"tok-var\">path</span><span class=\"tok-op\">,</span> <span class=\"tok-ty\">int</span> <span class=\"tok-var\">offset</span><span class=\"tok-op\">);</span></span></div>\n                    <div class=\"code-line\"><span class=\"ln\">69</span><span><span class=\"tok-op\">}</span></span></div>\n                  </div>\n                  <div class=\"vs-scrollbar\" aria-hidden=\"true\"><i></i></div>\n                </div>\n              </div>\n\n              <!-- Right: 1:1 Flutter ChatScreen + IdeChatTitle (#282827) -->\n              <div class=\"fl-chat-pane\" id=\"ideChatPane\">\n                <!-- IdeChatTitle (IdeTabStrip: 35px, #212120, active #282827 + #B39364 top border) -->\n                <div class=\"fl-chat-tabs\">\n                  <button class=\"fl-chat-tab\" type=\"button\" data-chat-tab=\"0\">\n                    <iconify-icon icon=\"codicon:check\" width=\"13\" height=\"13\" style=\"color:#9DC08B;\"></iconify-icon>\n                    <span>360Hz frame pacing</span>\n                  </button>\n                  <button class=\"fl-chat-tab is-active\" type=\"button\" data-chat-tab=\"1\">\n                    <canvas class=\"fl-pixel-loader\" width=\"28\" height=\"28\" aria-hidden=\"true\"></canvas>\n                    <span>SSH ADB &amp; Protocol Bridge</span>\n                    <iconify-icon class=\"fl-tab-x\" icon=\"codicon:close\" width=\"13\" height=\"13\"></iconify-icon>\n                  </button>\n                  <div class=\"fl-chat-tab-actions\">\n                    <span class=\"fl-icon-btn\" title=\"New Chat\"><iconify-icon icon=\"codicon:add\" width=\"15\" height=\"15\"></iconify-icon></span>\n                    <span class=\"fl-icon-btn\" title=\"Show Chats\"><iconify-icon icon=\"codicon:history\" width=\"15\" height=\"15\"></iconify-icon></span>\n                  </div>\n                </div>\n\n                <!-- ChatHistoryView (StepHeader + ActivityRow + TurnFooter._LiveStats) -->\n                <div class=\"fl-chat-feed\" id=\"ideChatFeed\">\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">protocol_schema.dart</span><span class=\"fl-add\">+387</span></div>\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Thought 3s</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">tunnel_mux.dart</span><span class=\"fl-add\">+106</span></div>\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Ran <b>2</b> commands · thought 8s</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">adb_bridge.dart</span><span class=\"fl-add\">+518</span><span class=\"fl-del\">-1</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-shimmer\">Running</span></div>\n\n                  <!-- ActivityRow: ThinkingSpark(15, #D97857) + _Musing typewriter -->\n                  <div class=\"fl-activity-row\" data-live-active>\n                    <canvas class=\"fl-spark\" width=\"30\" height=\"30\" aria-hidden=\"true\"></canvas>\n                    <span class=\"fl-musing\" data-musing=\"ide\">Doodling in the margins..</span>\n                  </div>\n\n                  <!-- TurnFooter._LiveStats: RollingText odometer digits -->\n                  <div class=\"fl-live-stats\" data-live-active>\n                    <span class=\"fl-stat\">\n                      <iconify-icon icon=\"lucide:clock\" width=\"12\" height=\"12\"></iconify-icon>\n                      <span class=\"fl-roll\" data-roll=\"ide-time\">18m 03s</span>\n                    </span>\n                    <span class=\"fl-stat\">\n                      <iconify-icon icon=\"lucide:zap\" width=\"12\" height=\"12\"></iconify-icon>\n                      <span class=\"fl-roll\" data-roll=\"ide-speed\">174.60 tok/s</span>\n                    </span>\n                    <span class=\"fl-stat\">\n                      <iconify-icon icon=\"lucide:arrow-down\" width=\"12\" height=\"12\"></iconify-icon>\n                      <span class=\"fl-roll\" data-roll=\"ide-tokens\">100.63k tokens</span>\n                    </span>\n                  </div>\n                </div>\n\n                <!-- ChatScreen._buildDock -->\n                <div class=\"fl-dock\">\n                  <!-- 1. GoalPanel (bubbleFill #393937, border amber 55%, radius 8) -->\n                  <div class=\"fl-goal-panel\" data-goal-panel>\n                    <button class=\"fl-goal-head\" type=\"button\" aria-expanded=\"false\">\n                      <iconify-icon icon=\"lucide:flag\" width=\"13\" height=\"13\" style=\"color:#E5BA7D;flex-shrink:0;\"></iconify-icon>\n                      <span class=\"fl-goal-tag\">Goal</span>\n                      <span class=\"fl-goal-cond\">Implement bidirectional SSH tunnel &amp; custom model protocol translator</span>\n                      <span class=\"fl-goal-state\">\n                        <span class=\"fl-shimmer\" style=\"font-size:11.5px;\">Working</span>\n                        <span class=\"fl-goal-elapsed\" data-goal-elapsed=\"ide\"> · 18m 37s</span>\n                      </span>\n                      <iconify-icon class=\"fl-goal-chev\" icon=\"codicon:chevron-up\" width=\"14\" height=\"14\"></iconify-icon>\n                    </button>\n                    <div class=\"fl-goal-body\">\n                      <p>Implement bidirectional SSH tunnel, zero-copy local file/port forwarding, and USB-C ADB bridge with passing integration tests.</p>\n                      <div class=\"fl-goal-check\"><span>Last check</span> Core tunnel_mux tests green; verifying ADB port reverse over SSH.</div>\n                    </div>\n                  </div>\n\n                  <!-- 2. ContextUsagePanel (PanelCard: #393937, border #4E4D4A, radius 10) -->\n                  <div class=\"fl-panel-card is-open\" id=\"ideContextPanel\">\n                    <div class=\"fl-panel-head\">\n                      <span class=\"fl-panel-title\">Context window</span>\n                      <span class=\"fl-panel-summary\">296.7k / 400.0k (74%)  ·  70.3k until auto-compact</span>\n                      <button class=\"fl-panel-close\" id=\"ideCtxClose\" type=\"button\" aria-label=\"Close context panel\">\n                        <iconify-icon icon=\"codicon:close\" width=\"14\" height=\"14\"></iconify-icon>\n                      </button>\n                    </div>\n                    <div class=\"fl-panel-body\">\n                      <!-- _WindowPainter (8px height, exact UsagePalette.part colors + hatched reserve) -->\n                      <div class=\"fl-ctx-bar\" aria-hidden=\"true\">\n                        <span data-part-bar=\"system\" style=\"width:6.3%;background:#8A79D8;\"></span>\n                        <span data-part-bar=\"memory\" style=\"width:9.8%;background:#BD8128;\"></span>\n                        <span data-part-bar=\"skills\" style=\"width:6.4%;background:#B0679E;\"></span>\n                        <span data-part-bar=\"tools\" style=\"width:16.1%;background:#3F86D8;\"></span>\n                        <span data-part-bar=\"mcp\" style=\"width:4.4%;background:#D2654F;\"></span>\n                        <span data-part-bar=\"messages\" style=\"width:4.1%;background:var(--x-grey, #B0AFA9);\"></span>\n                        <span data-part-bar=\"toolResult\" style=\"width:27.1%;background:#2E9E72;\"></span>\n                        <span class=\"fl-ctx-reserve\"></span>\n                      </div>\n\n                      <!-- _PartCell 2-column grid (Flutter: ((width + 8) / 198).floor() = 2) -->\n                      <div class=\"fl-part-grid\" id=\"idePartGrid\">\n                        <button class=\"fl-part-cell\" type=\"button\" data-part=\"system\">\n                          <i style=\"background:#8A79D8;\"></i><span class=\"fl-pl\">System prompt</span><span class=\"fl-pv\">25.2k</span><span class=\"fl-pp\">9%</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                        </button>\n                        <button class=\"fl-part-cell\" type=\"button\" data-part=\"memory\">\n                          <i style=\"background:#BD8128;\"></i><span class=\"fl-pl\">CLAUDE.md &amp; rules</span><span class=\"fl-pv\">39.1k</span><span class=\"fl-pp\">13%</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                        </button>\n                        <button class=\"fl-part-cell\" type=\"button\" data-part=\"skills\">\n                          <i style=\"background:#B0679E;\"></i><span class=\"fl-pl\">Skills</span><span class=\"fl-pv\">25.6k</span><span class=\"fl-pp\">9%</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                        </button>\n                        <button class=\"fl-part-cell\" type=\"button\" data-part=\"tools\">\n                          <i style=\"background:#3F86D8;\"></i><span class=\"fl-pl\">Built-in tools</span><span class=\"fl-pv\">64.5k</span><span class=\"fl-pp\">22%</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                        </button>\n                        <button class=\"fl-part-cell\" type=\"button\" data-part=\"mcp\">\n                          <i style=\"background:#D2654F;\"></i><span class=\"fl-pl\">MCP</span><span class=\"fl-pv\">17.5k</span><span class=\"fl-pp\">6%</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                        </button>\n                        <button class=\"fl-part-cell\" type=\"button\" data-part=\"messages\">\n                          <i style=\"background:var(--x-grey, #B0AFA9);\"></i><span class=\"fl-pl\">Conversation</span><span class=\"fl-pv\">16.3k</span><span class=\"fl-pp\">5%</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                        </button>\n                        <button class=\"fl-part-cell\" type=\"button\" data-part=\"toolResult\">\n                          <i style=\"background:#2E9E72;\"></i><span class=\"fl-pl\">Tool results</span><span class=\"fl-pv\">108.4k</span><span class=\"fl-pp\">37%</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                        </button>\n                        <div class=\"fl-part-cell is-static\">\n                          <i class=\"is-hollow\"></i><span class=\"fl-pl\">Reserved for compaction</span><span class=\"fl-pv\">33.0k</span><span class=\"fl-pp\"></span><span style=\"width:11px;\"></span>\n                        </div>\n                      </div>\n\n                      <!-- Optional interactive part detail drawer -->\n                      <div class=\"fl-part-drawer\" id=\"idePartDrawer\" hidden></div>\n\n                      <!-- _PromptCacheMeter (#9DC08B read + #E0B97F written + #E8877A uncached) -->\n                      <div class=\"fl-cache-meter\">\n                        <span class=\"fl-cm-lbl\">Prompt cache</span>\n                        <div class=\"fl-cm-bar\" aria-hidden=\"true\">\n                          <span style=\"width:94%;background:#9DC08B;\"></span>\n                          <span style=\"width:4%;background:#E0B97F;\"></span>\n                          <span style=\"width:2%;background:#E8877A;\"></span>\n                        </div>\n                        <span class=\"fl-cm-pct\">97%</span>\n                        <span class=\"fl-cm-all\">98% overall</span>\n                      </div>\n\n                      <!-- _PlanUsage -->\n                      <div class=\"fl-plan-usage\">\n                        <div class=\"fl-plan-head\">\n                          <span>Plan usage</span>\n                          <span class=\"fl-plan-sess\">This session <b>$4.61</b></span>\n                        </div>\n                        <div class=\"fl-limit-row\">\n                          <span class=\"fl-lr-lbl\">5-hour limit</span>\n                          <div class=\"fl-lr-bar\"><i style=\"width:10%;\"></i></div>\n                          <span class=\"fl-lr-pct\">10%</span>\n                          <span class=\"fl-lr-rst\">resets in 1h 56m</span>\n                        </div>\n                        <div class=\"fl-limit-row\">\n                          <span class=\"fl-lr-lbl\">Weekly limit</span>\n                          <div class=\"fl-lr-bar\"><i style=\"width:10%;\"></i></div>\n                          <span class=\"fl-lr-pct\">10%</span>\n                          <span class=\"fl-lr-rst\">resets in 4d 20h</span>\n                        </div>\n                      </div>\n                    </div>\n                  </div>\n\n                  <!-- 3. ActivityStrip (#393937, border #4E4D4A, radius 10, padding 3px 0) -->\n                  <div class=\"fl-activity-strip\" data-change-strip=\"ide\">\n                    <div class=\"fl-strip-row\">\n                      <button class=\"fl-strip-toggle\" type=\"button\" aria-expanded=\"false\">\n                        <iconify-icon class=\"fl-strip-chev\" icon=\"codicon:chevron-right\" width=\"14\" height=\"14\"></iconify-icon>\n                        <span class=\"fl-strip-count\">9 files changed</span>\n                        <span class=\"fl-add\">+3454</span>\n                        <span class=\"fl-del\">-0</span>\n                      </button>\n                      <div class=\"fl-strip-btns\">\n                        <button class=\"fl-panel-btn\" type=\"button\" data-strip-action=\"undo\">Undo all</button>\n                        <button class=\"fl-panel-btn is-primary\" type=\"button\" data-strip-action=\"keep\">Keep all</button>\n                      </div>\n                    </div>\n                    <div class=\"fl-change-tree\" hidden>\n                      <div class=\"fl-ct-row\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>adb_bridge.dart</span><span class=\"fl-add\">+518</span><span class=\"fl-del\">-1</span><span class=\"fl-git-st is-a\">A</span></div>\n                      <div class=\"fl-ct-row\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>protocol_schema.dart</span><span class=\"fl-add\">+387</span><span class=\"fl-git-st is-m\">M</span></div>\n                      <div class=\"fl-ct-row\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>tunnel_mux.dart</span><span class=\"fl-add\">+106</span><span class=\"fl-git-st is-a\">A</span></div>\n                    </div>\n                  </div>\n\n                  <!-- 4. ChatComposer (#393937, border #4E4D4A, radius 12) -->\n                  <div class=\"fl-composer\">\n                    <div class=\"fl-composer-input\" aria-label=\"Chat composer preview\">Stream <span class=\"fl-chip\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>file_service.dart</span><span class=\"fl-chip-muted\">:51-58</span></span> without base64, the trace is <span class=\"fl-chip\"><iconify-icon icon=\"material-symbols:notes-rounded\" width=\"13\" height=\"13\"></iconify-icon><span>Pasted text #1</span><span class=\"fl-chip-muted is-sep\">+42 lines</span></span> and the panel should look like <span class=\"fl-chip is-image\"><img class=\"fl-chip-thumb\" src=\"/assets/mobile-2.webp\" alt=\"\" /><span>Image 1</span></span><i class=\"fl-caret\"></i></div>\n                    <div class=\"fl-composer-bar\">\n                      <div class=\"fl-pickers\">\n                        <span class=\"fl-pill is-emph\"><iconify-icon icon=\"lucide:infinity\" width=\"12\" height=\"12\"></iconify-icon> Agent <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                        <span class=\"fl-pill is-caution\"><iconify-icon icon=\"codicon:shield\" width=\"12\" height=\"12\"></iconify-icon> Full access <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                        <span class=\"fl-pill\"><iconify-icon icon=\"codicon:sparkle\" width=\"12\" height=\"12\"></iconify-icon> Default · 400K · High <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                      </div>\n                      <div class=\"fl-composer-actions\">\n                        <span class=\"fl-tool-btn\" title=\"Enhance prompt\"><iconify-icon icon=\"codicon:sparkle\" width=\"14\" height=\"14\"></iconify-icon></span>\n                        <button class=\"fl-tool-btn fl-ctx-ring-btn is-active\" id=\"ideCtxRingBtn\" type=\"button\" title=\"Context window (74%)\">\n                          <svg viewBox=\"0 0 16 16\" width=\"13\" height=\"13\" aria-hidden=\"true\">\n                            <circle cx=\"8\" cy=\"8\" r=\"6\" fill=\"none\" style=\"stroke:var(--x-dim, #7E7D78)\" stroke-width=\"2\"></circle>\n                            <circle cx=\"8\" cy=\"8\" r=\"6\" fill=\"none\" stroke=\"#A09F98\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-dasharray=\"27.9 37.7\" transform=\"rotate(-90 8 8)\"></circle>\n                          </svg>\n                        </button>\n                        <button class=\"fl-send-btn is-streaming\" type=\"button\" data-live-toggle title=\"Pause / Resume live demo\">\n                          <i></i>\n                        </button>\n                      </div>\n                    </div>\n                  </div>\n                </div>\n              </div>\n            </div>\n\n            <!-- IDE Bottom Status Bar (24px #212120 — ONLY in IDE mode) -->\n            <div class=\"app-statusbar\">\n              <div class=\"sb-group\">\n                <span><iconify-icon icon=\"codicon:git-branch\" width=\"12\" height=\"12\" style=\"vertical-align:-2px;\"></iconify-icon> main</span>\n                <span><iconify-icon icon=\"codicon:error\" width=\"12\" height=\"12\" style=\"vertical-align:-2px;\"></iconify-icon> 0 &nbsp;<iconify-icon icon=\"codicon:warning\" width=\"12\" height=\"12\" style=\"vertical-align:-2px;\"></iconify-icon> 0</span>\n                <span>{} dart</span>\n              </div>\n              <div class=\"sb-group\">\n                <span>Ln 53, Col 66</span>\n                <span>Spaces: 2</span>\n                <span>UTF-8</span>\n                <span>LF</span>\n                <span>Dart</span>\n                <iconify-icon icon=\"codicon:bell\" width=\"12\" height=\"12\" style=\"vertical-align:-2px;\"></iconify-icon>\n              </div>\n            </div>\n          </div>\n\n          <!-- ==================== MODE 2: ISLANDS CHAT + USAGE (Flutter Islands + ConversationUsageView) ==================== -->\n          <div class=\"win-mode win-mode-usage\" data-workspace=\"usage\">\n            <!-- Col 1: Sidebar directly on #212120 window canvas (no card border, matching sidebar.dart) -->\n            <aside class=\"fl-sidebar\">\n              <div class=\"fl-sb-top\">\n                <span class=\"traffic-lights\" aria-hidden=\"true\">\n                  <i class=\"tl-r\"></i><i class=\"tl-y\"></i><i class=\"tl-g\"></i>\n                </span>\n                <span class=\"fl-icon-btn\" style=\"margin-left:auto;\"><iconify-icon icon=\"codicon:layout-sidebar-left\" width=\"15\" height=\"15\"></iconify-icon></span>\n              </div>\n\n              <div class=\"fl-sb-new-wrap\">\n                <div class=\"fl-new-chat-btn\">\n                  <iconify-icon icon=\"codicon:add\" width=\"15\" height=\"15\"></iconify-icon>\n                  <span>New Chat</span>\n                </div>\n              </div>\n\n              <div class=\"fl-sb-nav\">\n                <div class=\"fl-nav-row\"><iconify-icon icon=\"codicon:folder-opened\" width=\"14\" height=\"14\"></iconify-icon><span>Open Project</span></div>\n                <div class=\"fl-nav-row\"><iconify-icon icon=\"codicon:search\" width=\"14\" height=\"14\"></iconify-icon><span>Search</span></div>\n                <div class=\"fl-nav-row\"><iconify-icon icon=\"codicon:plug\" width=\"14\" height=\"14\"></iconify-icon><span>Customize</span></div>\n                <div class=\"fl-nav-row\"><iconify-icon icon=\"codicon:note\" width=\"14\" height=\"14\"></iconify-icon><span>Stash</span></div>\n              </div>\n\n              <div class=\"fl-sb-group-bar\">\n                <span>All <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                <span>By project <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n              </div>\n\n              <div class=\"fl-sb-list\">\n                <div class=\"fl-host-group\">\n                  <div class=\"fl-host-row\">\n                    <iconify-icon icon=\"codicon:chevron-down\" width=\"12\" height=\"12\"></iconify-icon>\n                    <svg class=\"finder-icon\" viewBox=\"0 0 24 24\" width=\"14\" height=\"14\" aria-hidden=\"true\"><defs><linearGradient id=\"fdLSb\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#4fb8ff\"/><stop offset=\"1\" stop-color=\"#1477f0\"/></linearGradient><linearGradient id=\"fdRSb\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#f4f9ff\"/><stop offset=\"1\" stop-color=\"#cfe3f8\"/></linearGradient><clipPath id=\"fdCSb\"><rect x=\"1\" y=\"1\" width=\"22\" height=\"22\" rx=\"5.2\"/></clipPath></defs><g clip-path=\"url(#fdCSb)\"><rect width=\"24\" height=\"24\" fill=\"url(#fdRSb)\"/><path d=\"M0 0H13.2C12.7 3.6 12.1 7.6 11.5 11.3L9.7 12.7L11.6 13.4C11.2 16.6 11.5 20.2 12.2 24H0Z\" fill=\"url(#fdLSb)\"/><path d=\"M7.4 7.3V10.1M16.6 7.3V10.1\" stroke=\"#16304d\" stroke-width=\"1.6\" stroke-linecap=\"round\"/><path d=\"M5.4 15.4C8.4 18.6 15.6 18.6 18.6 15.4\" fill=\"none\" stroke=\"#16304d\" stroke-width=\"1.5\" stroke-linecap=\"round\"/></g></svg>\n                    <span>mac-studio</span>\n                    <span class=\"fl-ssh-badge\">SSH</span>\n                  </div>\n                  <div class=\"fl-thread-row\"><span>iOS TestFlight build</span><em>3h</em></div>\n                </div>\n\n                <div class=\"fl-host-group\">\n                  <div class=\"fl-host-row\">\n                    <iconify-icon icon=\"codicon:chevron-down\" width=\"12\" height=\"12\"></iconify-icon>\n                    <iconify-icon icon=\"logos:linux-tux\" width=\"13\" height=\"14\"></iconify-icon>\n                    <span>prod-gpu-01</span>\n                    <span class=\"fl-ssh-badge\">SSH</span>\n                  </div>\n                  <div class=\"fl-thread-row\"><span>Migrate relay &amp; Caddy</span><em>2d</em></div>\n                  <div class=\"fl-thread-row\"><span>USB-C Android deploy</span><em>5h</em></div>\n                </div>\n\n                <div class=\"fl-host-group\">\n                  <div class=\"fl-host-row\">\n                    <iconify-icon icon=\"codicon:chevron-down\" width=\"12\" height=\"12\"></iconify-icon>\n                    <iconify-icon icon=\"fa6-brands:windows\" width=\"12\" height=\"12\" style=\"color:#00a4ef;\"></iconify-icon>\n                    <span>win-workstation</span>\n                    <span class=\"fl-ssh-badge\">SSH</span>\n                  </div>\n                  <div class=\"fl-thread-row\"><span>bao-bash.exe benchmark</span><em>1d</em></div>\n                </div>\n\n                <div class=\"fl-host-group\">\n                  <div class=\"fl-host-row is-bright\">\n                    <iconify-icon icon=\"codicon:chevron-down\" width=\"12\" height=\"12\"></iconify-icon>\n                    <iconify-icon icon=\"codicon:folder\" width=\"13\" height=\"13\" style=\"color:#E5BA7D;\"></iconify-icon>\n                    <span>BaoCode</span>\n                    <em class=\"fl-proj-cnt\">4</em>\n                  </div>\n                  <div class=\"fl-thread-row is-active\">\n                    <canvas class=\"fl-pixel-loader\" width=\"26\" height=\"26\" aria-hidden=\"true\"></canvas>\n                    <span>Multi-protocol adapter</span>\n                    <b class=\"fl-add\">+2911</b>\n                  </div>\n                  <div class=\"fl-thread-row\"><span>Model pricing rules</span><em>1h</em></div>\n                  <div class=\"fl-thread-row\"><span>360Hz wheel glide</span><em>5h</em></div>\n                  <div class=\"fl-thread-row\"><span>Browser 1ms profiler</span><em>2d</em></div>\n                </div>\n              </div>\n\n              <div class=\"fl-sb-foot\">\n                <span><iconify-icon icon=\"codicon:eye-closed\" width=\"13\" height=\"13\"></iconify-icon> Hide archived</span>\n                <iconify-icon icon=\"codicon:settings-gear\" width=\"14\" height=\"14\"></iconify-icon>\n              </div>\n            </aside>\n\n            <!-- Col 2: Center Conversation Island (30px title row + Island card + 28px foot row) -->\n            <div class=\"fl-island-col\">\n              <div class=\"fl-island-top\">\n                <span class=\"fl-icon-btn\" title=\"Pin Window\"><iconify-icon icon=\"codicon:pin\" width=\"14\" height=\"14\"></iconify-icon></span>\n                <button class=\"fl-open-ide-btn is-split\" id=\"tbToIde\" type=\"button\">\n                  <span class=\"fl-oib-main\">\n                    <iconify-icon icon=\"codicon:layout-sidebar-left\" width=\"13\" height=\"13\"></iconify-icon>\n                    <span>Fast Ide</span>\n                  </span>\n                  <span class=\"fl-oib-sep\"></span>\n                  <span class=\"fl-oib-drop\"><iconify-icon icon=\"codicon:chevron-down\" width=\"12\" height=\"12\"></iconify-icon></span>\n                </button>\n              </div>\n\n              <div class=\"fl-island-card\">\n                <div class=\"fl-card-header\">\n                  <span class=\"fl-card-title\">Multi-protocol adapter</span>\n                  <div class=\"fl-card-tools\">\n                    <span class=\"fl-icon-btn\"><iconify-icon icon=\"codicon:terminal\" width=\"14\" height=\"14\"></iconify-icon></span>\n                    <span class=\"fl-icon-btn is-on\"><iconify-icon icon=\"codicon:layout-sidebar-right\" width=\"14\" height=\"14\"></iconify-icon></span>\n                  </div>\n                </div>\n\n                <div class=\"fl-chat-feed\">\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Searched <b>3</b> patterns, read <b>9</b> files · thought 32s</span></div>\n                  <div class=\"fl-prose\">Three upstreams disagree on tool calls: Anthropic sends tool_use blocks, Responses sends function_call items, Gemini sends functionCall parts.</div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">message_types.dart</span><span class=\"fl-add\">+96</span></div>\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Ran <b>2</b> commands · thought 6s</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">gemini_parts.dart</span><span class=\"fl-add\">+211</span></div>\n                  <div class=\"fl-prose\">Mapping every upstream onto one schema first: Claude Messages stays the source of truth, everything else adapts to it.</div>\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Read <b>6</b> files · thought 21s</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">upstream_registry.dart</span><span class=\"fl-add\">+142</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">tool_schema_bridge.dart</span><span class=\"fl-add\">+268</span></div>\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Searched <b>4</b> patterns · thought 9s</span></div>\n                  <div class=\"fl-prose\">Responses streams reasoning items on their own, so the decoder holds them until the matching output_text arrives.</div>\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Searched <b>2</b> patterns, ran <b>5</b> commands · thought 44s</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">openai_responses.dart</span><span class=\"fl-add\">+764</span></div>\n                  <div class=\"fl-step is-muted\"><span class=\"fl-obj\">Ran <b>4</b> commands · thought 14s</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">codex_service.dart</span><span class=\"fl-add\">+13</span></div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">pricing_schedule.dart</span><span class=\"fl-add\">+914</span></div>\n                  <div class=\"fl-prose\">\n                    Now wiring the core translator (Claude Messages ⇄ OpenAI / Gemini), preserving cache breakpoints, tool schemas, and exact peak/holiday pricing telemetry.\n                  </div>\n                  <div class=\"fl-step\"><span class=\"fl-verb\">Edited</span><span class=\"fl-obj\">stream_decoder.dart</span><span class=\"fl-add\">+544</span></div>\n\n                  <div class=\"fl-activity-row\" data-live-active>\n                    <canvas class=\"fl-spark\" width=\"30\" height=\"30\" aria-hidden=\"true\"></canvas>\n                    <span class=\"fl-musing\" data-musing=\"usage\">Cogitating..</span>\n                  </div>\n\n                  <div class=\"fl-live-stats\" data-live-active>\n                    <span class=\"fl-stat\">\n                      <iconify-icon icon=\"lucide:clock\" width=\"12\" height=\"12\"></iconify-icon>\n                      <span class=\"fl-roll\" data-roll=\"usage-time\">17m 16s</span>\n                    </span>\n                    <span class=\"fl-stat\">\n                      <iconify-icon icon=\"lucide:zap\" width=\"12\" height=\"12\"></iconify-icon>\n                      <span class=\"fl-roll\" data-roll=\"usage-speed\">169.50 tok/s</span>\n                    </span>\n                    <span class=\"fl-stat\">\n                      <iconify-icon icon=\"lucide:arrow-down\" width=\"12\" height=\"12\"></iconify-icon>\n                      <span class=\"fl-roll\" data-roll=\"usage-tokens\">93.63k tokens</span>\n                    </span>\n                  </div>\n                </div>\n\n                <div class=\"fl-dock\">\n                  <div class=\"fl-goal-panel\" data-goal-panel>\n                    <button class=\"fl-goal-head\" type=\"button\" aria-expanded=\"false\">\n                      <iconify-icon icon=\"lucide:flag\" width=\"13\" height=\"13\" style=\"color:#E5BA7D;flex-shrink:0;\"></iconify-icon>\n                      <span class=\"fl-goal-tag\">Goal</span>\n                      <span class=\"fl-goal-cond\">Support OpenAI Responses, Codex &amp; Gemini without touching config</span>\n                      <span class=\"fl-goal-state\">\n                        <span class=\"fl-shimmer\" style=\"font-size:11.5px;\">Working</span>\n                        <span class=\"fl-goal-elapsed\" data-goal-elapsed=\"usage\"> · 17m 51s</span>\n                      </span>\n                      <iconify-icon class=\"fl-goal-chev\" icon=\"codicon:chevron-up\" width=\"14\" height=\"14\"></iconify-icon>\n                    </button>\n                    <div class=\"fl-goal-body\">\n                      <p>Translate Claude Messages ⇄ OpenAI Responses / Codex / Gemini with zero edits to ~/.claude and exact peak/holiday pricing.</p>\n                      <div class=\"fl-goal-check\"><span>Last check</span> Prompt cache hit rate verified at 98.3% across 219 requests.</div>\n                    </div>\n                  </div>\n\n                  <div class=\"fl-activity-strip\" data-change-strip=\"usage\">\n                    <div class=\"fl-strip-row\">\n                      <button class=\"fl-strip-toggle\" type=\"button\" aria-expanded=\"false\">\n                        <iconify-icon class=\"fl-strip-chev\" icon=\"codicon:chevron-right\" width=\"14\" height=\"14\"></iconify-icon>\n                        <span class=\"fl-strip-count\">8 files changed</span>\n                        <span class=\"fl-add\">+2911</span>\n                        <span class=\"fl-del\">-0</span>\n                      </button>\n                      <div class=\"fl-strip-btns\">\n                        <button class=\"fl-panel-btn\" type=\"button\" data-strip-action=\"undo\">Undo all</button>\n                        <button class=\"fl-panel-btn is-primary\" type=\"button\" data-strip-action=\"keep\">Keep all</button>\n                      </div>\n                    </div>\n                    <div class=\"fl-change-tree\" hidden>\n                      <div class=\"fl-ct-row\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>pricing_schedule.dart</span><span class=\"fl-add\">+914</span><span class=\"fl-git-st is-a\">A</span></div>\n                      <div class=\"fl-ct-row\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>openai_responses.dart</span><span class=\"fl-add\">+764</span><span class=\"fl-git-st is-m\">M</span></div>\n                      <div class=\"fl-ct-row\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>stream_decoder.dart</span><span class=\"fl-add\">+544</span><span class=\"fl-git-st is-a\">A</span></div>\n                    </div>\n                  </div>\n\n                  <!-- In Islands mode, ContextMeter sits in the 28px foot below the card (_meterInFoot) -->\n                  <div class=\"fl-composer\">\n                    <div class=\"fl-composer-input\" aria-label=\"Islands composer preview\">Map <span class=\"fl-chip\"><img class=\"micon\" src=\"/assets/micons/dart.svg\" alt=\"\" /><span>codex_service.dart</span><span class=\"fl-chip-muted\">:120-148</span></span> onto the adapter, the failing request is <span class=\"fl-chip\"><iconify-icon icon=\"material-symbols:notes-rounded\" width=\"13\" height=\"13\"></iconify-icon><span>Pasted text #1</span><span class=\"fl-chip-muted is-sep\">+86 lines</span></span> and pricing should render like <span class=\"fl-chip is-image\"><img class=\"fl-chip-thumb\" src=\"/assets/mobile-4.webp\" alt=\"\" /><span>Image 1</span></span><i class=\"fl-caret\"></i></div>\n                    <div class=\"fl-composer-bar\">\n                      <div class=\"fl-pickers\">\n                        <span class=\"fl-pill is-emph\"><iconify-icon icon=\"lucide:infinity\" width=\"12\" height=\"12\"></iconify-icon> Agent <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                        <span class=\"fl-pill is-caution\"><iconify-icon icon=\"codicon:shield\" width=\"12\" height=\"12\"></iconify-icon> Full access <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                        <span class=\"fl-pill\"><iconify-icon icon=\"codicon:sparkle\" width=\"12\" height=\"12\"></iconify-icon> Default · 400K · High <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                      </div>\n                      <div class=\"fl-composer-actions\">\n                        <span class=\"fl-tool-btn\" title=\"Enhance prompt\"><iconify-icon icon=\"codicon:sparkle\" width=\"14\" height=\"14\"></iconify-icon></span>\n                        <button class=\"fl-send-btn is-streaming\" type=\"button\" data-live-toggle title=\"Pause / Resume live demo\">\n                          <i></i>\n                        </button>\n                      </div>\n                    </div>\n                  </div>\n                </div>\n              </div>\n\n              <!-- 28px Islands.belowHeight foot under the conversation card -->\n              <div class=\"fl-island-foot\">\n                <span class=\"fl-foot-branch\">\n                  <iconify-icon icon=\"codicon:git-branch\" width=\"12\" height=\"12\"></iconify-icon>\n                  <span>main*</span>\n                  <iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon>\n                </span>\n                <span class=\"fl-foot-meter\">\n                  <svg viewBox=\"0 0 16 16\" width=\"13\" height=\"13\" aria-hidden=\"true\">\n                    <circle cx=\"8\" cy=\"8\" r=\"6\" fill=\"none\" style=\"stroke:var(--x-dim, #7E7D78)\" stroke-width=\"2\"></circle>\n                    <circle cx=\"8\" cy=\"8\" r=\"6\" fill=\"none\" stroke=\"#A09F98\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-dasharray=\"26.6 37.7\" transform=\"rotate(-90 8 8)\"></circle>\n                  </svg>\n                  <span>282K / 400K</span>\n                </span>\n              </div>\n            </div>\n\n            <!-- Col 3: Right SidePanel IslandTabbedCard (browser-like IslandTabs + ConversationUsageView) -->\n            <div class=\"fl-sidepanel-col\">\n              <div class=\"fl-island-tabs\">\n                <span class=\"fl-itab\"><iconify-icon icon=\"codicon:files\" width=\"13\" height=\"13\"></iconify-icon><span>Files</span></span>\n                <i class=\"fl-itab-sep\"></i>\n                <span class=\"fl-itab\"><iconify-icon icon=\"codicon:source-control\" width=\"13\" height=\"13\"></iconify-icon><span>Changes</span><b class=\"fl-itab-badge\">13</b></span>\n                <i class=\"fl-itab-sep\"></i>\n                <span class=\"fl-itab\"><iconify-icon icon=\"codicon:terminal\" width=\"13\" height=\"13\"></iconify-icon><span>Terminal</span></span>\n                <span class=\"fl-itab is-active\"><iconify-icon icon=\"lucide:pie-chart\" width=\"12\" height=\"12\"></iconify-icon><span>Usage</span></span>\n                <div class=\"fl-sidepanel-actions\">\n                  <span class=\"fl-icon-btn\"><iconify-icon icon=\"codicon:layout\" width=\"14\" height=\"14\"></iconify-icon></span>\n                  <span class=\"fl-icon-btn\"><iconify-icon icon=\"codicon:close\" width=\"14\" height=\"14\"></iconify-icon></span>\n                </div>\n              </div>\n\n              <div class=\"fl-island-card fl-usage-panel\">\n                <!-- UsageFilterBar (26px rounded-13px pills, exact usage_filters.dart) -->\n                <div class=\"fl-usage-filters\">\n                  <span class=\"fl-u-chip\"><iconify-icon icon=\"codicon:type-hierarchy\" width=\"12\" height=\"12\"></iconify-icon><span>Kind: All</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                  <span class=\"fl-u-chip\"><iconify-icon icon=\"codicon:hubot\" width=\"12\" height=\"12\"></iconify-icon><span>Agent: All</span><iconify-icon icon=\"codicon:chevron-down\" width=\"11\" height=\"11\"></iconify-icon></span>\n                  <span class=\"fl-u-chip\"><iconify-icon icon=\"codicon:error\" width=\"12\" height=\"12\"></iconify-icon><span>Failed only</span></span>\n                  <span class=\"fl-icon-btn\" style=\"margin-left:auto;\"><iconify-icon icon=\"codicon:refresh\" width=\"14\" height=\"14\"></iconify-icon></span>\n                </div>\n\n                <!-- UsageOverview: UsageStatGrid of UsageStatTile (#2E2E2D, radius 12, no border) -->\n                <div class=\"fl-stat-grid\">\n                  <div class=\"fl-stat-tile\">\n                    <div class=\"fl-st-top\"><iconify-icon icon=\"codicon:symbol-numeric\" width=\"12\" height=\"12\"></iconify-icon><span>Tokens</span></div>\n                    <div class=\"fl-st-mid\">\n                      <span class=\"fl-st-val\">36.4M</span>\n                      <svg class=\"fl-sparkline\" viewBox=\"0 0 60 26\">\n                        <defs><linearGradient id=\"flSp\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0%\" style=\"stop-color:var(--x-spark, #EDC994)\" stop-opacity=\"0.28\"/><stop offset=\"100%\" style=\"stop-color:var(--x-spark, #EDC994)\" stop-opacity=\"0\"/></linearGradient></defs>\n                        <polygon fill=\"url(#flSp)\" points=\"1,25 1,21 15,19 27,15 37,17 47,4 59,18 59,25\" />\n                        <polyline fill=\"none\" style=\"stroke:var(--x-spark, #EDC994)\" stroke-width=\"1.5\" stroke-linejoin=\"round\" points=\"1,21 15,19 27,15 37,17 47,4 59,18\" />\n                        <circle cx=\"59\" cy=\"18\" r=\"2\" style=\"fill:var(--x-spark, #EDC994)\" />\n                      </svg>\n                    </div>\n                    <span class=\"fl-st-sub\">36.3M in · 143K out</span>\n                  </div>\n\n                  <div class=\"fl-stat-tile\">\n                    <div class=\"fl-st-top\"><iconify-icon icon=\"codicon:credit-card\" width=\"12\" height=\"12\"></iconify-icon><span>Cost</span></div>\n                    <div class=\"fl-st-mid\">\n                      <span class=\"fl-st-val\">$15.03</span>\n                      <svg class=\"fl-sparkline\" viewBox=\"0 0 60 26\">\n                        <polygon fill=\"url(#flSp)\" points=\"1,25 1,22 17,18 31,16 45,5 59,17 59,25\" />\n                        <polyline fill=\"none\" style=\"stroke:var(--x-spark, #EDC994)\" stroke-width=\"1.5\" stroke-linejoin=\"round\" points=\"1,22 17,18 31,16 45,5 59,17\" />\n                        <circle cx=\"59\" cy=\"17\" r=\"2\" style=\"fill:var(--x-spark, #EDC994)\" />\n                      </svg>\n                    </div>\n                    <span class=\"fl-st-sub\">At configured rates</span>\n                  </div>\n\n                  <div class=\"fl-stat-tile\">\n                    <div class=\"fl-st-top\"><iconify-icon icon=\"codicon:pulse\" width=\"12\" height=\"12\"></iconify-icon><span>Calls</span></div>\n                    <div class=\"fl-st-mid\">\n                      <span class=\"fl-st-val\">219</span>\n                      <svg class=\"fl-sparkline\" viewBox=\"0 0 60 26\">\n                        <polygon fill=\"url(#flSp)\" points=\"1,25 1,19 13,13 27,17 41,6 59,13 59,25\" />\n                        <polyline fill=\"none\" style=\"stroke:var(--x-spark, #EDC994)\" stroke-width=\"1.5\" stroke-linejoin=\"round\" points=\"1,19 13,13 27,17 41,6 59,13\" />\n                        <circle cx=\"59\" cy=\"13\" r=\"2\" style=\"fill:var(--x-spark, #EDC994)\" />\n                      </svg>\n                    </div>\n                    <span class=\"fl-st-sub\">228 tool calls asked</span>\n                  </div>\n\n                  <div class=\"fl-stat-tile\">\n                    <div class=\"fl-st-top\"><iconify-icon icon=\"codicon:database\" width=\"12\" height=\"12\"></iconify-icon><span>Cache hit rate</span></div>\n                    <div class=\"fl-st-mid\">\n                      <span class=\"fl-st-val\">98.3%</span>\n                      <svg class=\"fl-sparkline\" viewBox=\"0 0 60 26\">\n                        <polygon fill=\"url(#flSp)\" points=\"1,25 1,6 15,5 31,4 47,4 59,4 59,25\" />\n                        <polyline fill=\"none\" style=\"stroke:var(--x-spark, #EDC994)\" stroke-width=\"1.5\" stroke-linejoin=\"round\" points=\"1,6 15,5 31,4 47,4 59,4\" />\n                        <circle cx=\"59\" cy=\"4\" r=\"2\" style=\"fill:var(--x-spark, #EDC994)\" />\n                      </svg>\n                    </div>\n                    <span class=\"fl-st-sub\">$135.39 saved · 35.6M</span>\n                  </div>\n\n                  <div class=\"fl-stat-tile\">\n                    <div class=\"fl-st-top\"><iconify-icon icon=\"lucide:zap\" width=\"12\" height=\"12\"></iconify-icon><span>Time to first token</span></div>\n                    <div class=\"fl-st-mid\">\n                      <span class=\"fl-st-val\">2.4s</span>\n                      <svg class=\"fl-sparkline\" viewBox=\"0 0 60 26\">\n                        <polygon fill=\"url(#flSp)\" points=\"1,25 1,16 15,12 29,13 43,8 59,11 59,25\" />\n                        <polyline fill=\"none\" style=\"stroke:var(--x-spark, #EDC994)\" stroke-width=\"1.5\" stroke-linejoin=\"round\" points=\"1,16 15,12 29,13 43,8 59,11\" />\n                        <circle cx=\"59\" cy=\"11\" r=\"2\" style=\"fill:var(--x-spark, #EDC994)\" />\n                      </svg>\n                    </div>\n                    <span class=\"fl-st-sub\">6.6s per call on avg</span>\n                  </div>\n\n                  <div class=\"fl-stat-tile\">\n                    <div class=\"fl-st-top\"><iconify-icon icon=\"codicon:flame\" width=\"12\" height=\"12\"></iconify-icon><span>Output speed</span></div>\n                    <div class=\"fl-st-mid\">\n                      <span class=\"fl-st-val\">224</span>\n                      <svg class=\"fl-sparkline\" viewBox=\"0 0 60 26\">\n                        <polygon fill=\"url(#flSp)\" points=\"1,25 1,14 17,9 33,11 47,6 59,10 59,25\" />\n                        <polyline fill=\"none\" style=\"stroke:var(--x-spark, #EDC994)\" stroke-width=\"1.5\" stroke-linejoin=\"round\" points=\"1,14 17,9 33,11 47,6 59,10\" />\n                        <circle cx=\"59\" cy=\"10\" r=\"2\" style=\"fill:var(--x-spark, #EDC994)\" />\n                      </svg>\n                    </div>\n                    <span class=\"fl-st-sub\">tok/s · 143K output</span>\n                  </div>\n                </div>\n\n                <!-- UsageContextSection (UsageCard #2E2E2D, radius 12, exact UsagePalette._dark) -->\n                <div class=\"fl-usage-growth\">\n                  <div class=\"fl-ug-head\">\n                    <div class=\"fl-ug-title\">Context growth</div>\n                    <div class=\"fl-ug-sub\">282K now  ·  peak 365K  ·  219 reqs  ·  Cost $15.03</div>\n                  </div>\n                  <div class=\"fl-ug-legend\">\n                    <span><i style=\"background:#2E9E72;\"></i>Cache read</span>\n                    <span><i style=\"background:#3F86D8;\"></i>Input</span>\n                    <span><i style=\"background:#B0679E;\"></i>Cache write</span>\n                    <span><i style=\"background:#BD8128;\"></i>Output</span>\n                  </div>\n                  <svg class=\"growth-svg\" id=\"heroGrowthSvg\" viewBox=\"0 0 440 176\" preserveAspectRatio=\"xMidYMid meet\" aria-label=\"Context growth chart\"></svg>\n                  <div class=\"fl-ug-divider\"></div>\n                  <div class=\"fl-call-strip\">\n                    <span class=\"fl-call-nav\">\n                      <button class=\"fl-step-btn\" id=\"usagePrevReq\" type=\"button\" aria-label=\"Previous request\"><iconify-icon icon=\"codicon:chevron-left\" width=\"12\" height=\"12\"></iconify-icon></button>\n                      <strong id=\"usageReqNum\">#219/219</strong>\n                      <button class=\"fl-step-btn\" id=\"usageNextReq\" type=\"button\" aria-label=\"Next request\"><iconify-icon icon=\"codicon:chevron-right\" width=\"12\" height=\"12\"></iconify-icon></button>\n                    </span>\n                    <span class=\"fl-call-meta\" id=\"usageReqMeta\">20:11  ·  claude-opus-5-5  ·  $0.205  ·  100% cache</span>\n                    <span class=\"fl-call-tot\"><strong id=\"usageReqPrompt\">282K</strong> <em id=\"usageReqDelta\">+547</em></span>\n                  </div>\n                  <div class=\"fl-ctx-bar\" id=\"usageMakeupBar\" style=\"height:6px;\">\n                    <span style=\"width:1.8%;background:#BD8128;\"></span>\n                    <span style=\"width:1.2%;background:#B0679E;\"></span>\n                    <span style=\"width:0.5%;background:#D2654F;\"></span>\n                    <span style=\"width:12.6%;background:var(--x-grey, #B0AFA9);\"></span>\n                    <span style=\"width:83.9%;background:#2E9E72;\"></span>\n                  </div>\n                  <div class=\"fl-ub-grid\">\n                    <div class=\"fl-ub-row\"><i style=\"background:#BD8128;\"></i><span>CLAUDE.md &amp; rules</span><b>4,994</b><em>2%</em></div>\n                    <div class=\"fl-ub-row\"><i style=\"background:#B0679E;\"></i><span>Skills</span><b>3,274</b><em>1%</em></div>\n                    <div class=\"fl-ub-row\"><i style=\"background:#D2654F;\"></i><span>MCP</span><b>1,177</b><em>0%</em></div>\n                    <div class=\"fl-ub-row\"><i style=\"background:var(--x-grey, #B0AFA9);\"></i><span>Conversation</span><b>35.7K</b><em>13%</em></div>\n                    <div class=\"fl-ub-row\"><i style=\"background:#2E9E72;\"></i><span>Tool results</span><b>237K</b><em>84%</em></div>\n                  </div>\n                </div>\n              </div>\n            </div>\n          </div>\n        </div>";

  const desktopWin = document.getElementById('desktopWindow');

  // Shimmering words get the copy their band of light runs over (see
  // .fl-shimmer in the CSS), as they come: from this markup and from
  // whatever the playback puts in later.
  function shimmerize(root) {
    const list = root.matches?.('.fl-shimmer') ? [root] : [];
    root.querySelectorAll?.('.fl-shimmer').forEach((el) => list.push(el));
    for (const el of list) {
      if (el.querySelector(':scope > .fl-shim-win')) continue;
      const win = document.createElement('span');
      win.className = 'fl-shim-win';
      win.setAttribute('aria-hidden', 'true');
      const txt = document.createElement('span');
      txt.className = 'fl-shim-txt';
      txt.textContent = el.textContent;
      win.appendChild(txt);
      el.appendChild(win);
    }
  }
  shimmerize(mount);
  new MutationObserver((records) => {
    for (const r of records) r.addedNodes.forEach((n) => { if (n.nodeType === 1) shimmerize(n); });
  }).observe(mount, { childList: true, subtree: true });

  function setStageMode(mode) {
    if (!desktopWin) return;
    desktopWin.classList.toggle('is-ide', mode === 'ide');
    desktopWin.classList.toggle('is-usage', mode === 'usage');

    document.querySelectorAll('.win-mode').forEach((ws) => {
      ws.classList.toggle('is-active', ws.dataset.workspace === mode);
    });
    // A list shown again (or for the first time) opens at its end.
    document.querySelectorAll('.win-mode.is-active .fl-chat-feed').forEach((feed) => {
      feed.scrollTop = feed.scrollHeight;
    });
  }

  document.getElementById('tbToUsage')?.addEventListener('click', () => showDemo(usageDemo || 'agent'));
  document.getElementById('tbToIde')?.addEventListener('click', () => showDemo('editor'));

  /* ========================================================================
     3b. 1:1 Flutter Live Animations & Interactive Dock Widgets
     ======================================================================== */
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  // The README's pictures (serve.mjs's /__shots) set window.baoShot to how
  // many of each conversation's steps to show, { usage: n, ide: n }: drawn
  // at once, done, and still.
  const shot = window.baoShot || null;
  let livePaused = reducedMotion || !!shot;

  // --- ThinkingSpark (lib/chat/widgets/thinking_spark.dart) ---
  const SPARK_SEQ = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1];
  const sparkCanvases = Array.from(document.querySelectorAll('.fl-spark'));

  function drawTeardropRay(ctx, angle, len, bulb, neck) {
    ctx.save();
    ctx.rotate(angle);
    ctx.beginPath();
    ctx.moveTo(0, -neck);
    ctx.bezierCurveTo(len * 0.45, -neck * 1.1, len - bulb * 0.6, -bulb, len, 0);
    ctx.bezierCurveTo(len - bulb * 0.6, bulb, len * 0.45, neck * 1.1, 0, neck);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  function drawThinkingSpark(canvas, shapeIdx, rotRad) {
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const w = canvas.width;
    const h = canvas.height;
    const cx = w / 2;
    const cy = h / 2;
    const R = Math.min(w, h) * 0.46;

    ctx.clearRect(0, 0, w, h);
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(rotRad);
    ctx.fillStyle = '#D97857';
    ctx.strokeStyle = '#D97857';

    if (shapeIdx === 0) {
      ctx.beginPath();
      ctx.arc(0, 0, R * 0.22, 0, Math.PI * 2);
      ctx.fill();
    } else if (shapeIdx === 1) {
      for (let i = 0; i < 4; i++) {
        drawTeardropRay(ctx, (i * Math.PI) / 2, R * 0.9, R * 0.2, R * 0.05);
      }
      ctx.beginPath();
      ctx.arc(0, 0, R * 0.14, 0, Math.PI * 2);
      ctx.fill();
    } else if (shapeIdx === 2) {
      ctx.lineWidth = Math.max(1.5, R * 0.16);
      ctx.lineCap = 'round';
      for (let i = 0; i < 8; i++) {
        const a = (i * Math.PI) / 4;
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(Math.cos(a) * R * 0.8, Math.sin(a) * R * 0.8);
        ctx.stroke();
      }
    } else if (shapeIdx === 3) {
      const pts = 12;
      const outer = R * 0.88;
      const inner = R * 0.46;
      const coords = [];
      for (let i = 0; i < pts; i++) {
        const a = (i * Math.PI) / 6;
        const r = i % 2 === 0 ? outer : inner;
        coords.push([Math.cos(a) * r, Math.sin(a) * r]);
      }
      ctx.beginPath();
      for (let i = 0; i < pts; i++) {
        const prev = coords[(i + pts - 1) % pts];
        const curr = coords[i];
        const next = coords[(i + 1) % pts];
        const mx1 = (prev[0] + curr[0]) / 2;
        const my1 = (prev[1] + curr[1]) / 2;
        const mx2 = (curr[0] + next[0]) / 2;
        const my2 = (curr[1] + next[1]) / 2;
        if (i === 0) ctx.moveTo(mx1, my1);
        ctx.quadraticCurveTo(curr[0], curr[1], mx2, my2);
      }
      ctx.closePath();
      ctx.fill();
    } else if (shapeIdx === 4) {
      for (let i = 0; i < 6; i++) {
        drawTeardropRay(ctx, (i * Math.PI) / 3, R * 0.98, R * 0.19, R * 0.04);
      }
      ctx.beginPath();
      ctx.arc(0, 0, R * 0.16, 0, Math.PI * 2);
      ctx.fill();
    } else {
      for (let i = 0; i < 6; i++) {
        drawTeardropRay(ctx, (i * Math.PI) / 3, R * 0.97, R * 0.29, R * 0.07);
      }
      ctx.beginPath();
      ctx.arc(0, 0, R * 0.24, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  // --- PixelLoader (lib/chat/widgets/pixel_loader.dart, exact 19-frame fill) ---
  const PIXEL_FRAMES = [
    '#........', '+#.......', '++...#...', '++...+..#', '++...+#.+',
    '++...++#+', '++.#.++++', '++#+.++++', '++++#++++', '#########',
    '#########', '-++++++++', '.-+++++++', '..+++-+++', '..+++.++-',
    '..+++.-+.', '..+++..-.', '..+-+....', '..-.+....'
  ];
  const PIXEL_ALPHA = { '#': 1, '+': 0.55, '-': 0.25, '.': 0 };
  const pixelCanvases = Array.from(document.querySelectorAll('.fl-pixel-loader'));

  // _PixelPainter: square pixels, at 14 pixels of 3 and gaps of 2, the
  // grid in the middle, each to the nearest half pixel; textMuted leaning
  // a fifth to the accent.
  function drawPixelLoader(canvas, frameIdx) {
    const fi = frameIdx % PIXEL_FRAMES.length;
    if (canvas._pf === fi) return;
    canvas._pf = fi;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const side = canvas.clientWidth || canvas.width / 2;
    const dpr = Math.max(2, Math.round(window.devicePixelRatio || 1));
    const px = Math.round(side * dpr);
    if (canvas.width !== px) { canvas.width = px; canvas.height = px; }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, side, side);
    const half = (v) => Math.round(v * 2) / 2;
    const cell = Math.max(1, half((side * 3) / 14));
    const gap = Math.max(0.5, half((side * 2) / 14));
    const inset = half((side - 3 * cell - 2 * gap) / 2);
    const frame = PIXEL_FRAMES[fi];
    for (let i = 0; i < 9; i++) {
      const a = PIXEL_ALPHA[frame[i]] || 0;
      if (!a) continue;
      ctx.fillStyle = `rgba(172, 163, 146, ${a})`;
      ctx.fillRect(inset + (i % 3) * (cell + gap), inset + Math.floor(i / 3) * (cell + gap), cell, cell);
    }
  }

  // Stilled for a picture, at the spark's fullest (SPARK_SEQ 5).
  let sparkElapsed = shot ? 5 * 120 + 60 : 0;
  let lastAnimTs = performance.now();
  // The little canvases move slowly: drawn on the page's shared 30-frame
  // beat (baoTicker) they look as smooth as at the screen's rate, at a
  // fraction of the work, and on the same frames as the hero's sky.
  let ticking = false;
  function tickFlutterCanvases(now) {
    // Off screen or in a hidden tab the loop stops; it starts again on
    // the way back.
    if (!windowInView || document.hidden) { ticking = false; return false; }
    const dt = Math.min(100, now - lastAnimTs);
    lastAnimTs = now;
    if (!livePaused) {
      sparkElapsed += dt;
    }
    const seqIdx = Math.floor(sparkElapsed / 120) % SPARK_SEQ.length;
    const shape = SPARK_SEQ[seqIdx];
    const rot = ((sparkElapsed % 12000) / 12000) * Math.PI * 2;
    // Only the shown mode's (asking the layout which are shown would cost
    // a layout every beat while the transcript changes).
    const mode = shownMode();
    const shown = (c) => (c._ws || (c._ws = c.closest('[data-workspace]')?.dataset.workspace || mode)) === mode;
    if (windowInView && !document.hidden) sparkCanvases.forEach((c) => { if (shown(c)) drawThinkingSpark(c, shape, rot); });

    // 80 ms a frame, an agent's at 1.5× and a subagent's at 1.3×.
    if (windowInView && !document.hidden) {
      pixelCanvases.forEach((c) => { if (shown(c)) drawPixelLoader(c, Math.floor(sparkElapsed / (c.closest('.fl-agent') ? 61.5 : 53.3))); });
    }

  }

  function startFlutterTicks() {
    if (ticking || reducedMotion) return;
    ticking = true;
    lastAnimTs = performance.now();
    window.baoTicker.add(tickFlutterCanvases);
  }

  // Paint frame 0 immediately even under reducedMotion
  sparkCanvases.forEach((c) => drawThinkingSpark(c, 4, 0.2));
  pixelCanvases.forEach((c) => drawPixelLoader(c, 8));
  document.addEventListener('visibilitychange', () => { if (!document.hidden) startFlutterTicks(); });
  // Started once windowInView is set, below.

  // --- ActivityRow._Musing Typewriter (lib/chat/widgets/activity_row.dart) ---
  const MUSING_PHRASES = [
    'Doodling in the margins',
    'Cogitating',
    'Binding the monad',
    'Squinting at the diff',
    'Wrangling edge cases',
    'Herding tokens',
    'Tracing the stack',
    'Negotiating with types',
    'Percolating',
    'Brewing a plan'
  ];

  function startMusing(el, startIdx) {
    if (!el || reducedMotion) return;
    let phraseIdx = startIdx % MUSING_PHRASES.length;
    let phase = 'type'; // type -> blink -> dots -> fade
    let charPos = 0;
    let stepCount = 0;
    let caretOn = true;

    const key = el.dataset.musing;
    function nextTick() {
      if (livePaused || !windowInView || document.hidden || shownMode() !== key) {
        setTimeout(nextTick, 250);
        return;
      }
      const phrase = MUSING_PHRASES[phraseIdx];
      if (phase === 'type') {
        el.style.opacity = '1';
        charPos++;
        const slice = phrase.slice(0, charPos);
        el.innerHTML = `${slice}<span class="fl-musing-caret"></span>`;
        if (charPos >= phrase.length) {
          phase = 'blink';
          stepCount = 0;
          setTimeout(nextTick, 220);
        } else {
          const prevCh = phrase[charPos - 1];
          const delay = 14 + Math.random() * 14 + (prevCh === ' ' ? 24 : 0);
          setTimeout(nextTick, delay);
        }
      } else if (phase === 'blink') {
        caretOn = !caretOn;
        el.innerHTML = `${phrase}<span class="fl-musing-caret" style="opacity:${caretOn ? 1 : 0};"></span>`;
        stepCount++;
        if (stepCount >= 3) {
          phase = 'dots';
          stepCount = 0;
          setTimeout(nextTick, 280);
        } else {
          setTimeout(nextTick, 260);
        }
      } else if (phase === 'dots') {
        const dots = '.'.repeat((stepCount % 3) + 1);
        el.textContent = phrase + dots;
        stepCount++;
        if (stepCount >= 6) {
          phase = 'fade';
          setTimeout(nextTick, 350);
        } else {
          setTimeout(nextTick, 400);
        }
      } else {
        el.style.opacity = '0';
        setTimeout(() => {
          phraseIdx = (phraseIdx + 1) % MUSING_PHRASES.length;
          charPos = 0;
          phase = 'type';
          el.textContent = '';
          el.style.opacity = '1';
          nextTick();
        }, 250);
      }
    }

    setTimeout(nextTick, 900 + startIdx * 450);
  }

  startMusing(document.querySelector('[data-musing="ide"]'), 0);
  startMusing(document.querySelector('[data-musing="usage"]'), 1);

  // --- RollingText Odometer + Live Timers (lib/chat/widgets/rolling_text.dart) ---
  function setRollingText(el, nextStr) {
    if (!el) return;
    const prevStr = el.dataset.rollVal || el.textContent || '';
    if (prevStr === nextStr && el.children.length > 0) return;
    el.dataset.rollVal = nextStr;

    if (reducedMotion || prevStr.length !== nextStr.length || el.children.length !== nextStr.length) {
      el.innerHTML = '';
      for (const ch of nextStr) {
        const slot = document.createElement('span');
        slot.className = 'fl-roll-ch';
        const track = document.createElement('span');
        track.className = 'fl-roll-track';
        const span = document.createElement('span');
        span.textContent = ch === ' ' ? '\u00a0' : ch;
        track.appendChild(span);
        slot.appendChild(track);
        el.appendChild(slot);
      }
      return;
    }

    for (let i = 0; i < nextStr.length; i++) {
      const oldCh = prevStr[i];
      const newCh = nextStr[i];
      if (oldCh === newCh) continue;
      const slot = el.children[i];
      if (!slot) continue;
      const track = document.createElement('span');
      track.className = 'fl-roll-track';
      track.style.transition = 'none';
      track.style.transform = 'translateY(0)';
      const s1 = document.createElement('span');
      s1.textContent = oldCh === ' ' ? '\u00a0' : oldCh;
      const s2 = document.createElement('span');
      s2.textContent = newCh === ' ' ? '\u00a0' : newCh;
      track.appendChild(s1);
      track.appendChild(s2);
      slot.innerHTML = '';
      slot.appendChild(track);
      requestAnimationFrame(() => {
        track.style.transition = 'transform 0.22s cubic-bezier(0.22, 1, 0.36, 1)';
        track.style.transform = 'translateY(-1.25em)';
      });
    }
  }

  function fmtDur(totalSec) {
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return `${m}m ${String(s).padStart(2, '0')}s`;
  }

  const liveTimers = {
    ide: { turnSec: 18 * 60 + 3, goalSec: 18 * 60 + 37, speed: 174.6, tokens: 100.63 },
    usage: { turnSec: 17 * 60 + 16, goalSec: 17 * 60 + 51, speed: 169.5, tokens: 93.63 }
  };

  function syncLiveStats(key) {
    const st = liveTimers[key];
    setRollingText(document.querySelector(`[data-roll="${key}-time"]`), fmtDur(st.turnSec));
    setRollingText(document.querySelector(`[data-roll="${key}-speed"]`), `${st.speed.toFixed(2)} tok/s`);
    setRollingText(document.querySelector(`[data-roll="${key}-tokens"]`), `${st.tokens.toFixed(2)}k tokens`);
    const gEl = document.querySelector(`[data-goal-elapsed="${key}"]`);
    if (gEl) gEl.textContent = ` · ${fmtDur(st.goalSec)}`;
  }

  syncLiveStats('ide');
  syncLiveStats('usage');

  if (!reducedMotion) {
    setInterval(() => {
      if (livePaused) return;
      ['ide', 'usage'].forEach((key) => {
        const st = liveTimers[key];
        st.turnSec += 1;
        st.goalSec += 1;
        const deltaSpeed = (Math.random() - 0.48) * 3.4;
        st.speed = Math.max(152, Math.min(228, st.speed + deltaSpeed));
        st.tokens += st.speed / 1000;
        // Counted on regardless; drawn only where it can be seen.
        if (windowInView && !document.hidden && shownMode() === key) syncLiveStats(key);
      });
    }, 1000);
  }

  // Stop / Play toggle on Composer button
  document.querySelectorAll('[data-live-toggle]').forEach((btn) => {
    btn.addEventListener('click', () => {
      livePaused = !livePaused;
      desktopWin?.classList.toggle('is-paused', livePaused);
      document.querySelectorAll('[data-live-toggle]').forEach((b) => {
        b.classList.toggle('is-paused', livePaused);
      });
    });
  });

  // GoalPanel expand / collapse
  document.querySelectorAll('[data-goal-panel]').forEach((panel) => {
    const head = panel.querySelector('.fl-goal-head');
    head?.addEventListener('click', () => {
      const open = panel.classList.toggle('is-expanded');
      head.setAttribute('aria-expanded', String(open));
    });
  });

  // ContextUsagePanel toggle (close button & composer ring button)
  const ideCtxPanel = document.getElementById('ideContextPanel');
  const ideCtxRingBtn = document.getElementById('ideCtxRingBtn');
  const ideCtxClose = document.getElementById('ideCtxClose');

  function setIdeContextOpen(open) {
    ideCtxPanel?.classList.toggle('is-open', open);
    ideCtxRingBtn?.classList.toggle('is-active', open);
  }

  ideCtxClose?.addEventListener('click', () => setIdeContextOpen(false));
  ideCtxRingBtn?.addEventListener('click', () => {
    setIdeContextOpen(!ideCtxPanel?.classList.contains('is-open'));
  });

  // ContextUsagePanel _PartCell breakdown drawer
  const PART_DETAILS = {
    system: [
      ['base_system_prompt.md', '16.4k'],
      ['environment_and_workspace', '5.2k'],
      ['security_and_style_rules', '3.6k']
    ],
    memory: [
      ['monad/CLAUDE.md', '14.8k'],
      ['~/.claude/rules/请说中文.md', '1.2k'],
      ['MEMORY.md + 12 linked notes', '23.1k']
    ],
    skills: [
      ['code-review · simplify · run', '11.4k'],
      ['cloudflare:* (12 skills)', '9.8k'],
      ['baocode-usage · dataviz', '4.4k']
    ],
    tools: [
      ['Bash · Read · Edit · Write', '22.8k'],
      ['browser_* (22 DevTools tools)', '31.4k'],
      ['session_* · usage_report', '10.3k']
    ],
    mcp: [
      ['mcp__baocode__browser_*', '12.1k'],
      ['mcp__baocode__session_*', '5.4k']
    ],
    messages: [
      ['User instructions (6 turns)', '4.2k'],
      ['Assistant reasoning & summaries', '12.1k']
    ],
    toolResult: [
      ['adb_bridge.dart (read + diff)', '44.6k'],
      ['tunnel_mux.dart & test output', '38.2k'],
      ['protocol_schema.dart', '25.6k']
    ]
  };

  const idePartDrawer = document.getElementById('idePartDrawer');
  const ideCtxBar = ideCtxPanel?.querySelector('.fl-ctx-bar');
  let selectedPart = null;

  document.querySelectorAll('#idePartGrid .fl-part-cell[data-part]').forEach((cell) => {
    cell.addEventListener('click', () => {
      const part = cell.dataset.part;
      selectedPart = selectedPart === part ? null : part;

      document.querySelectorAll('#idePartGrid .fl-part-cell[data-part]').forEach((c) => {
        c.classList.toggle('is-selected', c.dataset.part === selectedPart);
      });

      if (ideCtxBar) {
        ideCtxBar.classList.toggle('has-focus', Boolean(selectedPart));
        ideCtxBar.querySelectorAll('[data-part-bar]').forEach((seg) => {
          seg.classList.toggle('is-focused', seg.dataset.partBar === selectedPart);
        });
      }

      if (idePartDrawer) {
        if (!selectedPart || !PART_DETAILS[selectedPart]) {
          idePartDrawer.hidden = true;
        } else {
          idePartDrawer.innerHTML = PART_DETAILS[selectedPart]
            .map(([name, tok]) => `<div class="fl-pd-row"><code>${name}</code><b>${tok}</b></div>`)
            .join('');
          idePartDrawer.hidden = false;
        }
      }
    });
  });

  // ActivityStrip expand / Undo all / Keep all
  document.querySelectorAll('[data-change-strip]').forEach((strip) => {
    const toggle = strip.querySelector('.fl-strip-toggle');
    const tree = strip.querySelector('.fl-change-tree');
    const countEl = strip.querySelector('.fl-strip-count');
    const origLabel = countEl ? countEl.textContent : '';

    toggle?.addEventListener('click', () => {
      const expanded = strip.classList.toggle('is-expanded');
      toggle.setAttribute('aria-expanded', String(expanded));
      if (tree) tree.hidden = !expanded;
    });

    strip.querySelectorAll('[data-strip-action]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const act = btn.dataset.stripAction;
        if (!countEl) return;
        const already = strip.dataset.resolved === act;
        if (already) {
          strip.dataset.resolved = '';
          countEl.textContent = origLabel;
          strip.querySelectorAll('[data-strip-action]').forEach((b) => { b.style.opacity = '1'; });
        } else {
          strip.dataset.resolved = act;
          countEl.textContent = act === 'keep' ? 'All edits kept' : 'Reverted edits';
          strip.querySelectorAll('[data-strip-action]').forEach((b) => {
            b.style.opacity = b === btn ? '1' : '0.45';
          });
        }
      });
    });
  });

  // Mode 1 IdeChatTitle tab switch
  const ideChatTabs = Array.from(document.querySelectorAll('[data-chat-tab]'));
  const ideChatFeed = document.getElementById('ideChatFeed');
  const ideLiveFeedHtml = ideChatFeed ? ideChatFeed.innerHTML : '';
  const ideDoneFeedHtml = `
    <div class="fl-step is-muted"><span class="fl-obj">Searched <b>4</b> files · thought 11s</span></div>
    <div class="fl-step"><span class="fl-verb">Edited</span><span class="fl-obj">wheel_glide.dart</span><span class="fl-add">+142</span><span class="fl-del">-38</span></div>
    <div class="fl-step"><span class="fl-verb">Edited</span><span class="fl-obj">smooth_scroll_controller.dart</span><span class="fl-add">+64</span><span class="fl-del">-12</span></div>
    <div class="fl-prose">Locked trackpad deadzone to 0.01px and switched desktop wheel inertia to 144/360Hz ease-out without overscroll bounce.</div>
    <div class="fl-step is-muted"><span class="fl-obj">Ran <b>3</b> tests · all green · 42s total</span></div>
  `;

  ideChatTabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const idx = tab.dataset.chatTab;
      ideChatTabs.forEach((t) => t.classList.toggle('is-active', t === tab));
      if (!ideChatFeed) return;
      if (idx === '0') {
        ideChatFeed.innerHTML = ideDoneFeedHtml;
      } else {
        ideChatFeed.innerHTML = ideLiveFeedHtml;
        // Re-bind live canvas & rolling refs inside Mode 1 feed
        const newSpark = ideChatFeed.querySelector('.fl-spark');
        if (newSpark) {
          sparkCanvases.length = 0;
          sparkCanvases.push(...document.querySelectorAll('.fl-spark'));
        }
        startMusing(ideChatFeed.querySelector('[data-musing="ide"]'), 2);
        syncLiveStats('ide');
      }
    });
  });

  /* ========================================================================
     4. Crisp 1:1 Flutter UsageContextSection Stepped Bar Chart (UsagePalette._dark)
     ======================================================================== */
  const USAGE_POINTS = [];
  (function buildUsageSeries() {
    const N = 88;
    const compactIdx = 62;
    for (let i = 0; i < N; i++) {
      let totalK;
      if (i <= compactIdx) {
        const t = i / compactIdx;
        totalK = 36 + Math.pow(t, 1.28) * 329 + Math.sin(i * 0.7) * 5;
      } else {
        const t = (i - compactIdx - 1) / (N - compactIdx - 2);
        totalK = 34 + Math.pow(t, 0.85) * 248 + Math.sin(i * 0.9) * 4;
      }
      totalK = Math.max(24, Math.min(372, totalK));
      if (i === N - 1) {
        totalK = 282;
      }
      const cacheWriteK = i === N - 1 ? 0 : ((i === 0 || i === compactIdx + 1 || i % 11 === 0) ? 14 + (i % 7) : 4);
      const inputK = i === N - 1 ? 1 : 3;
      const outputK = 3 + (i % 4);
      const cacheReadK = Math.max(8, totalK - cacheWriteK - inputK - outputK);
      const reqNum = Math.min(219, Math.max(1, Math.round(((i + 1) / N) * 219)));
      const minuteOffset = Math.round((i / (N - 1)) * 33);
      const hh = 19 + Math.floor((38 + minuteOffset) / 60);
      const mm = (38 + minuteOffset) % 60;
      const timeStr = `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
      const cachePct = i === N - 1 ? 100 : Math.round((cacheReadK / (cacheReadK + cacheWriteK + inputK)) * 100);
      const cost = i === N - 1 ? '0.205' : (0.04 + (totalK / 400) * 0.19).toFixed(3);
      const prevTotal = i > 0 ? USAGE_POINTS[i - 1].totalK : totalK;
      const deltaTok = i === N - 1 ? 547 : Math.round((totalK - prevTotal) * 1000);
      USAGE_POINTS.push({
        idx: i,
        reqNum,
        timeStr,
        totalK,
        cacheReadK,
        inputK,
        cacheWriteK,
        outputK,
        cachePct,
        cost,
        deltaTok,
        compacted: i === compactIdx
      });
    }
  })();

  let selectedUsageIdx = USAGE_POINTS.length - 1;
  let usageReqTotal = 219;

  function renderGrowthSvg(svgId, height, interactive) {
    const svg = document.getElementById(svgId);
    if (!svg) return;
    const W = 440;
    const H = height;
    const padL = 34;
    const padR = 8;
    const padT = 14;
    const padB = 20;
    const plotW = W - padL - padR;
    const plotH = H - padT - padB;
    const maxK = 420;
    const yOf = (k) => padT + plotH - (k / maxK) * plotH;

    let out = '';

    [0, 100, 200, 300, 400].forEach((k) => {
      const y = yOf(k).toFixed(1);
      out += `<line x1="${padL}" y1="${y}" x2="${W - padR}" y2="${y}" style="stroke:var(--x-grid, rgba(225,224,220,0.07))" stroke-width="1"/>`;
      out += `<text x="${padL - 5}" y="${(Number(y) + 3).toFixed(1)}" text-anchor="end" style="fill:var(--x-dim, #7E7D78)" font-family="ui-monospace,monospace" font-size="8.5">${k === 0 ? '0' : k + 'K'}</text>`;
    });

    const N = USAGE_POINTS.length;
    const step = plotW / N;
    const barW = Math.max(1.8, step - 1.1);

    if (interactive) {
      const hx = (padL + selectedUsageIdx * step - 0.6).toFixed(1);
      out += `<rect x="${hx}" y="${padT}" width="${(barW + 1.2).toFixed(1)}" height="${plotH}" style="fill:var(--x-hl, rgba(237,201,148,0.22))" rx="1"/>`;
    }

    USAGE_POINTS.forEach((pt, i) => {
      const x = (padL + i * step).toFixed(1);
      const yBase = yOf(0);
      const hRead = (pt.cacheReadK / maxK) * plotH;
      const hIn = (pt.inputK / maxK) * plotH;
      const hWrite = (pt.cacheWriteK / maxK) * plotH;
      const hOut = (pt.outputK / maxK) * plotH;

      const yRead = yBase - hRead;
      const yIn = yRead - hIn;
      const yWrite = yIn - hWrite;
      const yOut = yWrite - hOut;

      const opacity = interactive && i !== selectedUsageIdx ? '0.88' : '1';
      out += `<g class="bar-hit" data-bar-idx="${i}" opacity="${opacity}">`;
      out += `<rect x="${x}" y="${padT}" width="${step.toFixed(1)}" height="${plotH}" fill="transparent"/>`;
      out += `<rect x="${x}" y="${yRead.toFixed(1)}" width="${barW.toFixed(1)}" height="${hRead.toFixed(1)}" fill="#2E9E72"/>`;
      out += `<rect x="${x}" y="${yIn.toFixed(1)}" width="${barW.toFixed(1)}" height="${Math.max(1, hIn).toFixed(1)}" fill="#3F86D8"/>`;
      if (hWrite > 0.8) {
        out += `<rect x="${x}" y="${yWrite.toFixed(1)}" width="${barW.toFixed(1)}" height="${hWrite.toFixed(1)}" fill="#B0679E"/>`;
      }
      out += `<rect x="${x}" y="${yOut.toFixed(1)}" width="${barW.toFixed(1)}" height="${Math.max(1.2, hOut).toFixed(1)}" fill="#BD8128"/>`;

      if (pt.compacted) {
        const cx = (padL + i * step + barW / 2).toFixed(1);
        const cy = yOf(398).toFixed(1);
        out += `<polygon points="${cx},${Number(cy) - 4} ${Number(cx) + 4},${cy} ${cx},${Number(cy) + 4} ${Number(cx) - 4},${cy}" style="fill:var(--x-grey, #B0AFA9)"/>`;
      }
      out += `</g>`;
    });

    const times = ['19:38', '19:44', '19:47', '19:55', '19:57', '20:01', '20:02', '20:06'];
    times.forEach((lbl, idx) => {
      const tx = (padL + 12 + (idx / (times.length - 1)) * (plotW - 28)).toFixed(1);
      out += `<text x="${tx}" y="${H - 4}" text-anchor="middle" style="fill:var(--x-dim, #7E7D78)" font-family="ui-monospace,monospace" font-size="8.5">${lbl}</text>`;
    });

    svg.innerHTML = out;
  }

  function updateUsageInspector(idx) {
    selectedUsageIdx = Math.max(0, Math.min(USAGE_POINTS.length - 1, idx));
    const pt = USAGE_POINTS[selectedUsageIdx];
    renderGrowthSvg('heroGrowthSvg', 176, true);

    const numEl = document.getElementById('usageReqNum');
    const metaEl = document.getElementById('usageReqMeta');
    const promptEl = document.getElementById('usageReqPrompt');
    const deltaEl = document.getElementById('usageReqDelta');
    if (numEl) numEl.textContent = `#${pt.reqNum}/${usageReqTotal}`;
    if (metaEl) metaEl.textContent = `${pt.timeStr}  ·  claude-opus-5-5  ·  $${pt.cost}  ·  ${pt.cachePct}% cache`;
    if (promptEl) promptEl.textContent = `${Math.round(pt.totalK)}K`;
    if (deltaEl) {
      const sign = pt.deltaTok >= 0 ? '+' : '';
      deltaEl.textContent = `${sign}${pt.deltaTok}`;
      deltaEl.style.color = pt.deltaTok >= 0 ? 'var(--x-up, #9DC08B)' : 'var(--x-down, #E8877A)';
    }
  }

  document.getElementById('heroGrowthSvg')?.addEventListener('click', (e) => {
    const g = e.target.closest?.('[data-bar-idx]');
    if (g) updateUsageInspector(Number(g.getAttribute('data-bar-idx')));
  });
  document.getElementById('usagePrevReq')?.addEventListener('click', () => updateUsageInspector(selectedUsageIdx - 1));
  document.getElementById('usageNextReq')?.addEventListener('click', () => updateUsageInspector(selectedUsageIdx + 1));

  updateUsageInspector(USAGE_POINTS.length - 1);
  
  const initialMode = new URLSearchParams(window.location.search).get("mode") === "ide" ? "ide" : "usage";
  setStageMode(initialMode);

  // Islands conversation: the transcript runs under the card's title and
  // fades out there (EdgeFadeMask, underTitle) once there is content above.
  document.querySelectorAll('.fl-island-card .fl-chat-feed').forEach((feed) => {
    const sync = () => feed.classList.toggle('has-above', feed.scrollTop > 0.5);
    feed.addEventListener('scroll', sync, { passive: true });
    requestAnimationFrame(() => { feed.scrollTop = feed.scrollHeight; sync(); });
  });


  // --- Transcript playback (ChatHistoryView as a turn runs), looped ---
  // A turn plays as the desktop shows one: the user's bubble, thinking,
  // folded tool runs with their web badges, subagent cards working in
  // parallel, a plan to start, todos, edits, a command printing, then the
  // answer streaming in; once done its work folds to "Worked for …". The
  // list follows its end; the oldest rows leave from the top. Only the
  // shown mode plays, and only while the window is on screen.
  const WEB = {
    google: 'logos:google-icon',
    openai: 'simple-icons:openai',
    anthropic: 'simple-icons:anthropic',
    android: 'logos:android-icon',
    stackoverflow: 'logos:stackoverflow-icon',
    github: 'simple-icons:github'
  };

  // Each demo's turns; the first [prefill] items are on screen from the
  // start, done, and the rest plays on from there, round and round.
  const ADAPTER_TURN = [
    { k: 'user', text: 'Gemini and OpenAI Responses should go through the same adapter. Check their current pricing first, and plan before touching code.' },
    { k: 'think', ms: 1400 },
    { k: 'fold', run: 'Searching the web', obj: 'Gemini API pricing 2026', ms: 1500, done: 'Searched the web, fetched <b>3</b> pages', thought: '6s', web: ['google', 'openai', 'anthropic'] },
    { k: 'agents', list: [
      { desc: 'Map every caller of the stream decoder', type: 'Explore', model: 'Haiku 5.5', acts: ['Grepped decodeChunk', 'Read stream_decoder.dart', 'Read codex_service.dart', 'Grepped onUsage'], ms: 4600, tools: 9, tokens: '18.2k' },
      { desc: 'Collect cache pricing rules per upstream', type: 'Explore', model: 'Haiku 5.5', acts: ['Fetched ai.google.dev/pricing', 'Read pricing_schedule.dart', 'Fetched openai.com/api/pricing'], ms: 5600, tools: 7, tokens: '12.6k' }
    ] },
    { k: 'plan', title: 'Unified upstream adapter', lines: [
      'One <code>UpstreamAdapter</code> per provider, Claude Messages as the shared shape',
      'Gemini: hold <code>usageMetadata</code> until the final chunk',
      'Responses: map <code>reasoning</code> items to thinking blocks',
      'Pricing: cache read / write rates per upstream, peak hours included',
      'Tests against recorded streams for all three'
    ] },
    { k: 'todo', done: 1, total: 4, obj: 'Gemini stream decoder' },
    { k: 'edit', file: 'gemini_stream.dart', add: 188, del: 0, ms: 1300 },
    { k: 'edit', file: 'usage_backfill.dart', add: 74, del: 0, ms: 1100 },
    { k: 'edit', file: 'openai_responses.dart', add: 31, del: 4, ms: 1100 },
    { k: 'session', obj: 'Adapter tests on recorded streams', model: 'Sonnet 5.5', ms: 1100, sent: 'Run the adapter suite against the recorded Gemini, Responses and Claude streams. Fix fixtures only, not the adapter, and report back what failed.' },
    { k: 'todo', done: 3, total: 4, obj: 'Pricing per upstream' },
    { k: 'tool', icon: 'simple-icons:modelcontextprotocol', run: 'Calling', done: 'Called', obj: 'stripe · list_invoices', ms: 1200 },
    { k: 'edit', file: 'pricing_schedule.dart', add: 57, del: 12, ms: 1200 },
    { k: 'fold', run: 'Going to', obj: 'localhost:8080/usage', ms: 1500, done: 'Took <b>4</b> steps in the browser', thought: '5s', img: '/assets/mobile-4.webp' },
    { k: 'agents', list: [
      { desc: 'Review the diff for regressions', type: 'Review', model: 'Opus 5.5', acts: ['Read gemini_stream.dart', 'Read pricing_schedule.dart', 'Ran dart analyze'], ms: 3600, tools: 5, tokens: '21.4k' }
    ] },
    { k: 'prose', final: true, text: 'Gemini and Responses now share one adapter. Cache reads are backfilled from the final chunk, and the usage page shows costs that match the invoices. The recorded-stream tests run in their own conversation, which reports back here.' },
    { k: 'end', worked: '6m 12s' }
  ];

  const IMG_GAME = { src: '/assets/gen-game.webp', ratio: 1360 / 768 };
  const IMG_TITLE = { src: '/assets/gen-title.webp', ratio: 1360 / 768 };

  const SCRIPTS = {
    agent: { prefill: 8, turns: [
      ADAPTER_TURN,
      [
        { k: 'user', text: 'Make a store screenshot for the game demo: the boss fight on the sky islands, HUD on.' },
        { k: 'think', ms: 900 },
        { k: 'tool', icon: 'codicon:file', run: 'Reading', done: 'Read', obj: 'docs/art-direction.md', ms: 700 },
        { k: 'image', prompt: 'In-game screenshot of a stylized 3D action RPG: a swordswoman in a crimson cloak faces a bronze mechanical dragon over floating sky islands at sunset, boss bar, minimap and ability HUD', ...IMG_GAME, file: 'boss-fight.png', ms: 5200 },
        { k: 'prose', final: true, text: 'Saved to store/boss-fight.png at 1360×768. The HUD follows the demo build: boss bar on top, minimap, four abilities on cooldown.' },
        { k: 'end', worked: '41s' }
      ],
      [
        { k: 'agentmsg', after: 1800, agent: 'Adapter tests on recorded streams', model: 'Sonnet 5.5', text: 'All 42 adapter tests pass against the recorded Gemini, Responses and Claude streams. One fixture still priced gemini-3-pro cache reads at the old rate: I updated <code>pricing_test.dart</code> and left the adapter as it was.' },
        { k: 'think', ms: 900 },
        { k: 'session', obj: 'Adapter tests on recorded streams', model: 'Sonnet 5.5', action: 'send', ms: 900, sent: 'Run the same suite on prod-gpu-01 over SSH, then check the Pixel on its USB-C port still connects.' },
        { k: 'tool', icon: 'material-symbols:mobile-outline-rounded', run: 'Installing on', done: 'Installed on', obj: 'Pixel 9 · USB-C via prod-gpu-01', ms: 1500 },
        { k: 'prose', final: true, text: 'Good: the fixture fix is the only change, so the adapter stands. The same suite is now running on prod-gpu-01, and the Pixel on its USB-C port connects and streams usage live.' },
        { k: 'end', worked: '1m 12s' }
      ]
    ] },

    ide: { prefill: 5, turns: [
      [
        { k: 'user', text: 'Make the phone on the remote USB-C port show up locally.' },
        { k: 'think', ms: 1200 },
        { k: 'agents', list: [
          { desc: 'Find where devices are listed', type: 'Explore', model: 'Haiku 5.5', acts: ['Grepped listDevices', 'Read adb_bridge.dart', 'Read tunnel_mux.dart'], ms: 3600, tools: 6, tokens: '9.4k' }
        ] },
        { k: 'cmd', cmd: 'adb -s R5CT20 forward tcp:9222 localabstract:chrome_devtools_remote', ms: 1300, out: ['9222'] },
        { k: 'edit', file: 'adb_bridge.dart', add: 64, del: 3, ms: 1100 },
        { k: 'edit', file: 'tunnel_mux.dart', add: 142, del: 0, ms: 1400 },
        { k: 'fold', run: 'Searching the web', obj: 'adb forward over ssh tunnel', ms: 1300, done: 'Searched the web, fetched <b>2</b> pages', thought: '4s', web: ['android', 'stackoverflow'] },
        { k: 'cmd', cmd: 'dart test test/ide/tunnel_mux_test.dart', ms: 1600, out: ['00:01 +9: device channel survives reconnect', '00:02 +14: All tests passed!'] },
        { k: 'prose', final: true, text: 'The phone on prod-gpu-01’s USB-C port now shows up in the local device list, and Chrome on it can be debugged from here.' },
        { k: 'end', worked: '4m 37s' }
      ],
      [
        { k: 'user', text: 'Open the site on that phone and check it renders.' },
        { k: 'fold', run: 'Going to', obj: 'baocode.dev on Pixel 9', ms: 1700, done: 'Took <b>5</b> steps in the browser', thought: '4s', img: '/assets/mobile-2.webp' },
        { k: 'prose', final: true, text: 'Renders cleanly on the phone: no layout shift, fonts load, first paint in 0.8s.' },
        { k: 'end', worked: '52s' }
      ]
    ] },

    windows: { prefill: 5, turns: [
      [
        { k: 'user', text: 'npm run build takes 40s on this Windows box and 9s on the Mac. Find out why, and no WSL.' },
        { k: 'think', ms: 1100 },
        { k: 'cmd', cmd: 'npm run build', ms: 1800, out: ['vite v6.2.0 building for production...', '✓ 1834 modules transformed.', '✓ built in 41.8s'] },
        { k: 'fold', run: 'Searching the web', obj: 'node build slow on Windows spawn cmd.exe', ms: 1300, done: 'Searched the web, fetched <b>3</b> pages', thought: '4s', web: ['google', 'stackoverflow', 'github'] },
        { k: 'cmd', cmd: 'rg -n "spawnSync" C:/workspace/shop/tools', ms: 1200, out: ['tools/build.mjs:42:  spawnSync("cmd", ["/c", step])', 'tools/build.mjs:77:  spawnSync("cmd", ["/c", "copy", src, dst])'] },
        { k: 'edit', file: 'build.mjs', add: 23, del: 9, ms: 1200 },
        { k: 'cmd', cmd: 'npm run build', ms: 1500, out: ['vite v6.2.0 building for production...', '✓ 1834 modules transformed.', '✓ built in 9.6s'] },
        { k: 'prose', final: true, text: 'Down from 41.8s to 9.6s, level with the Mac. The build started cmd.exe for every step and every copy; it runs them in-process now, and paths stay C:/… all the way through.' },
        { k: 'end', worked: '2m 26s' }
      ],
      [
        { k: 'user', text: 'Does it still build when I start it from the Mac over SSH?' },
        { k: 'think', ms: 800 },
        { k: 'cmd', cmd: 'git -C C:/workspace/shop status --short', ms: 900, out: [' M tools/build.mjs'] },
        { k: 'cmd', cmd: 'npm run build', ms: 1400, out: ['✓ 1834 modules transformed.', '✓ built in 9.8s'] },
        { k: 'prose', final: true, text: 'Yes: 9.8s when started over SSH from mac-studio, with nothing to set up on this side.' },
        { k: 'end', worked: '38s' }
      ]
    ] },

    remote: { prefill: 6, turns: [
      [
        { k: 'user', text: 'Put the relay on prod-gpu-01 behind Caddy, and keep port 7443 working for old clients.' },
        { k: 'think', ms: 1000 },
        { k: 'cmd', cmd: 'systemctl status relay --no-pager | head -3', ms: 1100, out: ['● relay.service - BaoCode iroh relay', '     Loaded: loaded (/etc/systemd/system/relay.service; enabled)', '     Active: active (running) since Mon 2026-11-16 09:12:04 UTC'] },
        { k: 'tool', icon: 'codicon:file', run: 'Reading', done: 'Read', obj: '/etc/caddy/Caddyfile', ms: 700 },
        { k: 'edit', file: 'Caddyfile', add: 14, del: 2, ms: 1200 },
        { k: 'cmd', cmd: 'sudo caddy reload --config /etc/caddy/Caddyfile', ms: 1300, out: ['INFO using config from file {"file": "/etc/caddy/Caddyfile"}', '✓ config reloaded: relay.baocode.dev, :7443'] },
        { k: 'tool', icon: 'codicon:plug', run: 'Forwarding', done: 'Forwarded', obj: 'localhost:7443 → prod-gpu-01:7443', ms: 900 },
        { k: 'browser', act: 'open', run: 'Opening', done: 'Opened', obj: 'localhost:7443/health', ms: 900 },
        { k: 'prose', final: true, text: 'Caddy now fronts the relay with TLS on 443, and 7443 still answers old clients. Checked through the forwarded port from this Mac: healthy, 38 ms.' },
        { k: 'end', worked: '3m 04s' }
      ],
      [
        { k: 'user', text: 'Build the Android app there and run it on my phone.' },
        { k: 'think', ms: 800 },
        { k: 'cmd', cmd: './gradlew assembleDebug -q', ms: 1600, out: ['✓ BUILD SUCCESSFUL in 48s'] },
        { k: 'tool', icon: 'material-symbols:mobile-outline-rounded', run: 'Installing on', done: 'Installed on', obj: 'Pixel 9 · USB-C on this Mac', ms: 1400 },
        { k: 'prose', final: true, text: 'Built on prod-gpu-01 and installed on the Pixel plugged into your Mac: adb reaches it through the SSH tunnel.' },
        { k: 'end', worked: '1m 31s' }
      ]
    ] },

    browser: { prefill: 3, turns: [
      [
        { k: 'user', text: 'Checkout on my store stutters when I apply a coupon. Find out why and fix it.' },
        { k: 'think', ms: 900 },
        { k: 'browser', act: 'open', run: 'Opening', done: 'Opened', obj: 'shop.local/checkout', ms: 1000 },
        { k: 'browser', act: 'snapshot', run: 'Reading the page', done: 'Read the page', obj: 'Checkout — Acme', ms: 800 },
        { k: 'browser', act: 'click', target: 'coupon', run: 'Clicking', done: 'Clicked', obj: '“Coupon code”', ms: 900 },
        { k: 'browser', act: 'type', target: 'coupon', text: 'SPRING25', run: 'Typing', done: 'Typed', obj: '“SPRING25”', ms: 1100 },
        { k: 'browser', act: 'perf', target: 'apply', run: 'Profiling', done: 'Profiled', obj: 'Apply · 3 long tasks, 412 ms', ms: 1900 },
        { k: 'browser', act: 'inspect', target: 'summary', run: 'Inspecting', done: 'Inspected', obj: '<CartSummary> state', ms: 1100 },
        { k: 'edit', file: 'cart_summary.tsx', add: 12, del: 31, ms: 1200 },
        { k: 'browser', act: 'reload', run: 'Reloading', done: 'Reloaded', obj: 'Checkout — Acme', ms: 800 },
        { k: 'browser', act: 'perf2', target: 'apply', run: 'Profiling', done: 'Profiled', obj: 'Apply · no long tasks, 38 ms', ms: 1700 },
        { k: 'prose', final: true, text: 'Applying a coupon re-rendered the whole cart three times: <CartSummary> recomputed taxes on every change. It is memoized now, and the click takes 38 ms instead of 412 ms, measured in your logged-in Chrome.' },
        { k: 'end', worked: '2m 51s' }
      ],
      [
        { k: 'user', text: 'Pay with the test card and make sure the order goes through.' },
        { k: 'browser', act: 'type', target: 'card', text: '4242 4242 4242 4242', run: 'Typing', done: 'Typed', obj: '“4242 4242 4242 4242”', ms: 1300 },
        { k: 'browser', act: 'click', target: 'pay', run: 'Clicking', done: 'Clicked', obj: '“Pay now”', ms: 900 },
        { k: 'browser', act: 'paid', run: 'Reading the page', done: 'Read the page', obj: 'Order #10482 confirmed', ms: 900 },
        { k: 'prose', final: true, text: 'Paid with the test card: order #10482 is confirmed and shows under your account.' },
        { k: 'end', worked: '34s' }
      ]
    ] },

    api: { prefill: 4, turns: [
      [
        { k: 'switch', up: 'claude', model: 'Opus 5.5', via: 'Claude Code' },
        { k: 'user', text: 'Add the Gemini peak-hour multiplier to the pricing rules.' },
        { k: 'think', ms: 900 },
        { k: 'edit', file: 'pricing_rules.dart', add: 42, del: 3, ms: 1200 },
        { k: 'prose', final: true, text: 'Added: 1.5× from 09:00 to 18:00 Pacific on weekdays, applied per request.' },
        { k: 'end', worked: '1m 05s' }
      ],
      [
        { k: 'switch', up: 'corp', model: 'GPT-5.5', via: 'corp-gateway' },
        { k: 'user', text: 'Review that change.' },
        { k: 'think', ms: 900 },
        { k: 'tool', icon: 'codicon:file', run: 'Reading', done: 'Read', obj: 'pricing_rules.dart', ms: 700 },
        { k: 'prose', final: true, text: 'One edge: a request that starts before 18:00 and ends after it is billed at peak. That matches Google’s own rule, so I would keep it.' },
        { k: 'end', worked: '22s' }
      ],
      [
        { k: 'switch', up: 'deepseek', model: 'DeepSeek V4', via: 'DeepSeek' },
        { k: 'user', text: 'Write the tests for it.' },
        { k: 'think', ms: 800 },
        { k: 'edit', file: 'pricing_rules_test.dart', add: 88, del: 0, ms: 1300 },
        { k: 'prose', final: true, text: 'Six tests: weekday peak, weekend, the 18:00 boundary, holidays, and two time zones.' },
        { k: 'end', worked: '41s' }
      ],
      [
        { k: 'switch', up: 'gemini', model: 'Gemini 3 Pro', via: 'Antigravity' },
        { k: 'user', text: 'Sum up the change for the PR.' },
        { k: 'think', ms: 700 },
        { k: 'prose', final: true, text: 'Adds Gemini’s weekday peak-hour multiplier (1.5×, 09:00–18:00 PT) to the pricing rules, billed by request start, with six tests around the boundaries.' },
        { k: 'end', worked: '14s' }
      ]
    ] },

    image: { prefill: 5, turns: [
      [
        { k: 'user', text: 'Make the title screen for the Steam page: SKYWARD, the swordswoman on a sky island at dusk.' },
        { k: 'think', ms: 900 },
        { k: 'image', prompt: 'Title screen of a stylized anime-style action RPG: SKYWARD logo and main menu on the left, a swordswoman in a crimson cloak on a floating sky island at blue hour', ...IMG_TITLE, file: 'title-screen.png', ms: 5000 },
        { k: 'prose', final: true, text: 'Saved to store/title-screen.png at 1360×768.' },
        { k: 'end', worked: '36s' }
      ],
      [
        { k: 'user', text: 'Now the boss fight on the sky islands, HUD on.' },
        { k: 'think', ms: 900 },
        { k: 'tool', icon: 'codicon:file', run: 'Reading', done: 'Read', obj: 'docs/art-direction.md', ms: 700 },
        { k: 'image', prompt: 'In-game screenshot of a stylized 3D action RPG: a swordswoman in a crimson cloak faces a bronze mechanical dragon over floating sky islands at sunset, boss bar, minimap and ability HUD', ...IMG_GAME, file: 'boss-fight.png', ms: 5200 },
        { k: 'prose', final: true, text: 'Saved to store/boss-fight.png. The HUD follows the demo build: boss bar on top, minimap, four abilities on cooldown.' },
        { k: 'end', worked: '41s' }
      ]
    ] },

    orchestrate: { prefill: 3, turns: [
      [
        { k: 'user', text: 'Ship 1.8: the iOS build on mac-studio, the Windows installer on win-workstation, the relay on prod-gpu-01. One conversation each, and report back here.' },
        { k: 'think', ms: 1000 },
        { k: 'session', obj: 'iOS TestFlight 1.8', host: 'mac-studio', model: 'Sonnet 5.5', ms: 900, sent: 'Bump to 1.8, archive and upload to TestFlight. Report the build number.' },
        { k: 'session', obj: 'Windows installer 1.8', host: 'win-workstation', model: 'Sonnet 5.5', ms: 900, closed: true, sent: 'Build the 1.8 installers for x64 and arm64, smoke-test them, report the hashes.' },
        { k: 'session', obj: 'Relay deploy 1.8', host: 'prod-gpu-01', model: 'Haiku 5.5', ms: 900, closed: true, sent: 'Deploy relay 1.8 behind Caddy, keep 7443, report health.' },
        { k: 'prose', final: true, text: 'Handed out to three conversations, one on each machine. Their reports come back here as they finish.' },
        { k: 'end', worked: '48s' }
      ],
      [
        { k: 'agentmsg', after: 2200, agent: 'Relay deploy 1.8', model: 'Haiku 5.5', text: 'Relay 1.8 is live behind Caddy. Health checks pass on 443 and 7443; p50 latency 31 ms.' },
        { k: 'think', ms: 600 },
        { k: 'prose', final: true, text: '1 of 3 in: the relay is live.' },
        { k: 'end', worked: '9s' }
      ],
      [
        { k: 'agentmsg', after: 2600, agent: 'Windows installer 1.8', model: 'Sonnet 5.5', text: 'Built and smoke-tested both installers. x64 <code>4f1c…9a2e</code>, arm64 <code>b7d0…13c5</code>. Ready to upload.' },
        { k: 'think', ms: 600 },
        { k: 'prose', final: true, text: '2 of 3: the Windows installers are built.' },
        { k: 'end', worked: '8s' }
      ],
      [
        { k: 'agentmsg', after: 2600, agent: 'iOS TestFlight 1.8', model: 'Sonnet 5.5', text: 'Build 1.8 (412) is uploaded to TestFlight and processing.' },
        { k: 'think', ms: 800 },
        { k: 'edit', file: 'RELEASE_NOTES.md', add: 24, del: 0, ms: 1200 },
        { k: 'prose', final: true, text: 'All three are done: iOS 1.8 (412) on TestFlight, the Windows installers built, the relay live. The release notes are in RELEASE_NOTES.md.' },
        { k: 'end', worked: '1m 02s' }
      ]
    ] }
  };

  // Faster than life: a turn reads in under a minute.
  const PACE = 0.6;

  let windowInView = true;
  if ('IntersectionObserver' in window && desktopWin) {
    new IntersectionObserver((entries) => {
      windowInView = entries.some((e) => e.isIntersecting);
      if (windowInView) startFlutterTicks();
    }).observe(desktopWin);
  }
  startFlutterTicks();

  function shownMode() {
    return desktopWin?.classList.contains('is-ide') ? 'ide' : 'usage';
  }

  function canPlay(key) {
    return !livePaused && windowInView && !document.hidden && shownMode() === key;
  }

  // Keeps the list at its end as it grows (the list itself does not
  // scroll by hand: the page scrolls past it).
  function makeFollower(feed) {
    let animating = false;
    function frame() {
      const target = feed.scrollHeight - feed.clientHeight;
      const gap = target - feed.scrollTop;
      const before = feed.scrollTop;
      if (Math.abs(gap) >= 0.6) feed.scrollTop += gap * 0.24;
      // There, or a step too small to move it (scrollTop keeps to whole
      // device pixels): settle, or this would go on every frame for ever.
      if (Math.abs(gap) < 0.6 || feed.scrollTop === before) {
        feed.scrollTop = target;
        animating = false;
        feed.dispatchEvent(new Event('scroll'));
        return;
      }
      requestAnimationFrame(frame);
    }
    return function follow() {
      if (animating) return;
      animating = true;
      requestAnimationFrame(frame);
    };
  }

  function pushUsageRequest() {
    const last = USAGE_POINTS[USAGE_POINTS.length - 1];
    let totalK = last.totalK + 2 + Math.random() * 6;
    let compacted = false;
    if (totalK > 380) {
      totalK = 38 + Math.random() * 6;
      compacted = true;
    }
    usageReqTotal += 1;
    const cacheWriteK = compacted ? 16 : 3;
    const inputK = 2;
    const outputK = 2 + Math.round(Math.random() * 3);
    const [hh, mm] = last.timeStr.split(':').map(Number);
    const mins = hh * 60 + mm + (Math.random() < 0.5 ? 1 : 0);
    const pt = {
      reqNum: usageReqTotal,
      timeStr: `${String(Math.floor(mins / 60) % 24).padStart(2, '0')}:${String(mins % 60).padStart(2, '0')}`,
      totalK,
      cacheReadK: Math.max(8, totalK - cacheWriteK - inputK - outputK),
      inputK,
      cacheWriteK,
      outputK,
      cachePct: compacted ? 64 : 97 + Math.round(Math.random() * 3),
      cost: (0.04 + (totalK / 400) * 0.19).toFixed(3),
      deltaTok: Math.round((totalK - last.totalK) * 1000),
      compacted: false
    };
    const followLast = selectedUsageIdx === USAGE_POINTS.length - 1;
    USAGE_POINTS.shift();
    USAGE_POINTS.push(pt);
    USAGE_POINTS.forEach((p, i) => { p.idx = i; });
    updateUsageInspector(followLast ? USAGE_POINTS.length - 1 : selectedUsageIdx - 1);

    const pane = document.querySelector('[data-workspace="usage"]');
    const vals = pane ? pane.querySelectorAll('.fl-stat-tile .fl-st-val') : [];
    usageTotals.tokensM += (totalK * 1000) / 1e6;
    usageTotals.cost += Number(pt.cost);
    usageTotals.peakK = Math.max(usageTotals.peakK, totalK);
    if (vals[0]) vals[0].textContent = `${usageTotals.tokensM.toFixed(1)}M`;
    if (vals[1]) vals[1].textContent = `$${usageTotals.cost.toFixed(2)}`;
    if (vals[2]) vals[2].textContent = String(usageReqTotal);
    usageMeterEl ??= Array.from(pane?.querySelectorAll('span') || []).find((el) => / \/ 400K$/.test(el.textContent) && !el.children.length);
    if (usageMeterEl) usageMeterEl.textContent = `${Math.round(totalK)}K / 400K`;
    const sub = pane?.querySelector('.fl-ug-sub');
    if (sub) sub.textContent = `${Math.round(totalK)}K now  ·  peak ${Math.round(usageTotals.peakK)}K  ·  ${usageReqTotal} reqs  ·  Cost $${usageTotals.cost.toFixed(2)}`;
  }
  const usageTotals = { tokensM: 36.4, cost: 15.03, peakK: 365 };
  let usageMeterEl;


  const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;');

  // Plays [script] in [feed] until stopped; [hooks.fx] hears each item as
  // it starts and as it is done (and whether it was built at once), for
  // what the window shows beside the conversation.
  function startPlayback(key, feed, script, hooks = {}) {
    const { prefill, turns } = script;
    const activity = feed?.querySelector('.fl-activity-row');
    const liveStats = feed?.querySelector('.fl-live-stats');
    if (!feed || !activity) return { stop() {} };
    let alive = true;
    const fx = (ev, phase) => hooks.fx?.(ev, phase, instant);
    // What was drawn into the markup gives way to the scripted turn.
    Array.from(feed.children).forEach((el) => {
      if (el !== activity && el !== liveStats) el.remove();
    });

    const scope = feed.parentElement;
    const countEl = scope.querySelector('.fl-strip-count');
    const addEl = scope.querySelector('.fl-strip-toggle .fl-add');
    const delEl = scope.querySelector('.fl-strip-toggle .fl-del');
    const threadAdd = key === 'usage' ? document.querySelector('.fl-thread-row.is-active .fl-add') : null;
    const strip = scope.querySelector('.fl-activity-strip');
    const base = {
      files: parseInt(countEl?.textContent, 10) || 0,
      add: parseInt(addEl?.textContent.replace('+', ''), 10) || 0,
      del: Math.abs(parseInt(delEl?.textContent, 10) || 0)
    };
    let totals = { ...base, seen: new Set() };
    let turnEdits = { files: new Set(), add: 0, del: 0 };
    // The turn's web sites and pictures, for its folded line.
    let turnWeb = [];
    let turnImgs = [];
    const follow = makeFollower(feed);
    let turnIdx = 0;
    let evIdx = 0;
    let turn = null; // { root, work }
    // Built at once, done (the prefill): no waits, no motion.
    let instant = false;

    function setTotals() {
      if (countEl) countEl.textContent = `${totals.files} file${totals.files === 1 ? '' : 's'} changed`;
      if (addEl) addEl.textContent = `+${totals.add}`;
      if (delEl) delEl.textContent = `-${totals.del}`;
      if (threadAdd) {
        threadAdd.textContent = `+${totals.add}`;
        threadAdd.style.display = totals.add ? '' : 'none';
      }
      // No changes, no strip.
      if (strip) strip.style.display = totals.files ? '' : 'none';
    }

    function prune() {
      // Turns far above leave; the list keeps its place.
      while (feed.scrollHeight > feed.clientHeight * 3.2) {
        const first = feed.firstElementChild;
        if (!first || first === activity || first === turn?.root) break;
        const h = first.offsetHeight + 4.5;
        first.remove();
        feed.scrollTop = Math.max(0, feed.scrollTop - h);
      }
    }

    function put(el, outside) {
      if (!instant) el.classList.add('is-live');
      (outside ? turn.root : turn.work).appendChild(el);
      if (!instant) follow();
      return el;
    }

    function make(tag, cls, html) {
      const el = document.createElement(tag);
      el.className = cls;
      if (html != null) el.innerHTML = html;
      return el;
    }

    function wait(ms, fn) {
      if (instant) { fn(); return; }
      setTimeout(function tick() {
        if (!alive) return;
        if (!canPlay(key)) { setTimeout(tick, 300); return; }
        fn();
      }, ms * PACE);
    }

    function later(ms, fn) {
      if (instant) fn(); else setTimeout(() => { if (alive) fn(); }, ms * PACE);
    }

    function setWorking(on) {
      activity.style.display = on ? '' : 'none';
      if (liveStats) liveStats.style.display = on ? '' : 'none';
    }

    function edited(file, add, del) {
      if (!totals.seen.has(file)) { totals.seen.add(file); totals.files += 1; }
      totals.add += add;
      totals.del += del;
      turnEdits.files.add(file);
      turnEdits.add += add;
      turnEdits.del += del;
      setTotals();
    }

    function request() {
      if (key === 'usage' && !instant) pushUsageRequest();
    }

    function stream(el, text, done, html) {
      if (instant) {
        if (html) el.innerHTML = text; else el.textContent = text;
        done();
        return;
      }
      const words = text.split(' ');
      let w = 0;
      let acc = '';
      (function chunk() {
        if (!alive) return;
        if (!canPlay(key)) { setTimeout(chunk, 300); return; }
        const n = 2 + Math.floor(Math.random() * 3);
        acc += (w ? ' ' : '') + words.slice(w, w + n).join(' ');
        w += n;
        if (html) el.innerHTML = acc; else el.textContent = acc;
        follow();
        if (w < words.length) setTimeout(chunk, 26 + Math.random() * 30);
        else done();
      })();
    }

    const okIcon = '<iconify-icon class="fl-agent-ok" icon="material-symbols:check-circle-outline-rounded" width="14" height="14"></iconify-icon>';
    const chev = '<iconify-icon class="fl-step-chev" icon="material-symbols:chevron-right-rounded" width="15" height="15"></iconify-icon>';

    // StepWebIcons then the pictures, after a folded line (_foldTrailing).
    function foldTrailing() {
      const shown = turnWeb.slice(0, 5);
      const rest = turnWeb.length - shown.length;
      const web = shown.length
        ? `<span class="fl-web-badges" style="width:${20 + (shown.length - 1) * 14}px">` +
          shown.map((site, i) => `<i style="left:${i * 14}px"><iconify-icon icon="${WEB[site]}" width="12" height="12"></iconify-icon></i>`).join('') +
          `</span>${rest > 0 ? `<em class="fl-web-rest">+${rest}</em>` : ''}`
        : '';
      const imgs = turnImgs.map((src) => `<img class="fl-step-thumb" src="${src}" alt="" />`).join('');
      return web + imgs;
    }

    // A turn opens on what came in: the user's bubble, or another agent's card.
    function startTurn(head, next) {
      turn = { root: make('div', 'fl-turn'), work: make('div', 'fl-turn-work') };
      turnEdits = { files: new Set(), add: 0, del: 0 };
      turnWeb = [];
      turnImgs = [];
      if (!instant) head.classList.add('is-live');
      turn.root.appendChild(head);
      turn.root.appendChild(turn.work);
      feed.insertBefore(turn.root, activity);
      if (!instant) { prune(); follow(); }
      wait(350, () => { setWorking(true); if (!instant) follow(); wait(200, next); });
    }

    const PLAY = {
      user(ev, next) {
        fx(ev, 'start');
        startTurn(make('div', 'fl-user-msg', `<div class="fl-user-bubble">${esc(ev.text)}</div>`), next);
      },
      // AgentMessageCard: a message another conversation sent this one.
      agentmsg(ev, next) {
        // It comes when the other conversation is done: a while after.
        wait(ev.after || 0, () => {
          fx(ev, 'done');
          startTurn(make('div', 'fl-agentmsg',
            `<div class="fl-agentmsg-head"><iconify-icon icon="codicon:reply" width="14" height="14"></iconify-icon>` +
            `<span class="fl-agentmsg-name">${esc(ev.agent)}</span><em>${ev.model}</em><em>· sent</em></div>` +
            `<div class="fl-agentmsg-body">${ev.text}</div>`), next);
        });
      },
      // SessionStep: work handed to another conversation, opened to what was sent.
      session(ev, next) {
        const send = ev.action === 'send';
        const icon = '<iconify-icon class="fl-step-icon" icon="codicon:comment-discussion" width="13" height="13"></iconify-icon>';
        const wrap = put(make('div', 'fl-cmd',
          `<div class="fl-step">${icon}<span class="fl-shimmer">${send ? 'Handing work to' : 'Starting'} ${esc(ev.obj)}</span></div>`));
        const head = wrap.firstElementChild;
        wait(ev.ms, () => {
          head.innerHTML = `${icon}<span class="fl-verb">${send ? 'Handed work to' : 'Started'}</span>` +
            `<span class="fl-obj fl-session-name">${esc(ev.obj)}</span><em>${ev.model}</em>${ev.closed ? chev : chev.replace('fl-step-chev', 'fl-step-chev is-open')}`;
          if (!ev.closed) {
            const body = make('div', 'fl-step-body is-text', esc(ev.sent));
            if (!instant) body.classList.add('is-live');
            wrap.appendChild(body);
          }
          if (!instant) follow();
          fx(ev, 'done');
          request();
          wait(500, next);
        });
      },
      // ImageStep: its line, the picture's place with a light sweeping
      // across while it is made, then the picture. It stays out when the
      // turn's work folds.
      image(ev, next) {
        new Image().src = ev.src;
        const icon = '<iconify-icon class="fl-step-icon" icon="ri:image-line" width="13" height="13"></iconify-icon>';
        const el = put(make('div', 'fl-imgstep',
          `<div class="fl-step">${icon}<span class="fl-verb fl-shimmer">Generating image</span><span class="fl-obj">${esc(ev.prompt)}</span></div>` +
          `<div class="fl-img-box is-making" style="aspect-ratio:${ev.ratio}"></div>`), true);
        wait(ev.ms, () => {
          el.querySelector('.fl-shimmer').outerHTML = '<span class="fl-verb">Generated image</span>';
          const box = el.querySelector('.fl-img-box');
          box.classList.remove('is-making');
          box.innerHTML = `<img src="${ev.src}" alt="" />`;
          fx(ev, 'done');
          request();
          wait(500, next);
        });
      },
      // A browser tool's step (BrowserStep): Chrome's icon, the verb and
      // what it was about; the page beside it plays along.
      browser(ev, next) {
        const icon = '<iconify-icon class="fl-step-icon" icon="lucide:chrome" width="13" height="13"></iconify-icon>';
        const el = put(make('div', 'fl-step', `${icon}<span class="fl-verb fl-shimmer">${ev.run}</span><span class="fl-obj">${esc(ev.obj)}</span>`));
        fx(ev, 'start');
        wait(ev.ms, () => {
          el.querySelector('.fl-shimmer').outerHTML = `<span class="fl-verb">${ev.done}</span>`;
          fx(ev, 'done');
          request();
          wait(320, next);
        });
      },
      // The model changed between turns: a quiet line, and the picker.
      switch(ev, next) {
        fx(ev, 'done');
        const el = make('div', 'fl-model-switch',
          `<iconify-icon icon="codicon:sparkle" width="12" height="12"></iconify-icon><span>Switched to <b>${ev.model}</b> · ${ev.via}</span>`);
        if (!instant) el.classList.add('is-live');
        feed.insertBefore(el, activity);
        if (!instant) follow();
        wait(700, next);
      },
      think(ev, next) {
        const el = put(make('div', 'fl-step', '<span class="fl-shimmer">Thinking</span>'));
        wait(ev.ms, () => {
          el.innerHTML = `<span class="fl-verb">Thought</span><span class="fl-obj">${Math.max(1, Math.round(ev.ms / 450))}s</span>`;
          wait(180, next);
        });
      },
      fold(ev, next) {
        const el = put(make('div', 'fl-step', `<span class="fl-shimmer">${ev.run} ${esc(ev.obj)}</span>`));
        let badges = null;
        if (ev.web) {
          badges = make('span', 'fl-web-badges');
          el.appendChild(badges);
          ev.web.forEach((site, i) => later((ev.ms / (ev.web.length + 1)) * (i + 1), () => {
            badges.insertAdjacentHTML('beforeend', `<i style="left:${i * 14}px"><iconify-icon icon="${WEB[site]}" width="12" height="12"></iconify-icon></i>`);
            badges.style.width = `${20 + i * 14}px`;
          }));
        }
        wait(ev.ms, () => {
          el.className = el.className.replace('fl-step', 'fl-step is-muted');
          const thumb = ev.img ? `<img class="fl-step-thumb" src="${ev.img}" alt="" />` : '';
          el.innerHTML = `<span class="fl-obj">${ev.done}<em> · thought ${ev.thought}</em></span>${thumb}`;
          if (badges) el.appendChild(badges);
          (ev.web || []).forEach((site) => { if (!turnWeb.includes(site)) turnWeb.push(site); });
          if (ev.img) turnImgs.push(ev.img);
          request();
          wait(260, next);
        });
      },
      tool(ev, next) {
        const icon = `<iconify-icon class="fl-step-icon" icon="${ev.icon}" width="13" height="13"></iconify-icon>`;
        const el = put(make('div', 'fl-step', `${icon}<span class="fl-shimmer">${ev.run} ${esc(ev.obj)}</span>`));
        wait(ev.ms, () => {
          el.innerHTML = `${icon}<span class="fl-verb">${ev.done}</span><span class="fl-obj">${esc(ev.obj)}</span>`;
          request();
          wait(260, next);
        });
      },
      agents(ev, next) {
        let left = ev.list.length;
        ev.list.forEach((a, n) => {
          const card = make('div', 'fl-agent',
            `<canvas class="fl-pixel-loader" width="28" height="28" aria-hidden="true"></canvas>` +
            `<span class="fl-agent-line"><span class="fl-agent-desc fl-shimmer">${esc(a.desc)}</span><span class="fl-agent-trail">· ${esc(a.acts[0])}</span></span>` +
            `<span class="fl-agent-time">0s</span><span class="fl-agent-model">${a.model}</span>` +
            `<span class="fl-agent-bg"><svg viewBox="0 0 24 24" width="13" height="13"><path fill="currentColor" d="M7 9v6H4l4 5l4-5H9V9c0-1.65 1.35-3 3-3h8V4h-8C9.24 4 7 6.24 7 9"/></svg>Background</span>` +
            `<iconify-icon class="fl-agent-stop" icon="material-symbols:stop-rounded" width="15" height="15"></iconify-icon>` +
            `<iconify-icon class="fl-agent-chev" icon="material-symbols:chevron-right-rounded" width="17" height="17"></iconify-icon>`);
          later(n * 500, () => {
            put(card);
            const canvas = card.querySelector('canvas');
            const trail = card.querySelector('.fl-agent-trail');
            const time = card.querySelector('.fl-agent-time');
            let tick = 0;
            let flip = 0;
            if (!instant) {
              pixelCanvases.push(canvas);
              drawPixelLoader(canvas, 0);
              let sec = 0;
              let act = 0;
              tick = setInterval(() => {
                if (!alive) { clearInterval(tick); clearInterval(flip); return; }
                if (!canPlay(key)) return;
                sec += 1;
                time.textContent = `${sec}s`;
              }, 1000 * PACE);
              flip = setInterval(() => {
                if (!canPlay(key)) return;
                act = (act + 1) % a.acts.length;
                trail.classList.add('is-out');
                setTimeout(() => { trail.textContent = `· ${a.acts[act]}`; trail.classList.remove('is-out'); }, 150);
              }, (a.ms * PACE) / (a.acts.length + 0.5));
            }
            wait(a.ms, () => {
              clearInterval(tick);
              clearInterval(flip);
              const at = pixelCanvases.indexOf(canvas);
              if (at >= 0) pixelCanvases.splice(at, 1);
              card.classList.add('is-done');
              canvas.outerHTML = okIcon;
              card.querySelector('.fl-agent-desc').classList.remove('fl-shimmer');
              trail.textContent = `· ${a.type} · ${Math.round(a.ms / 120)}s · ${a.tools} tools · ${a.tokens} tokens`;
              card.querySelectorAll('.fl-agent-time, .fl-agent-bg, .fl-agent-stop').forEach((el) => el.remove());
              request();
              left -= 1;
              if (left === 0) wait(300, next);
            });
          });
        });
      },
      plan(ev, next) {
        const card = put(make('div', 'fl-plancard',
          `<div class="fl-plancard-head"><iconify-icon icon="material-symbols:checklist-rounded" width="15" height="15"></iconify-icon><span>${esc(ev.title)}</span></div>` +
          `<ol class="fl-plancard-body"></ol>`));
        const body = card.querySelector('.fl-plancard-body');
        let i = 0;
        (function line() {
          if (i >= ev.lines.length) {
            if (instant) { card.classList.add('is-approved'); next(); return; }
            const bar = make('div', 'fl-plancard-start',
              '<span class="fl-pill"><iconify-icon icon="simple-icons:claude" width="11" height="11" style="color:#d97757"></iconify-icon> Opus 5.5 <iconify-icon icon="codicon:chevron-down" width="11" height="11"></iconify-icon></span>' +
              '<button class="fl-panel-btn is-primary" type="button">Start</button>');
            card.appendChild(bar);
            follow();
            wait(1100, () => {
              bar.querySelector('button').classList.add('is-pressed');
              wait(200, () => {
                bar.remove();
                card.classList.add('is-approved');
                wait(200, next);
              });
            });
            return;
          }
          const li = make('li', '');
          body.appendChild(li);
          stream(li, ev.lines[i], () => { i += 1; wait(60, line); }, true);
        })();
      },
      todo(ev, next) {
        put(make('div', 'fl-step',
          `<iconify-icon class="fl-step-icon" icon="ri:progress-4-line" width="13" height="13"></iconify-icon><span class="fl-verb">Todos ${ev.done}/${ev.total}</span><span class="fl-obj">${esc(ev.obj)}</span>`));
        wait(450, next);
      },
      edit(ev, next) {
        const el = put(make('div', 'fl-step', `<span class="fl-shimmer">Editing ${ev.file}</span>`));
        wait(ev.ms, () => {
          el.innerHTML = `<span class="fl-verb">Edited</span><span class="fl-obj">${ev.file}</span><span class="fl-add">+${ev.add}</span>${ev.del ? `<span class="fl-del">-${ev.del}</span>` : ''}`;
          edited(ev.file, ev.add, ev.del);
          request();
          wait(260, next);
        });
      },
      cmd(ev, next) {
        const wrap = put(make('div', 'fl-cmd',
          `<div class="fl-step"><span class="fl-shimmer">Running ${esc(ev.cmd)}</span></div>` +
          `<div class="fl-step-body"><div><span class="fl-sh-dollar">$ </span>${esc(ev.cmd)}</div></div>`));
        const head = wrap.firstElementChild;
        const out = wrap.lastElementChild;
        const failed = ev.out.some((l) => /\[E\]|-\d+:/.test(l));
        fx(ev, 'start');
        ev.out.forEach((line, i) => later(((ev.ms - 200) / ev.out.length) * (i + 1), () => {
          const cls = /passed|^\d+$|^✓/.test(line) ? ' is-ok' : /\[E\]|Expected/.test(line) ? ' is-err' : '';
          out.insertAdjacentHTML('beforeend', `<div class="fl-sh-out${cls}">${esc(line)}</div>`);
          if (!instant) follow();
        }));
        wait(ev.ms, () => {
          head.innerHTML = `<span class="fl-verb">Ran</span><span class="fl-obj">${esc(ev.cmd)}</span>${failed ? '<span class="fl-del">exit 1</span>' : ''}${chev.replace('fl-step-chev', 'fl-step-chev is-open')}`;
          fx(ev, 'done');
          request();
          wait(320, next);
        });
      },
      prose(ev, next) {
        const el = put(make('div', 'fl-prose', ''), ev.final);
        stream(el, ev.text, () => wait(400, () => { request(); next(); }));
      },
      end(ev, next) {
        setWorking(false);
        const work = turn.work;
        const files = turnEdits.files.size;
        const fold = make('div', 'fl-step fl-work-fold is-live',
          `<span class="fl-obj">Worked for ${ev.worked}${files ? `<em> · ${files} file${files > 1 ? 's' : ''}</em>` : ''}</span>` +
          (turnEdits.add ? `<span class="fl-add">+${turnEdits.add}</span>` : '') +
          (turnEdits.del ? `<span class="fl-del">-${turnEdits.del}</span>` : '') + foldTrailing() + chev);
        if (instant) {
          fold.classList.remove('is-live');
          work.replaceWith(fold);
          next();
          return;
        }
        work.style.height = `${work.offsetHeight}px`;
        requestAnimationFrame(() => {
          work.classList.add('is-folding');
          work.style.height = '0px';
        });
        setTimeout(() => {
          work.querySelectorAll('canvas').forEach((c) => {
            const at = pixelCanvases.indexOf(c);
            if (at >= 0) pixelCanvases.splice(at, 1);
          });
          if (!alive) return;
          work.replaceWith(fold);
          follow();
        }, 320);
        wait(2200, next);
      }
    };

    function advance() {
      const script = turns[turnIdx];
      const ev = script[evIdx];
      evIdx += 1;
      if (evIdx >= script.length) {
        evIdx = 0;
        turnIdx = (turnIdx + 1) % turns.length;
        if (turnIdx === 0) totals = { ...base, seen: new Set() };
      }
      return ev;
    }

    function next() {
      const ev = advance();
      PLAY[ev.k](ev, next);
    }

    // Opens on a turn well under way: its first items already done.
    instant = true;
    for (let n = 0; n < (shot?.[key] ?? prefill); n++) {
      const ev = advance();
      PLAY[ev.k](ev, () => {});
    }
    instant = false;
    // Between turns, nothing is at work.
    setWorking(evIdx !== 0);
    setTotals();
    feed.scrollTop = feed.scrollHeight;
    const handle = { stop() { alive = false; } };
    if (reducedMotion || shot) return handle;
    wait(500, next);
    return handle;
  }

  // ===== Demos: the tabs above the window, each a scene of its own =====
  const usageWin = document.querySelector('.win-mode-usage');
  const usageFeed = usageWin?.querySelector('.fl-island-card .fl-chat-feed');
  const sbList = usageWin?.querySelector('.fl-sb-list');
  const sbOriginal = sbList?.innerHTML || '';
  const cardTitle = usageWin?.querySelector('.fl-card-title');
  const goalPanel = usageWin?.querySelector('[data-goal-panel]');
  const composerInput = usageWin?.querySelector('.fl-composer-input');
  const composerOriginal = composerInput?.innerHTML || '';
  const modelPill = usageWin?.querySelectorAll('.fl-pickers .fl-pill')[2];
  const modelPillOriginal = modelPill?.innerHTML || '';
  const sideCol = usageWin?.querySelector('.fl-sidepanel-col');
  const sideTabs = sideCol?.querySelector('.fl-island-tabs');
  const caret = '<i class="fl-caret"></i>';
  const micon = (name) => `<iconify-icon icon="material-icon-theme:${name}" width="14" height="14"></iconify-icon>`;

  // --- The side panel's other faces ---
  const SHOP = `
    <div class="shop">
      <div class="shop-top"><b>acme</b><span>Cart <i>›</i> Shipping <i>›</i> <u>Payment</u></span></div>
      <div class="shop-items">
        <div class="shop-item"><i style="background:linear-gradient(135deg,#f6b26b,#e06666)"></i><div><b>Trail Runner 2</b><span>Size 42 · Ember</span></div><em>$129.00</em></div>
        <div class="shop-item"><i style="background:linear-gradient(135deg,#6fa8dc,#3d6fc6)"></i><div><b>Merino Crew Socks</b><span>2 pairs</span></div><em>$24.00</em></div>
        <div class="shop-item"><i style="background:linear-gradient(135deg,#93c47d,#38761d)"></i><div><b>Trail Bottle 750 ml</b><span>Moss</span></div><em>$18.00</em></div>
      </div>
      <div class="shop-sum" data-b="summary">
        <div class="shop-row"><span>Subtotal</span><b>$171.00</b></div>
        <div class="shop-coupon"><div class="shop-input" data-b="coupon"><span class="shop-val"></span><span class="shop-ph">Coupon code</span></div><button type="button" data-b="apply">Apply</button></div>
        <div class="shop-row shop-disc"><span>SPRING25</span><b>−$42.75</b></div>
        <div class="shop-row shop-total"><span>Total</span><b class="shop-tot">$171.00</b></div>
      </div>
      <div class="shop-pay">
        <div class="shop-input" data-b="card"><iconify-icon icon="lucide:credit-card" width="13" height="13"></iconify-icon><span class="shop-val"></span><span class="shop-ph">Card number</span></div>
        <button type="button" data-b="pay">Pay now</button>
      </div>
      <div class="shop-done"><iconify-icon icon="lucide:circle-check" width="30" height="30"></iconify-icon><b>Order #10482 confirmed</b><span>Receipt sent to you@acme.dev</span></div>
    </div>`;

  const UPSTREAMS = [
    { id: 'claude', icon: 'simple-icons:claude', color: '#d97757', name: 'Claude Code (this machine’s setup)', badge: 'Built-in', sub: 'Your own login and settings, nothing changed' },
    { id: 'corp', icon: 'lucide:building-2', color: 'var(--x-corp, #c9c7bf)', name: 'corp-gateway', sub: 'OpenAI Responses · llm.corp.internal · 3 models' },
    { id: 'deepseek', icon: 'simple-icons:deepseek', color: '#5b7bff', name: 'DeepSeek', sub: 'Anthropic Messages · api.deepseek.com · 2 models' },
    { id: 'gemini', icon: 'simple-icons:googlegemini', color: '#8ab4ff', name: 'Antigravity', sub: 'Google account · 4 models' },
    { id: 'codex', icon: 'simple-icons:openai', color: 'var(--x-codex, #e8e7e2)', name: 'Codex', sub: 'ChatGPT account · 3 models' },
    { id: 'openrouter', icon: 'simple-icons:openrouter', color: '#a3a8ff', name: 'OpenRouter', sub: 'OpenAI Chat Completions · 12 models' }
  ];

  sideCol?.querySelector('.fl-usage-panel')?.classList.add('fl-sp-pane');
  sideCol?.querySelector('.fl-usage-panel')?.setAttribute('data-pane', 'usage');
  sideCol?.insertAdjacentHTML('beforeend', `
    <div class="fl-island-card fl-sp-pane fl-term-pane" data-pane="terminal">
      <div class="fl-term-head"><span class="fl-term-tab"><iconify-icon icon="codicon:terminal" width="12" height="12"></iconify-icon><span class="fl-term-name"></span></span><span class="fl-term-host"></span></div>
      <div class="fl-term-body"></div>
    </div>
    <div class="fl-island-card fl-sp-pane fl-files-pane" data-pane="files">
      <div class="fl-ft">
        <div class="fl-ft-row is-dir"><iconify-icon class="fl-ft-chev" icon="codicon:chevron-down" width="12" height="12"></iconify-icon>${micon('folder-images-open')}<span>store</span></div>
        <div class="fl-ft-store"></div>
        <div class="fl-ft-row is-dir"><iconify-icon class="fl-ft-chev" icon="codicon:chevron-down" width="12" height="12"></iconify-icon>${micon('folder-docs-open')}<span>docs</span></div>
        <div class="fl-ft-row is-file">${micon('markdown')}<span>art-direction.md</span></div>
        <div class="fl-ft-row is-dir"><iconify-icon class="fl-ft-chev" icon="codicon:chevron-right" width="12" height="12"></iconify-icon>${micon('folder-src')}<span>src</span></div>
        <div class="fl-ft-row is-dir"><iconify-icon class="fl-ft-chev" icon="codicon:chevron-right" width="12" height="12"></iconify-icon>${micon('folder-resource')}<span>assets</span></div>
        <div class="fl-ft-row is-file is-top">${micon('nodejs')}<span>package.json</span></div>
      </div>
      <div class="fl-ft-preview"><div class="fl-ft-img"></div><div class="fl-ft-cap"></div></div>
    </div>
    <div class="fl-sp-pane fl-chrome" data-pane="browser">
      <div class="fl-cr-tabs">
        <span class="fl-cr-group">BaoCode</span>
        <span class="fl-cr-tab is-active"><i class="fl-cr-fav"></i><span class="fl-cr-title">New Tab</span><iconify-icon icon="codicon:close" width="10" height="10"></iconify-icon></span>
        <span class="fl-cr-tab"><iconify-icon icon="simple-icons:github" width="11" height="11"></iconify-icon><span>acme/shop</span></span>
        <iconify-icon class="fl-cr-new" icon="codicon:add" width="12" height="12"></iconify-icon>
      </div>
      <div class="fl-cr-bar">
        <iconify-icon icon="codicon:arrow-left" width="13" height="13"></iconify-icon>
        <iconify-icon icon="codicon:arrow-right" width="13" height="13"></iconify-icon>
        <iconify-icon class="fl-cr-reload" icon="codicon:refresh" width="13" height="13"></iconify-icon>
        <div class="fl-cr-url"><iconify-icon icon="codicon:lock" width="11" height="11"></iconify-icon><span class="fl-cr-addr"></span></div>
        <img class="fl-cr-ext" src="/assets/app_icon.png" alt="" />
      </div>
      <div class="fl-cr-page">
        ${SHOP}
        <div class="fl-cr-hl"><span></span></div>
        <div class="fl-cr-scan"></div>
        <div class="fl-cr-perf"><div class="fl-cr-perf-head"><b>Performance</b><span class="fl-cr-perf-sum"></span></div><div class="fl-cr-perf-track"></div></div>
        <div class="fl-cr-cursor"><svg viewBox="0 0 20 20" width="18" height="18"><path d="M3 2l13 7.2-5.6 1.4L8 16.4z" fill="#e5ba7d" stroke="#2a2213" stroke-width="1.2" stroke-linejoin="round"/></svg><i></i></div>
      </div>
    </div>
    <div class="fl-island-card fl-sp-pane fl-models-pane" data-pane="models">
      <div class="fl-mp-head"><iconify-icon icon="codicon:settings-gear" width="13" height="13"></iconify-icon><span>Settings</span><iconify-icon icon="codicon:chevron-right" width="11" height="11"></iconify-icon><b>Models</b></div>
      <div class="fl-mp-sec"><span>Default Model for New Sessions</span><span class="fl-mp-select">Last picked<iconify-icon icon="codicon:chevron-down" width="11" height="11"></iconify-icon></span></div>
      <div class="fl-mp-label"><span>Upstreams</span><span class="fl-mp-add"><iconify-icon icon="codicon:add" width="11" height="11"></iconify-icon>Add Upstream</span></div>
      <div class="fl-mp-list">${UPSTREAMS.map((u) => `
        <div class="fl-mp-row" data-up="${u.id}">
          <span class="fl-mp-logo"><iconify-icon icon="${u.icon}" width="15" height="15" style="color:${u.color}"></iconify-icon></span>
          <span class="fl-mp-main"><b>${u.name}${u.badge ? `<em>${u.badge}</em>` : ''}</b><span>${u.sub}</span></span>
          <span class="fl-mp-use"></span>
          <i class="fl-mp-toggle"></i>
        </div>`).join('')}
      </div>
      <div class="fl-mp-note"><iconify-icon icon="codicon:shield" width="12" height="12"></iconify-icon>Other protocols go through a local proxy, translated to Claude Messages; ~/.claude is never touched.</div>
    </div>`);

  // Windows' caption buttons, for the Windows scene.
  usageWin?.insertAdjacentHTML('beforeend',
    '<div class="fl-wincaps" aria-hidden="true"><span><iconify-icon icon="codicon:chrome-minimize" width="14" height="14"></iconify-icon></span><span><iconify-icon icon="codicon:chrome-maximize" width="13" height="13"></iconify-icon></span><span class="is-close"><iconify-icon icon="codicon:chrome-close" width="14" height="14"></iconify-icon></span></div>');

  const pane = (name) => sideCol?.querySelector(`[data-pane="${name}"]`);

  function showPane(name) {
    sideCol?.querySelectorAll('.fl-sp-pane').forEach((el) => el.classList.toggle('is-shown', el.dataset.pane === name));
    // The tabbed card for its own faces; Chrome and Settings are windows of their own.
    const tabbed = ['usage', 'terminal', 'files'].includes(name);
    sideCol?.classList.toggle('is-bare', !tabbed);
    const which = { files: 0, terminal: 2, usage: 3 }[name];
    sideTabs?.querySelectorAll('.fl-itab').forEach((tab, i) => tab.classList.toggle('is-active', i === which));
  }

  // --- Terminal ---
  const term = {
    body: () => pane('terminal')?.querySelector('.fl-term-body'),
    prompt: '',
    reset(cfg) {
      const p = pane('terminal');
      if (!p) return;
      p.querySelector('.fl-term-name').textContent = cfg.shell;
      p.querySelector('.fl-term-host').textContent = cfg.where;
      this.prompt = cfg.prompt;
      // Earlier commands with their prompts as drawn; the rest as printed.
      const plain = cfg.prompt.replace(/<[^>]+>/g, '');
      this.body().innerHTML = cfg.intro.map((l, i) => l.startsWith(plain)
        ? `<div>${cfg.prompt}${esc(l.slice(plain.length))}</div>`
        : `<div class="${i === 0 ? 't-dim' : ''}">${esc(l) || '&nbsp;'}</div>`).join('') + this.promptLine();
    },
    promptLine() { return `<div class="t-line">${this.prompt}<span class="t-cmd"></span><i class="t-cursor"></i></div>`; },
    run(cmd, instant) {
      const line = this.body()?.querySelector('.t-line:last-child .t-cmd');
      if (!line) return;
      if (instant) { line.textContent = cmd; return; }
      let i = 0;
      (function type() {
        line.textContent = cmd.slice(0, i);
        i += 2;
        if (i <= cmd.length + 1) setTimeout(type, 18);
      })();
    },
    print(lines) {
      const body = this.body();
      if (!body) return;
      const last = body.querySelector('.t-line:last-child');
      last?.querySelector('.t-cursor')?.remove();
      lines.forEach((l) => body.insertAdjacentHTML('beforeend', `<div class="${/^✓|passed/.test(l) ? 't-ok' : ''}">${esc(l)}</div>`));
      body.insertAdjacentHTML('beforeend', this.promptLine());
      while (body.children.length > 60) body.firstElementChild.remove();
    }
  };

  // --- Files (pictures made) ---
  const files = {
    reset() {
      const p = pane('files');
      if (!p) return;
      p.querySelector('.fl-ft-store').innerHTML = '';
      p.querySelector('.fl-ft-img').innerHTML = '';
      p.querySelector('.fl-ft-cap').textContent = '';
    },
    add(ev, instant) {
      const p = pane('files');
      if (!p) return;
      const store = p.querySelector('.fl-ft-store');
      store.querySelectorAll('.is-sel').forEach((r) => r.classList.remove('is-sel'));
      let row = store.querySelector(`[data-file="${ev.file}"]`);
      if (!row) {
        row = document.createElement('div');
        row.className = 'fl-ft-row is-file' + (instant ? '' : ' is-live');
        row.dataset.file = ev.file;
        row.innerHTML = `${micon('image')}<span>${ev.file}</span><b class="fl-git-st is-a">A</b>`;
        store.appendChild(row);
      }
      row.classList.add('is-sel');
      p.querySelector('.fl-ft-img').innerHTML = `<img src="${ev.src}" alt="" />`;
      p.querySelector('.fl-ft-cap').textContent = `store/${ev.file} · 1360 × 768`;
    }
  };

  // --- Chrome, driven ---
  const chrome = {
    el: () => pane('browser'),
    q(sel) { return this.el()?.querySelector(sel); },
    reset() {
      const c = this.el();
      if (!c) return;
      c.classList.remove('is-loaded', 'is-perf', 'is-paid', 'is-applied');
      c.querySelectorAll('.shop-val').forEach((v) => { v.textContent = ''; });
      c.querySelectorAll('.is-focus').forEach((v) => v.classList.remove('is-focus'));
      this.q('.fl-cr-title').textContent = 'New Tab';
      this.q('.fl-cr-addr').textContent = '';
      this.q('.shop-tot').textContent = '$171.00';
      this.hl(null);
      this.cursorTo(null);
    },
    at(target) {
      const page = this.q('.fl-cr-page');
      const el = target && this.q(`[data-b="${target}"]`);
      if (!page || !el) return null;
      const a = page.getBoundingClientRect();
      const b = el.getBoundingClientRect();
      return { x: b.left - a.left, y: b.top - a.top, w: b.width, h: b.height };
    },
    cursorTo(target) {
      const cur = this.q('.fl-cr-cursor');
      const r = this.at(target);
      if (!cur) return;
      if (!r) { cur.style.opacity = '0'; return; }
      cur.style.opacity = '1';
      cur.style.transform = `translate(${r.x + Math.min(r.w * 0.62, r.w - 10)}px, ${r.y + r.h * 0.55}px)`;
    },
    click() {
      const cur = this.q('.fl-cr-cursor');
      cur?.classList.remove('is-click');
      void cur?.offsetWidth;
      cur?.classList.add('is-click');
    },
    hl(target, label) {
      const hl = this.q('.fl-cr-hl');
      const r = this.at(target);
      if (!hl) return;
      if (!r) { hl.style.opacity = '0'; return; }
      Object.assign(hl.style, { opacity: '1', left: `${r.x - 3}px`, top: `${r.y - 3}px`, width: `${r.w + 6}px`, height: `${r.h + 6}px` });
      hl.querySelector('span').innerHTML = label || '';
      hl.classList.toggle('has-label', !!label);
    },
    type(target, text, instant) {
      const val = this.q(`[data-b="${target}"] .shop-val`);
      this.q(`[data-b="${target}"]`)?.classList.add('is-focus');
      if (!val) return;
      if (instant) { val.textContent = text; return; }
      let i = 0;
      (function step() {
        val.textContent = text.slice(0, ++i);
        if (i < text.length) setTimeout(step, 55);
      })();
    },
    perf(good) {
      const c = this.el();
      const track = this.q('.fl-cr-perf-track');
      if (!c || !track) return;
      const bars = good
        ? [[4, 3], [14, 2], [22, 4], [33, 2], [41, 3], [55, 2], [63, 3], [77, 2], [86, 3]]
        : [[3, 2], [9, 21], [33, 3], [38, 17], [58, 2], [62, 24], [89, 3]];
      track.innerHTML = bars.map(([l, w]) => `<i class="${!good && w > 10 ? 'is-long' : ''}" style="left:${l}%;width:${w}%"></i>`).join('');
      this.q('.fl-cr-perf-sum').textContent = good ? 'Apply coupon · no long tasks · INP 38 ms' : 'Apply coupon · 3 long tasks · INP 412 ms';
      c.classList.add('is-perf');
      c.classList.toggle('is-good', !!good);
    },
    fx(ev, phase, instant) {
      const c = this.el();
      if (!c) return;
      if (phase === 'start' && !instant) {
        if (ev.target) this.cursorTo(ev.target);
        if (ev.act === 'snapshot') { c.classList.remove('is-scan'); void c.offsetWidth; c.classList.add('is-scan'); }
        // Profiling a click: the click lands while it records.
        if (ev.act === 'perf' || ev.act === 'perf2') {
          setTimeout(() => {
            this.click();
            c.classList.add('is-applied');
            this.q('.shop-tot').textContent = '$128.25';
          }, 650);
        }
        return;
      }
      if (phase !== 'done') return;
      switch (ev.act) {
        case 'open':
          this.q('.fl-cr-addr').textContent = 'shop.local/checkout';
          this.q('.fl-cr-title').textContent = 'Checkout — Acme';
          c.classList.add('is-loaded');
          break;
        case 'click':
          this.click();
          this.q(`[data-b="${ev.target}"]`)?.classList.add('is-focus');
          if (ev.target === 'pay') this.hl(null);
          break;
        case 'type':
          this.type(ev.target, ev.text, instant);
          break;
        case 'perf':
          c.classList.add('is-applied');
          this.q('.shop-tot').textContent = '$128.25';
          this.perf(false);
          break;
        case 'inspect':
          this.hl('summary', '&lt;CartSummary&gt; · state { coupon, totals } · <b>rendered 3×</b>');
          break;
        case 'reload':
          this.hl(null);
          c.classList.remove('is-perf');
          c.classList.add('is-reload');
          setTimeout(() => c.classList.remove('is-reload'), 260);
          break;
        case 'perf2':
          this.perf(true);
          break;
        case 'paid':
          c.classList.remove('is-perf');
          c.classList.add('is-paid');
          this.cursorTo(null);
          break;
      }
    }
  };

  // --- Models (Settings → Models) ---
  const models = {
    use(id, model) {
      pane('models')?.querySelectorAll('.fl-mp-row').forEach((row) => {
        const on = row.dataset.up === id;
        row.classList.toggle('is-using', on);
        row.querySelector('.fl-mp-use').textContent = on ? 'In use' : '';
      });
      const up = UPSTREAMS.find((u) => u.id === id);
      if (modelPill && up) {
        modelPill.innerHTML = `<iconify-icon icon="${up.icon}" width="12" height="12" style="color:${up.color}"></iconify-icon> ${model} <iconify-icon icon="codicon:chevron-down" width="11" height="11"></iconify-icon>`;
        modelPill.classList.remove('is-flash');
        void modelPill.offsetWidth;
        modelPill.classList.add('is-flash');
      }
    }
  };

  // --- Sidebar: which conversation is open, and the ones handed out ---
  function syncPixelCanvases() {
    for (let i = pixelCanvases.length - 1; i >= 0; i--) if (!pixelCanvases[i].isConnected) pixelCanvases.splice(i, 1);
    document.querySelectorAll('.fl-pixel-loader').forEach((c) => {
      if (c.closest('.fl-agent') || pixelCanvases.includes(c)) return;
      c._pf = undefined;
      pixelCanvases.push(c);
      drawPixelLoader(c, 9);
    });
  }

  function hostGroup(host) {
    return Array.from(sbList?.querySelectorAll('.fl-host-group') || []).find((g) => g.querySelector('.fl-host-row span')?.textContent === host);
  }

  function openThread(host, name) {
    if (!sbList) return;
    sbList.innerHTML = sbOriginal;
    const rows = Array.from(sbList.querySelectorAll('.fl-thread-row'));
    let row = rows.find((r) => r.querySelector('span')?.textContent === name);
    const was = sbList.querySelector('.fl-thread-row.is-active');
    if (row !== was && was) {
      was.classList.remove('is-active');
      was.innerHTML = `<span>${was.querySelector('span').textContent}</span><em>now</em>`;
    }
    if (!row) {
      row = document.createElement('div');
      row.className = 'fl-thread-row';
      const group = hostGroup(host);
      group?.querySelector('.fl-host-row')?.after(row);
    }
    if (row !== was) {
      row.classList.add('is-active');
      row.innerHTML = `<canvas class="fl-pixel-loader" width="26" height="26" aria-hidden="true"></canvas><span>${esc(name)}</span><b class="fl-add">+0</b>`;
    }
    syncPixelCanvases();
  }

  function childThread(ev, done) {
    const group = hostGroup(ev.host || '');
    const name = ev.obj || ev.agent;
    let row = sbList?.querySelector(`[data-child="${name}"]`);
    if (!row && group) {
      row = document.createElement('div');
      row.className = 'fl-thread-row is-live';
      row.dataset.child = name;
      group.querySelector('.fl-host-row')?.after(row);
    }
    if (!row) return;
    row.innerHTML = done
      ? `<span>${esc(name)}</span><em>now</em>`
      : `<canvas class="fl-pixel-loader" width="26" height="26" aria-hidden="true"></canvas><span>${esc(name)}</span><em>now</em>`;
    syncPixelCanvases();
  }

  // --- The scenes ---
  const chip = (icon, label, muted) => `<span class="fl-chip">${icon}<span>${label}</span>${muted ? `<span class="fl-chip-muted">${muted}</span>` : ''}</span>`;
  const DEMOS = {
    agent: { thread: ['BaoCode', 'Multi-protocol adapter'], pane: 'usage', goal: true, base: { files: 8, add: 2911, del: 0 } },
    editor: { ide: true },
    windows: {
      os: 'win', thread: ['win-workstation', 'Slow build on Windows'], pane: 'terminal',
      term: { shell: 'bao-bash.exe', where: 'win-workstation · C:/workspace/shop', prompt: '<span class="t-path">C:/workspace/shop</span> <span class="t-dim">$</span> ', intro: ['BaoCode Bash 0.3.2 (x86_64-pc-windows-msvc) · Windows 11 Pro 24H2', '', 'C:/workspace/shop $ git pull --ff-only', 'Updating 8c41e2a..f03b7d9', 'Fast-forward', ' tools/build.mjs     | 12 +++++++-----', ' src/cart/totals.ts  |  4 ++--', ' 2 files changed, 9 insertions(+), 7 deletions(-)', 'C:/workspace/shop $ node -v && npm -v', 'v22.11.0', '10.9.0', 'C:/workspace/shop $ ls C:/workspace', 'monad  relay  shop  site'] },
      composer: `Profile the cold start too, the trace is ${chip(micon('nodejs'), 'build-trace.json')} ${caret}`
    },
    remote: {
      thread: ['prod-gpu-01', 'Migrate relay & Caddy'], pane: 'terminal',
      term: { shell: 'bash', where: 'prod-gpu-01 · Ubuntu 24.04 · SSH', prompt: '<span class="t-user">leo@prod-gpu-01</span>:<span class="t-path">/srv/relay</span>$ ', intro: ['Welcome to Ubuntu 24.04.1 LTS (GNU/Linux 6.8.0-49-generic x86_64)', '', '  System load:  0.38            Memory usage: 21%', '  Usage of /:   41.2% of 1.8TB  GPU 0: H100 80GB · 3%', '', 'Last login: Sat Nov 21 22:41:07 2026 from 10.0.0.12', 'leo@prod-gpu-01:/srv/relay$ git log --oneline -3', 'f03b7d9 relay: graceful drain on SIGTERM', '8c41e2a relay: per-client rate limit', '2d9e110 deploy: systemd unit hardening', 'leo@prod-gpu-01:/srv/relay$ ss -tlnp | grep 7443', 'LISTEN 0  4096  0.0.0.0:7443  0.0.0.0:*  users:(("relay",pid=1184))'] },
      composer: `Tail the relay log for five minutes after the switch ${caret}`
    },
    browser: {
      thread: ['BaoCode', 'Checkout stutter'], pane: 'browser',
      composer: `Then run the same flow on mobile, it should look like <span class="fl-chip is-image"><img class="fl-chip-thumb" src="/assets/mobile-2.webp" alt="" /><span>Image 1</span></span>${caret}`
    },
    api: {
      thread: ['BaoCode', 'Model pricing rules'], pane: 'models',
      composer: `Compare what the four models cost on this thread ${caret}`
    },
    image: {
      thread: ['BaoCode', 'Steam store art'], pane: 'files',
      composer: `Make a 9:16 version of both for the phone stores ${caret}`
    },
    orchestrate: {
      thread: ['BaoCode', 'Release 1.8'], pane: 'usage',
      composer: `Draft the GitHub release once all three report ${caret}`
    }
  };

  let usagePlayer = null;
  let usageDemo = null;
  let demoShown = null;

  function hooksFor(id, demo) {
    return {
      fx(ev, phase, instant) {
        // Round again: the page as it was.
        if (id === 'browser' && ev === SCRIPTS.browser.turns[0][0]) chrome.reset();
        if (demo.term && ev.k === 'cmd') {
          if (phase === 'start') term.run(ev.cmd, instant);
          else term.print(ev.out);
        }
        if (id === 'browser' && ev.k === 'browser') chrome.fx(ev, phase, instant);
        if (ev.k === 'image' && phase === 'done') files.add(ev, instant);
        if (ev.k === 'switch') models.use(ev.up, ev.model);
        if (id === 'orchestrate' && ev.k === 'session') childThread(ev, false);
        if (id === 'orchestrate' && ev.k === 'agentmsg') childThread(ev, true);
      }
    };
  }

  function stageDemo(id) {
    const demo = DEMOS[id];
    usagePlayer?.stop();
    desktopWin?.classList.toggle('is-winos', demo.os === 'win');
    openThread(demo.thread[0], demo.thread[1]);
    if (cardTitle) cardTitle.textContent = demo.thread[1];
    if (goalPanel) goalPanel.style.display = demo.goal ? '' : 'none';
    if (composerInput) composerInput.innerHTML = demo.composer || composerOriginal;
    if (modelPill) modelPill.innerHTML = modelPillOriginal;
    const base = demo.base || { files: 0, add: 0, del: 0 };
    const strip = usageWin.querySelector('.fl-activity-strip');
    strip.querySelector('.fl-strip-count').textContent = `${base.files} file${base.files === 1 ? '' : 's'} changed`;
    strip.querySelector('.fl-strip-toggle .fl-add').textContent = `+${base.add}`;
    strip.querySelector('.fl-strip-toggle .fl-del').textContent = `-${base.del}`;
    showPane(demo.pane);
    if (demo.term) term.reset(demo.term);
    if (demo.pane === 'files') files.reset();
    if (demo.pane === 'browser') chrome.reset();
    usagePlayer = startPlayback('usage', usageFeed, SCRIPTS[id], hooksFor(id, demo));
    usageDemo = id;
  }

  function showDemo(id) {
    if (!DEMOS[id]) id = 'agent';
    demoShown = id;
    document.querySelectorAll('.stage-tab').forEach((tab) => {
      const on = tab.dataset.demo === id;
      tab.classList.toggle('is-active', on);
      tab.setAttribute('aria-selected', String(on));
    });
    if (DEMOS[id].ide) { setStageMode('ide'); return; }
    if (usageDemo !== id) stageDemo(id);
    setStageMode('usage');
  }

  document.querySelectorAll('.stage-tab').forEach((tab) => {
    tab.addEventListener('click', () => showDemo(tab.dataset.demo));
  });
  startPlayback('ide', document.getElementById('ideChatFeed'), SCRIPTS.ide);
  const params = new URLSearchParams(window.location.search);
  showDemo(params.get('demo') || (params.get('mode') === 'ide' ? 'editor' : 'agent'));

  window.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
    const tab = document.querySelectorAll(".stage-tab")[Number(e.key) - 1];
    if (/^[1-8]$/.test(e.key) && tab) showDemo(tab.dataset.demo);
  });
}
})();
