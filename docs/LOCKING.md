# Hermes 本机版本锁定（自维护）

本机固定运行 **Hermes Agent v0.22.5（2026.9.24, stable，commit bf0203a）**，不跟官方滚动升级。
原因是：我们在这版上做了较多前端改动（中文界面、配置说明汉化、手机输入框、附件与产出入口），
跟着官方升级会不断产生冲突，收益主要是新功能而不是稳定性。

## 为什么锁定

- 官方 v0.22.5 之后的版本会重写前端结构，我们的补丁需要逐条重新适配；
- 现有功能已经够用，缺的功能我们自己补（改一行就能上，不用等社区）；
- 出问题可以立即回滚到快照，而不是等官方修。

## 三层保险

| 层 | 作用 | 位置 |
|---|---|---|
| 配置 | 关掉被动升级提示；万一升级先全量备份 `~/.hermes` | `updates.check=false` / `updates.pre_update_backup=true` |
| Shell | `hermes update` 被拦截，要显式 `HERMES_ALLOW_UPDATE=1` 才放行 | `~/.bashrc` 里的 `hermes()` 函数 |
| 快照 | 源码改动 + 构建产物 + 补丁包 + 配置打包，一条命令还原 | `/root/hermes-zh-patch/snapshot.sh`（周更 + 手动） |

## 日常操作

```bash
# 改了前端源码（web/src/**）之后
/root/hermes-zh-patch/rebuild.sh        # 构建 + 挂覆盖层 + 重启 + 自检

# 改了补丁包本身（payload/ 或 patch_src.py）之后
/root/hermes-zh-patch/apply.sh

# 出问题
/root/hermes-zh-patch/snapshot.sh --list
/root/hermes-zh-patch/snapshot.sh --restore latest

# 手动存一份当前状态
/root/hermes-zh-patch/snapshot.sh

# 确实要升级（不推荐）
/root/hermes-zh-patch/snapshot.sh
HERMES_ALLOW_UPDATE=1 hermes update
/root/hermes-zh-patch/apply.sh
```

## 已知边界

- Shell 拦截只对**交互式 bash** 生效；agent 用 `bash -lc` 或 systemd 直接调二进制时不受约束。
  真正的保险是快照 + `updates.check=false`（被动提示已关）。
- `hermes doctor`、`hermes status`、模型切换、网关重启等功能不受锁定影响。
- 依赖已装齐（node_modules 10MB、pnpm 锁文件在仓库里），重建前端**不需要联网**。
