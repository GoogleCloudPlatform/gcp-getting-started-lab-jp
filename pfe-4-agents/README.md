# Agent Platform Teachme readable v16

v15 の成功版をベースに、base64 埋め込みをやめて `assets/` に通常ファイルとして分離した可読版です。

## 使い方

```bash
cd "$HOME"
unzip agent_platform_teachme_readable_v16.zip -d agent-platform-it-support-handson
cd agent-platform-it-support-handson
teachme tutorial.md
```

チュートリアル中の生成ファイルは `assets/` からコピーされます。

## 含まれるソース

- `assets/Dockerfile`
- `assets/check_01.py`
- `assets/deploy_it_support_agent.py`
- `assets/model_armor_template.json`
- `assets/query_it_support_agent.py`
- `assets/requirements.txt`
- `assets/sanitize_dangerous.json`
- `assets/sanitize_normal.json`
- `assets/sanitize_prompt_injection.json`
- `assets/server.py`
- `assets/setup_db.py`
- `assets/test_mcp_local.py`
- `assets/toolspec.json`
