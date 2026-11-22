# 构建额度约定

- 只有用户明确要求构建、打包或更新 IPA 时，才运行 GitHub Actions 或重跑远程构建。日常代码和课程更新不自动构建。
- `.github/workflows/build.yml` 只保留 `workflow_dispatch`，不要添加 push、pull_request、tag 或定时触发。
- 发布时手动选择分支并设置 `publish_release=true`；只验收时设为 false。失败后先查看日志、修复并完成本地检查，不反复盲目重跑。
- 本地内容检查和必要的本地测试可以正常运行。发布版本及旧 IPA 不覆盖。
