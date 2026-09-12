# GitHub Desk

GitHub Desk 是一个仅在当前 Mac 上运行的原生仓库管理工具，用于减少重复的 Git 和 GitHub 命令操作。

## 功能

- 扫描本地工作区中的 Git 仓库
- 合并显示 GitHub 远程仓库
- 查看分支、提交、未提交修改和领先/落后状态
- 将本地项目发布为 GitHub 仓库
- 克隆尚未存在的 GitHub 仓库
- 提交并推送、拉取、推送本地修改
- 切换仓库公开状态
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

应用默认扫描 `~/Documents`，复用机器上已登录的 GitHub CLI `gh`，不会读取或保存访问令牌。
