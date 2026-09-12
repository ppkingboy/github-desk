# GitHub Desk

GitHub Desk 是一个仅在当前 Mac 上运行的原生仓库管理工具，用于减少重复的 Git 和 GitHub 命令操作。

## 功能

- 扫描本地工作区中的 Git 仓库
- 使用 GitHub Device Flow 登录，无需安装 `gh`
- 保存并切换多个 GitHub 账号，Token 存入 macOS Keychain
- 合并显示 GitHub 远程仓库
- 查看分支、提交、未提交修改和领先/落后状态
- 将本地项目发布为 GitHub 仓库
- 克隆尚未存在的 GitHub 仓库
- 提交并推送、拉取、推送本地修改
- 切换仓库公开状态
- 发布或提交前扫描私钥、Token 和常见服务密钥
- 检查 README、License、项目说明、Topics 和自动化配置
- 一键补齐仓库基础文件
- 批量同步安全的已连接仓库
- 创建本地项目并直接发布到 GitHub
- 在 Finder 或 GitHub 中打开项目

## 构建

```bash
./build-app.sh
```

构建结果位于：

```text
dist/GitHub Desk.app
```

## 使用

1. 双击 `GitHub Desk.app`。
2. 默认扫描 `~/Documents`，也可以点击“选择目录”切换工作区。
3. 在“本地项目”中处理提交、拉取、推送和首次发布。
4. 在“GitHub 仓库”中克隆尚未存在本地副本的远程仓库。

## 自检

```bash
swift run GitHubDesk --self-test
```

应用默认扫描 `~/Documents`。登录令牌只保存在当前 Mac 的 Keychain，不写入项目文件，也不依赖 Codex 或 GitHub CLI。
