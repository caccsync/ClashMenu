## v0.0.28

### ✨ 新增功能

- 设置窗口在“通用设置”和“高级操作”之间新增“代理设置”分组，提供“忽略这些主机/域的代理”可编辑配置
- 系统代理 helper 现在会同步写入并校验 macOS 代理例外列表（ExceptionsList）

### 🚀 优化改进

- “忽略这些主机/域的代理”改为多行滚动文本输入，窗口尺寸同步放宽，便于查看和编辑较长列表
- 默认代理例外列表更新为：`localhost,127.0.0.1,*.local,10/8,169.254/16,172.16/12,192.168/16,apple.com,*.apple.com`
- 本地打包版本已推进到 `0.0.28`

### 🐞 修复问题

- 修复特权 helper 的 launchd 注册方式，改用绝对路径 `ProgramArguments`，避免重启后因相对路径记录导致 `spawn failed / EX_CONFIG`
- 为应用退出阶段补充同步关闭系统代理的兜底逻辑，减少非菜单退出路径下残留系统代理的概率
- 修复系统代理 helper 的 XPC 接口，补齐 `bypassHosts` 数组参数的解码声明，避免新增代理例外列表参数后消息被 NSXPC 丢弃

### 📝 排查备注

- 如果更新后仍然看到旧的 `com.clashmenu.helper` XPC 解码错误，需要退出 ClashMenu 并执行 `sudo launchctl bootout system/com.clashmenu.helper`，再重新打开 `/Applications/ClashMenu.app` 让新 helper 生效

## v0.0.22

### ✨ 新增功能

- 在“通用设置”中新增“恢复确认延迟（秒）”，统一控制网络恢复和系统唤醒后的自动恢复确认等待时间，默认值为 3 秒

### 🚀 优化改进

- 菜单栏图标支持根据 Mihomo 运行中/已停止状态切换自定义品牌图标，并保持系统模板渲染与多显示器菜单栏的原生变暗效果
- 调整“关于”弹窗信息布局，按“ClashMenu 版本 / Mihomo 版本 / 空行 / Copyright”展示

## v0.1.5

### 🐞 修复问题

- 修复 macOS 13 Intel 平台下的兼容性问题，提升应用在旧版 Intel 设备上的启动与界面稳定性

<details>
<summary><strong> ✨ 新增功能 </strong></summary>

- 新增无内核版本的 ClashBar 安装包，支持按需分发不内置 Mihomo 内核的应用版本
- 支持在未内置核心组件时提供首次启动引导，方便用户手动安装和配置 Mihomo 内核

</details>

<details>
<summary><strong> 🚀 优化改进 </strong></summary>

- 优化未内置内核场景下的启动流程，缺少托管内核时将延后自动启动并提供更清晰的提示信息
- 调整启动失败与 TUN 相关错误提示文案，帮助用户更快定位和处理手动安装内核后的运行问题
- 优化打包与发布流程，适配新的安装包结构并同步更新相关资源与文档

</details>
