# MyNet repo 门禁 —— 统一入口
# 用法：make lint | make test | make guard | make check | make install-hooks
# 语言：平台适配脚本

.PHONY: lint test guard check install-hooks

lint:
	@echo "▸ lint"
	@echo "(S9 补全：shellcheck / 打包校验)"

test:
	@echo "▸ test"
	@echo "(S9 补全)"

guard:
	@echo "▸ guard（安全红线）"
	@sh .githooks/guard.sh

check: guard lint test
	@echo "✓ check 通过"

install-hooks:
	@git config core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "✓ hooks 已安装（core.hooksPath = .githooks）"
