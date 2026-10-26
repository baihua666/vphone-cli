# vphone-cli

## 镜像禁止上传与本地目录管理（2026-10-26）

- 用户明确禁止上传虚拟 iPhone 镜像及分片，包括通过发布脚本、CI、gh、网盘或手工上传。镜像只在线下由用户管理，从本地目录读取和更新。
- App 发布只包含 Launchpad、必要的 Core 和发行清单；`images` 与 `previousTags` 必须为空，不为了自包含发行目录重新上传镜像，也不引用历史发行来恢复在线镜像流程。
- 本地镜像目录独立管理版本、完整归档及校验元数据。刷新目录或更新模板不能覆盖已有 VM，不自动升级 Core 或 guest，不复制大文件到下载缓存。
- 本规则覆盖旧文档中“每个 Release 自带完整镜像”“上传镜像分片”的相反要求。历史已发布附件的删除需明确授权，不能因本规则擅自删除历史发布。
- 发布器和上传脚本须在网络上传前拒绝镜像及未登记附件；这不等于全局工具层已经拦截任意手工上传。

Virtual iPhone boot tool using Apple's Virtualization.framework with PCC research VMs.

## Monorepo development

- 版本声明与本地构建命名必须遵守下方「官方基线版本与本地标识」规范。
- Before cross-layer work, read `Documents/Guides/architecture-boundaries.md`: Views own presentation, VPhoneWSCore owns business orchestration/adapters, CLI exposes reusable operations, and existing kits own shared rules. VPN provider integration is not VM networking; do not duplicate either in Views.
- Resolve the same per-machine pinned runtime and library context for every operation. Treat legacy stop/probe and creation flows as documented migration gaps, not patterns to copy. Use the root CodeGraph index; cross-process contracts also require explicit tests.
- This fork develops Workstation GUI and the native CLI together on `tb_dev`. The GUI lives in `VPhoneWorkstation/`; edit it here, not in the old sibling checkout.
- Use `scripts/dev.sh build|test [gui|cli|all]`. `test cli` runs CoreKit tests; also run owning target tests for specific CLI changes. The imported GUI keeps its existing SwiftPM build; do not change the CLI's Xcode architecture.
- Product direction is GUI → native CLI → VM/guest. Keep firmware, restore and installation logic in the CLI. Existing GUI creation options are not yet fully adapted to CLI 2.x.
- `workstation.command` uses the in-repository GUI with the existing pinned runtime configuration. Building is not deploying: do not replace pinned hosts, VM data or proxy-path settings as part of routine development.
- CLI updates merge from `upstream/main`; GUI updates use `git subtree pull --prefix=VPhoneWorkstation workstation-upstream main`. Keep `main` as the CLI upstream baseline. See `Documents/Guides/monorepo-development.md`.

## 官方基线版本与本地标识

2026-10-22 用户明确要求：

- Core Bundle 与 Launchpad 的产品版本号必须使用实际合入的官方基线版本。例如 `2.8.0` 表示基于官方 2.8.0 修改，属于不可由本地开发改动的基线标识；本地新增功能、修复、重构或构建都不得修改其 major/minor/patch，也不得借用尚未合入的官方新版本号。
- 只有实际同步并核对了新的官方代码基线，才随该基线采用对应的官方版本号；同时记录官方 commit SHA 与本地改动，不能仅凭官方发布了新版就改版本声明。
- 必须保留官方本地构建身份机制 `<官方版本>-local.<内容哈希>`，不得用时间、`test`、流水号或人工名称替代、删去或伪造内容哈希。官方实现取包内签名 seal（`Contents/_CodeSignature/CodeResources`）的 SHA-256 前 8 位；缺少 seal 时沿用官方归档 SHA-256 回退。同一包重复安装应保持同一身份，不能仅因安装时间变化生成另一身份。
- `test`、构建时间和用户发布确认属于附加信息，不能替代官方版本或内容哈希。AI 自行创建且未经用户明确确认发布的产物默认标记为测试，测试通过不等于获准发布。优先在产物说明或展示标签中记录，例如核心身份 `2.8.0-local.199abaf3`、附加标签 `test / 2026-10-22 22:30 北京时间`；若以后扩展机器可解析的版本字符串，必须同时保留官方基线及内容哈希，并先实现安装器、版本解析与实例绑定兼容测试。当前仍沿用官方字符串格式，未实现自动追加 `test` 或时间。
- 下文上游 minor/series 规则描述官方升级契约，不授权本地另起版本系列。本地可选扩展通过能力探测和明确的缺能力错误保持兼容；Helper 的独立内部构建号仍按既有安装校验规则维护，不用它冒充官方产品版本。
- 已安装的历史错误命名不得直接改目录、receipt 或 VM 绑定来伪装修正；应后续按正确官方基线重新构建、安装并单独迁移验收。历史研究记录保留当时真实包名，注明错误命名，避免丢失追溯关系。

## Launchpad 业务优先与底层修改确认（2026-10-23）

- 应用管理、在线服务接入、下载、安装编排、业务状态及验收流程优先在 Launchpad 和 `Integrations/<Feature>/` 实现；先复用现有 CLI／HTTP／RPC 能力，尽量避免修改 CLI、Core Bundle、VM 宿主、guest、固件及 helper。
- 开发新业务不能默认要求升级实例绑定的 Core。保持每台实例原 library 与 pinned bundle；不因管理界面新增功能自动迁移运行时或更新 guest 环境。
- 确实缺少必要底层能力时，实施前必须向用户说明现有接口为何不足、尝试过的复用方案、最小修改范围、兼容与部署影响，并取得用户明确确认。一般性的“实现功能／继续／部署”不等于同意修改底层。
- 未获确认时继续完成可独立完成的 Launchpad 工作，明确报告缺失能力，不以动态注入、协议绕过或新增替代 CLI 规避确认。用户明确要求撤销本次底层改动时，可撤销本任务自身的改动，不触碰其它改动。
- 本规则是开发行为约束，不表示已实现自动拦截。

## Business customization boundaries

- 2026-10-23 用户要求：所有本地定制能力和实验功能（包括 Apple Wallet／Apple Pay／NFC／SE 相关实现）必须使用具名编译宏／Swift 编译条件控制，不能只加注释或运行时布尔值。定制用 `VPHONE_CUSTOM_<FEATURE>`，实验用 `VPHONE_EXPERIMENTAL_<FEATURE>`；可独立回退的功能分别命名，不借用 `DEBUG` 一次开启全部实验。实验默认关闭，启用须显式声明。
- 宏定义在所属 target 的既有构建配置中集中维护；实现隔离在独立目录／模块，上游入口只保留窄的条件组装点。关闭宏必须使该功能入口、注册、后台任务及副作用不可达，并恢复基础路径；删除功能时应能一并删除隔离实现、组装点与宏定义，不留下伪成功占位实现。跨 target／进程的定义与能力检测须一致，不能假定 Swift 条件会自动传给 C 或另一个 package。
- 实现或改造定制功能必须验证开启／关闭两种构建与相关行为，记录宏名、定义位置、默认值、影响范围和删除／回退步骤。已有定制未逐项完成宏改造时必须明确列为未覆盖，不得仅因更新规范就宣称已经隔离；纯离线研究报告不需要创建未使用的产品宏。
- 编译宏不能自动撤销已安装的 guest／内核／DSC／固件补丁或已写入的数据。补丁还须保留 patch-set／preset 开关，并记录原始输入恢复、重新生成／部署和验收办法；不得把关闭宿主宏冒充现有系统已回退。具体语言及构建接入见 [定制与实验功能的编译开关](Documents/Guides/architecture-boundaries.md#定制与实验功能的编译开关)。
- 业务定制必须以减少上游升级和合并成本为目标。优先复用已有插件/扩展入口、依赖注入或独立业务模块；没有现成扩展机制时，先采用独立目录/文件和一个窄的组装入口，不为单个需求创建通用插件平台。
- 通用核心只承载与业务无关的原子能力和公共规则。业务默认值、流程顺序、验收时长、供应商策略及业务数据放在业务模块；不因“多处可调用”就把业务编排放进 CoreKit、guest 或 privileged helper。
- 新增业务模块与测试优先放在 `Integrations/<Feature>/`，实际有跨 target 复用需求时再建立独立 library；小型单 target 定制可先使用清晰隔离的业务目录。上游拥有的入口只保留必要的组装/适配代码，依赖方向为业务模块 → 通用接口，核心不得反向依赖业务模块。
- 业务流程通过明确的扩展点接入。启用定制时保持用户要求的行为；未启用时保留基础产品路径。业务功能缺失或不兼容时给出该功能的具体失败，不应仅为可选定制扩大到全局 runtime 拒绝或迫使所有已有实例升级。真正修改公共 CLI/协议/布局时仍遵守本项目既有版本系列规则。
- 复用实例的 library 与 pinned bundle。业务配置和状态由业务模块独立维护，不向 VM manifest、guest 协议或 helper 添加供应商/业务字段；底层确实缺少通用能力时，单独说明最小新增接口及其兼容影响。
- 评审需列明：通用能力与业务策略的划分、触及的上游文件和必要性、停用定制后的基础行为、升级/合并影响，以及能力缺失、独立重试和真实环境验证。不得以动态注入绕过签名、helper 校验、权限边界或飞书禁令。
- 详细维护规则及设备初始化案例见 [业务定制隔离](Documents/Guides/architecture-boundaries.md#业务定制隔离)。这些是开发约束，不代表已经实现插件系统或工具层隔离。

## FLYWHEEL business integration

- Launchpad is the management entry for the FLYWHEEL integration. The related backend repository is `/Users/tubao/code/private/flywheel/JeecgBoot_flywheel`; this path is a local source reference, never a build or runtime dependency.
- Before integration work, read [FLYWHEEL integration boundaries](Documents/Guides/flywheel-integration.md) and the other repository's `AGENTS.md`. Keep the repositories, build systems and release processes independent.
- Keep FLYWHEEL client/business code in the independent `Integrations/Flywheel/` library and tests, outside upstream-owned VM/CLI/guest code and the Workstation subtree. Launchpad owns only UI composition and the adapter to existing machine operations.
- Do not add FLYWHEEL fields to VM manifests, `launchpad.json`, firmware, daemon or privileged helper protocols. Reuse existing machine operations with the selected machine's library and pinned bundle.
- Scope expanded on 2026-10-22: local business device CRUD in Launchpad, using an independent SwiftData store for numeric device numbers, regions, notes and platform references. Reuse platform names and start/stop operations. Deleting a business record must never delete the VM. Backend APIs, remote synchronization and business task execution remain deferred.
- FLYWHEEL opens in a separate single-instance native window. Do not replace the platform main page. Repeated entry clicks focus the existing business window; platform actions open/focus the main window and select the machine. Keep business window composition under `Flywheel/` and share the existing platform model.

- FLYWHEEL lifecycle regression is mandatory for association/list/persistence changes: test rename, delete, both clone modes, clone-then-delete-source, same-name replacement, explicit clone binding and database reopen. See the lifecycle matrix in `Documents/Guides/flywheel-integration.md`. Never infer identity from UDID alone (ordinary clones retain it); use local directory identity, and require explicit confirmation for legacy references without it. Platform deletion must retain business metadata and disable unresolved actions. Tests must use isolated stores/directories, never delete user VMs. Debug deployment must include the app's debug dylib as well as its launcher executable.

## Quick Reference

- **Build:** `xcodebuild -workspace VPhone.xcworkspace -scheme VPhone -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/XcodeBundle build`
- **Test:** Run the Xcode test schemes in their owning projects. The `VPhone` build validates the finished bundle.
- **Boot (GUI):** `vphone-cli vm launch <name>`
- **Boot (DFU):** `vphone-cli vm launch <name> --dfu`
- **AMFI refuses `vphone-vm`?** Launchpad uses its SMJobBless helper to run the installed bundle's `vphone-escalator` after checking its receipt. Standalone CLI users can run the allowlist tool as shown in `Documents/Guides/host-setup.md`. Repeat after the VM cdhash changes.
- **Restore:** `vphone-cli restore` runs in process over the vendored recovery and restore C modules in `VPhoneExecutable/VPhoneCommand/VPhoneRestore`.
- **Platform:** macOS 15+ (Sequoia). `vphone-vm` needs amfid to accept its private entitlements: either SIP off with `amfi_get_out_of_my_way=1`, or SIP on (`--without debug`) plus an allowlist bypass. Both are in `Documents/Guides/host-setup.md`. Launchpad's bundle preflight checks SIP and Research Guests and applies the allowlist through its installed helper.
- **Language:** Swift 6.0 in handwritten Xcode projects, private APIs via [Dynamic](https://github.com/mhdhejazi/Dynamic).
- **Dependencies:** Host and guest SwiftPM packages resolve dependencies by URL and version; `Package.resolved` pins the full graphs. There are no git submodules. **No Python anywhere, and no Homebrew package at runtime** — see Tiers below.
- **Installing an app on a guest: not `devicectl`.** `xcrun devicectl device install app` / `process launch` time out against vphone guests; do not use them. To go through installd (the path Xcode takes, and the only one that exercises the install-gate hooks), use `ideviceinstaller -u <UDID> install <ipa>`. vphoned's `apps.install` bypasses installd — it re-signs and places the bundle itself — so it proves nothing about installd. Launch with the `apps.launch` RPC.
- **Tiers.** The build machine may use Xcode and build tools. The shipped `VPhone.bundle` must use only system libraries and its own contents at runtime. Guest components run inside the VM. `Build/ValidateBundle.sh` checks bundle admission as part of the `VPhone` build.

## Workflow Rules

- Do not create, read, or update `/TODO.md`.
- Ignore `/TODO.md` if it exists locally; it is intentionally not part of the repo workflow anymore.
- Track plan, progress, assumptions, blockers, and next actions in commit history, code comments when warranted, and current research docs instead of a repo TODO file.

For any changes applying new patches, also update Research/0_binary_patch_comparison.md. Dont forget this.

## Local Skills

- For this fork, read `skills/vphone-development/SKILL.md` first. Current sync and runtime boundaries are in `Research/branch_workflow.md`; incident history is in `Research/debug_journal.md`.
- Existing `scripts/ad_test_trace.py` and its tests are host-side research tools retained from the business branch. They are not shipped in VPhone.bundle. The upstream no-Python rule below applies to product code; do not add an interpreter to the product or revive the removed Python firmware pipeline.

- If working on kernel analysis, symbolication lookups, or kernel patch reasoning, read `Skills/kernel-analysis-vphone600/SKILL.md` first.
- Use this skill as the default procedure for `vphone600` kernel work.
- If adding or changing a patch, a patch set, or a preset, read `Skills/authoring-patch-sets/SKILL.md` first. Every patch is declared in a patch set and selected by a preset; a patch in no manifest cannot be turned off and warns on every run.

## Firmware Mode

The public CLI exposes only JB: `vphone-cli fw patch` and `vphone-cli cfw install`.
The guest contains vphoned and required system patches; package-manager
bootstrap and first-boot installation are outside this project. Do not add
another public variant.

See `Research/` for detailed firmware pipeline, component origins, patch breakdowns, and boot flow documentation.

## Architecture

`VPhone.xcworkspace` contains handwritten Xcode projects. Do not introduce project generators, SwiftPM app targets, recovered references, or linked source folders. Source folders should carry the owning project or target name.

- `VPhoneExecutable/VPhoneVirtualization`: `VPhone.bundle`, `vphone-vm`, and `VPhoneVirtualMachineKit`. The bundle is the distributable output and has no app launcher.
- `VPhoneExecutable/VPhoneCommand`: `vphone-cli`, firmware patcher, signer, and command tests.
- `VPhoneExecutable/VPhoneCommand/VPhoneRestore`: native restore code and tests.
- `VPhoneExecutable/VPhoneEscalator`: the AMFI allowlist program, built for arm64e. It is not a general privilege service.
- `VPhoneKit`: shared core, archive, and external access kits with their tests.
- `VPhoneDaemon`: guest `vphoned`, native operations, and daemon configuration.
- `VPhoneGuestComponents`: guest dylibs built by Makefile from the bundle build phase.
- `VPhoneLaunchpad`: `vphone-launchpad.app`, the workstation app that downloads and manages `VPhone.bundle` releases and drives each VM through the `vphone-cli` of the Core Bundle that machine is bound to (`launchpad.json` in the machine folder; the default bundle only seeds new machines and library-wide commands), plus its SMJobBless helper `com.vphone.launchpad.helper`, `vphone-launchpad-cli`, a stateless client of the running app over a same-user Unix socket (`Documents/Guides/launchpad-cli.md`; use it to install and test a local `VPhone.bundle` build), and `vphone-launchpad-launcher`, the responsible process for each VM it starts. Shipped separately from the bundle. Settings live only in `VPhoneLaunchpad/Configuration/*.xcconfig`; the pbxproj holds none.

The `VPhone` scheme puts host programs in `VPhone.bundle/Contents/MacOS` and everything installed into the guest (vphoned, guest dylibs, their plists) in `Contents/Resources/guest-resources`. Xcode targets have `CODE_SIGNING_ALLOWED=NO`; the bundle build phase signs each binary ad hoc with only its own entitlements, then seals the outer bundle. `VPhoneVirtualization.entitlements` belongs to `vphone-vm`; `VPhoneDaemon.entitlements` belongs to `vphoned`. The bundle and CLI have no private entitlements.

### Key Patterns

- New machines boot **OpenAVB**, not Apple's AVPBooter: `VPhone.bundle/Contents/Resources/OpenAVB/OpenAVB.bin`, checked in prebuilt under `VPhoneExecutable/VPhoneVirtualization/Resources/OpenAVB/` from a pinned OpenAVB commit plus any patches in `patches/` beside it (none at present). Rebuild or check it only with `Build/UpdateOpenAVB.sh` (Homebrew LLVM/LLD, outside the repo). `fw patch` skips AVPBooter on an OpenAVB machine; `vphone-cli restore` uploads the iBSS identity first (`MobileRestoreCore/Recovery/openavb.c`); `vm config --rom` switches ROM. See `Research/Firmware/openavb_boot_rom.md`.
- New machines start the SEP from **OpenSEP**, not Apple's AVPSEPBooter: `VPhone.bundle/Contents/Resources/OpenSEP/OpenSEP.bin`, checked in prebuilt under `VPhoneExecutable/VPhoneVirtualization/Resources/OpenSEP/` from a pinned OpenSEP commit (`vresearch1` platform) plus any patches in `patches/` beside it. Rebuild or check it only with `Build/UpdateOpenSEP.sh`. Neither SEP ROM is patched; `vm config --seprom` switches it without a restore. See `Research/Firmware/opensep_sep_rom.md`.

- `vphone-cli` is the unentitled entry point. `VPhoneGuestLaunchPlanner` resolves `vphone-vm` beside the running executable, checks its entitlements, probes AMFI, and reports the exact allowlist command on refusal. It never obtains root itself.
- `vphone-escalator` manages AMFI cdhash admission only. It writes amfid heap state, not executable code. Root authorization belongs to the user or to `vphone-launchpad`; neither `vphone-cli` nor the bundle has an SMJobBless or sudo password flow.
- `vphone-launchpad` has no private entitlements. `SignLaunchpad.sh` gives its main executable two hardened-runtime resource entitlements, microphone (`com.apple.security.device.audio-input`) and location (`com.apple.security.personal-information.location`), from `VPhoneLaunchpad/Resources/VPhoneLaunchpad.entitlements`; its helper, CLI and launcher have none. It asks for Developer Tools access (`EPDeveloperTool`) and adds an `EPExecutionPolicy` exception for each installed bundle. `EPDeveloperTool.authorizationStatus` keeps the value the process launched with, while syspolicyd checks the live grant on every exception request, so Host Setup judges access by asking for an exception for Launchpad's own executable; a grant or a revocation in Settings applies without a relaunch. Its helper is the only root surface: it installs verified releases into the root-owned store `/Library/Application Support/vphone-launchpad/Bundles`, runs that bundle's `vphone-escalator allow` for its receipt-pinned `vphone-vm`, runs `cfw install` from that store after rechecking the recorded cdhash, and runs that store bundle's `vphone-cli vm leases --release-orphans` for the caller's own library folders. There is no generic command verb. Launchpad starts `vm launch` detached (own session, responsibility disclaimed) through `vphone-launchpad-launcher` in its `Contents/MacOS`, which starts `vphone-cli` as an ordinary child and stays until it exits, forwarding stop signals and exiting the same way. The launcher is therefore the responsible process for `vphone-vm`. As a tool in the app's `Contents/MacOS` it is attributed to the app, so privacy prompts, usage descriptions and grants (microphone, location) are the app's, asked once for its Developer ID signature instead of for each ad hoc signed bundle build; under the hardened runtime macOS refuses them without asking unless the app carries the matching entitlement. It refuses anything but `vm launch` of a `vphone-cli` in the root-owned store (`VPhoneLaunchpadLauncherPolicy`); without the launcher, Launchpad starts `vphone-cli` directly. Nothing is signed at build time: `VPhoneLaunchpad/Build/SignLaunchpad.sh` signs afterwards, and the team comes from the gitignored `Configuration/Developer.xcconfig`. Never commit a team ID.
- Launchpad and `VPhone.bundle` match by series, the first two numbers of the version: Launchpad 2.2.3 works with any `VPhone.bundle` 2.2.x, and the reverse. Patch releases within a series must stay interchangeable in both directions. A change to anything Launchpad relies on in the bundle (`vphone-cli` arguments or output, `vphone-escalator`, the bundle layout or receipt) needs a new minor version and a raised `minimumBundleComponents` in `VPhoneLaunchpad/VPhoneLaunchpadShared/VPhoneLaunchpadBundleStore.swift`. `Documents/Downloads/README.md` states this rule to users.
- Host VM artifacts, caches, and archives created by vphone use mode `0777` for workstation access. Symlinks are not followed when changing permissions. Guest filesystem modes inside `Disk.img` remain unchanged.
- `VPhoneRestore` runs in the CLI process over vendored libirecovery and idevicerestore. No Python or runtime Homebrew dependency is allowed.
- The VM process owns AppKit windows and the guest control connection. `vphoned` serves HTTP and WebSocket over VSOCK 1339, with camera data on 1338.
- The guest HTTP client, menus, file browser, IPA installation, and screen recorder live in `VPhoneVirtualMachineKit`.

---

## Coding Conventions

### Swift

- **Language:** Swift 6.0 (strict concurrency).
- **Style:** Pragmatic, minimal. No unnecessary abstractions.
- **Sections:** Use `// MARK: -` to organize code within files.
- **Access control:** Default (internal). Only mark `private` when needed for clarity.
- **Concurrency:** `@MainActor` for VM and UI classes. `nonisolated` delegate methods use `MainActor.isolated {}` to hop back safely.
- **Naming:** Types are `VPhone`-prefixed. Match Apple framework conventions.
- **Private APIs:** Use `Dynamic()` for runtime method dispatch. Touch objects use `NSClassFromString` + KVC to avoid designated initializer crashes.
- **NSWindow `isReleasedWhenClosed`:** Always set `window.isReleasedWhenClosed = false` for programmatically created windows managed by an `NSWindowController`. The default `true` causes `objc_release` crashes on dangling pointers during CA transaction commit.

### Shell Scripts

- Use `zsh` with `set -euo pipefail`.
- Scripts resolve their own directory via `${0:a:h}` or `$(cd "$(dirname "$0")" && pwd)`.

### Patchers

Every patcher is Swift, in `VPhoneExecutable/VPhoneCommand/FirmwarePatcher`.
The public firmware mode is JB; the CFW/DSC patchers are `vphone-cli cfw <verb>`.

- Disassembly is Capstone via `ARM64Disassembler` (the `libcapstone-spm` package). Assembly is `ARM64Encoder` plus the pre-encoded constants in `ARM64` (`ARM64Constants.swift`) — together they replace keystone's `asm()` / `asm_at()`, and `ARM64.nop` / `ARM64.movW0_0` are the old `NOP` / `MOV_W0_0`. IM4P containers go through `IM4PHandler` (the `libimg4-spm` package), which replaces pyimg4. Both resolve by URL; there is no `vendor/` directory to check out first.
- Dynamic pattern finding (string anchors, ADRP+ADD xrefs, BL frequency) — no hardcoded offsets.
- Each patch logged with offset and before/after state.
- No interpreter or runtime native-library repair: the `VPhone` Xcode scheme builds the complete bundle.

### Python

There is none, and adding any is a regression.

- No `.py` file is tracked in this repository, no shell script embeds a Python
  heredoc, and nothing resolves a `python3` at runtime. `git ls-files '*.py'`
  returns nothing; that is the standing check.
- There is no environment to activate and no dependency list to install. The
  restore backend was the last holdout and is now `VPhoneExecutable/VPhoneCommand/VPhoneRestore` over
  two vendored C targets — see `Research/Restore/native_restore_architecture.md`.
- A patch, a probe, a format reader or a device protocol belongs in Swift,
  where it is built, signed, gated by `Build/ValidateBundle.sh` and tested with
  everything else. Adding an interpreter back brings with it a provisioning
  step, a silent system-`python3` fallback, and a dependency closure
  `Build/ValidateBundle.sh` cannot see.
- There is no counter-example left. `amfidont` used to be cited as one — a
  third-party tool the user installed into their own Python — and it is gone
  too: the AMFI allowlist tool is `VPhoneExecutable/VPhoneEscalator`, a few C
  files built by Xcode for arm64e, with no runtime interpreter or LLDB.

### Kernel patcher guardrails

- For kernel patchers, never hardcode file offsets, virtual addresses, or preassembled instruction bytes inside patch logic.
- All instruction matching must be derived from Capstone decode results (mnemonic / operands / control-flow), not exact operand-string text when a semantic operand check is possible. `ARM64Disassembler` is the only decoder — match on the decoded mnemonic and operand detail, never on a formatted operand string.
- All replacement instruction bytes must come from Keystone-backed helpers already used by the project: `ARM64Encoder.encode*` and the `ARM64` constants, which were generated by keystone-engine, verified by Capstone round-trip, and are asserted word for word against keystone in `VPhoneExecutable/VPhoneCommand/FirmwarePatcherTests/Core/ARM64EncoderTests.swift`. Never write a literal instruction word at a patch site. A new instruction means a new encoder plus its keystone-checked test case, not a raw `Data`. Keystone is deliberately **not** a project dependency any more — nothing at runtime or in the test suite calls it, and the expected words are frozen constants. To derive a new one, stand keystone up in a throwaway environment **outside this repository** (`brew install keystone`, plus `keystone-engine` in a scratch interpreter somewhere under `/tmp`) and run the one-liner in that test file's header against it. There is no dependency list here to add it to and no environment here to install it into; creating either is the regression the "Python" section above forbids. Do not invent an expected word without checking it.
- Prefer source-backed semantic anchors: in-image symbol lookup, string xrefs, local call-flow, and XNU correlation. Do not depend on repo-exported per-kernel symbol dumps at runtime.
- When retargeting a patch, write the reveal procedure and validation steps into the relevant research doc or commit notes before handing off for testing. Do not create `TODO.md`.
- For `patchBsdInitAuth` (`Kernel/CustomFirmwarePatches/Storage/KernelCustomFirmwarePatchBsdInitAuth.swift`, named `patch_bsd_init_auth` in the research docs) specifically, the allowed reveal flow is: recover `bsd_init` -> locate rootvp panic block -> find the unique in-function `call` -> `cbnz w0/x0, panic` -> `bl imageboot_needed` site -> patch the branch gate only.

## Build & Sign

The VM process requires private entitlements for PV=3 virtualization. Build the `VPhone` scheme in Xcode; its final build phase ad hoc signs each child and seals `VPhone.bundle`. `swift build` alone does not produce the distributable bundle.

## Design System

- **Audience:** Security researchers. Terminal-adjacent workflow.
- **Feel:** Research instrument — precise, informative, no decoration.
- **Palette:** Dark neutral (`#1a1a1a` bg), status green/amber/red/blue accents.
- **Typography:** System monospace (SF Mono / Menlo) for UI and log output.
- **Depth:** Flat with 1px borders (`#333333`). No shadows.
- **Spacing:** 8px base unit, 12px component padding, 16px section gaps.

`vphone-launchpad` is the exception: it is a native SwiftUI Mac app. It uses system controls, grouped `Form`s, `Table`, SF Symbols, toolbar buttons for page actions, and the system appearance. Monospace is only for command text and logs.
