# MyNet repo 门禁 —— 统一入口
# 用法：make lint | make test | make guard | make check | make install-hooks
#       make pack-pkg | pack-dmg | pack-nsis | pack-linux | pack-all
# 语言：平台适配脚本 + 安装器

.PHONY: lint test guard check install-hooks pack-linux pack-pkg pack-dmg pack-nsis pack-all

lint:
	@sh scripts/check.sh lint

test:
	@sh scripts/check.sh test

guard:
	@echo "▸ guard（安全红线）"
	@sh .githooks/guard.sh

check: guard lint test
	@echo "✓ check 通过"

install-hooks:
	@git config core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "✓ hooks 已安装（core.hooksPath = .githooks）"

# ── 打包（E-7）────────────────────────────────────────────────
#
# 前置：mynet_agent 侧先 `make dist`，产物在
#   ../mynet_agent/dist/mynet_agent_{platform}_{arch}_{version}/
# 本目录的 pack-* 只负责「把二进制变成可双击的安装器」。
#
# 版本从产物目录取，也可 VERSION=… 覆盖。

AGENT_DIST ?= ../mynet_agent/dist
DIST       ?= dist

pack-linux:
	@echo "▸ pack-linux（校验 tgz 布局；真包在 mynet_agent 的 make dist）"
	@test -d "$(AGENT_DIST)" || { echo "✗ 缺 $(AGENT_DIST) —— 先在 mynet_agent 跑 make dist"; exit 1; }
	@ls "$(AGENT_DIST)"/mynet_agent_linux_*.tgz >/dev/null 2>&1 || { echo "✗ 没有 linux tgz"; exit 1; }
	@for f in "$(AGENT_DIST)"/mynet_agent_linux_*.tgz; do \
		echo "  $$f"; \
		tar -tzf "$$f" | grep -E '/(mynet|mynetd)$$' >/dev/null || { echo "✗ $$f 里没有 mynet/mynetd"; exit 1; }; \
	done
	@echo "✓ linux tgz 布局 OK（安装流程见 docs/INSTALL.md）"

pack-pkg:
	@echo "▸ pack-pkg（macOS .pkg）"
	@command -v pkgbuild >/dev/null 2>&1 || { echo "✗ 需要 macOS 的 pkgbuild"; exit 1; }
	@for d in "$(AGENT_DIST)"/mynet_agent_darwin_*; do \
		[ -d "$$d" ] || continue; \
		case "$$d" in *.tgz|*.zip) continue ;; esac; \
		ver=$$(basename "$$d" | sed -n 's/.*_\(v[^_]*\)$$/\1/p'); \
		[ -n "$$ver" ] || ver=$(or $(VERSION),v0.0.0-dev); \
		sh macos/build-pkg.sh "$$d" "$$ver" || exit 1; \
	done

pack-dmg: pack-pkg
	@echo "▸ pack-dmg（macOS .dmg）"
	@command -v hdiutil >/dev/null 2>&1 || { echo "✗ 需要 macOS 的 hdiutil"; exit 1; }
	@for p in $(DIST)/mynet_agent_darwin_*.pkg; do \
		[ -f "$$p" ] || continue; \
		sh macos/build-dmg.sh "$$p" || exit 1; \
	done

pack-nsis:
	@echo "▸ pack-nsis（Windows .exe）"
	@command -v makensis >/dev/null 2>&1 || { echo "✗ 需要 makensis（brew install makensis）"; exit 1; }
	@found=0; \
	for d in "$(AGENT_DIST)"/mynet_agent_windows_*; do \
		[ -d "$$d" ] || continue; \
		case "$$d" in *.tgz|*.zip) continue ;; esac; \
		[ -f "$$d/mynet.exe" ] || { echo "  ⚠ 跳过 $$d（缺 mynet.exe）"; continue; }; \
		found=1; \
		ver=$$(basename "$$d" | sed -n 's/.*_\(v[^_]*\)$$/\1/p'); \
		[ -n "$$ver" ] || ver=$(or $(VERSION),v0.0.0-dev); \
		sh nsis/build-nsis.sh "$$d" "$$ver" || exit 1; \
	done; \
	[ "$$found" = 1 ] || { echo "✗ 没有可用的 windows 产物目录"; exit 1; }

pack-all: pack-linux
	@-$(MAKE) --no-print-directory pack-pkg
	@-$(MAKE) --no-print-directory pack-dmg
	@-$(MAKE) --no-print-directory pack-nsis
	@echo "✓ pack-all 完成（平台工具缺失的会跳过并打印原因）"
	@ls -la $(DIST) 2>/dev/null || true
