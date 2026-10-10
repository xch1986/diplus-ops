# 安全与脱敏说明

本仓库为**公开存档/交接用途**，已做如下处理：

- ❌ 不含：frps token、隧道公网地址、Web 登录口令、企业微信/钉钉 webhook、JWT 密钥、SQLite 业务数据（db.db）、Lucky/OpenList 真实配置
- ❌ 不含：UFI-TOOLS（第三方开源项目，见 [github.com/kanoqwq/UFI-TOOLS](https://github.com/kanoqwq/UFI-TOOLS)）——车机远程通道依赖的 UFI 设备工具不在本项目范围内
- ✅ 提供：`frpc.toml.example`（脱敏模板）、全部业务代码与守护脚本、运维文档

如你有自己的部署实例，请勿直接使用示例凭据；所有密码/token 请自行生成。

## License

MIT
