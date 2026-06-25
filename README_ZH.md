[English](README.md)

<div align="center">
<a href="https://github.com/trojanpanel"><img src="https://github.com/trojanpanel/install-script/assets/46235235/bfc4f96a-e8b6-499d-956f-a9c212059294" alt="Trojan Panel" width="150" /></a>
<h1>Trojan Panel</h1>
<p>
<a href="https://github.com/trojanpanel/install-script/stargazers"><img src="https://img.shields.io/github/stars/trojanpanel/install-script" alt="GitHub stars"></a>
<a href="https://github.com/trojanpanel/install-script/forks"><img src="https://img.shields.io/github/forks/trojanpanel/install-script" alt="GitHub forks"></a>
<a href="https://github.com/trojanpanel/install-script/issues"><img src="https://img.shields.io/github/issues/trojanpanel/install-script" alt="GitHub issues"></a>
<a href="https://github.com/trojanpanel/install-script/releases"><img src="https://img.shields.io/github/v/release/trojanpanel/install-script" alt="GitHub release"></a>
<a href="https://hub.docker.com/r/jonssonyan/trojan-panel"><img src="https://img.shields.io/docker/pulls/jonssonyan/trojan-panel" alt="Docker pulls"></a>
</p>
<h3>支持Xray/Trojan-Go/Hysteria/NaiveProxy的多用户Web管理面板</h3>
<a href="https://github.com/trojanpanel/install-script/assets/46235235/7ac2bba1-b442-442d-b48e-b52f92e0bad8"><img src="https://github.com/trojanpanel/install-script/assets/46235235/7ac2bba1-b442-442d-b48e-b52f92e0bad8" alt="Trojan Panel"/></a>
</div>

## 特点

- 极速搭建: 一键安装脚本，降低部署门槛，快速搭建系统
- 国际化: 系统语言支持中文/English/한국인/فارسی
- 多代理支持: 节点类型支持Xray/Trojan-Go/Hysteria/NaiveProxy
- 分布式: 前后端分离开发，减少模块之间耦合度，可以自由组合部署在多个服务器
- 功能强大: 支持登录注册/用户管理/节点管理/邮件管理/黑名单管理/自定义伪装网站/系统看板等
- 所见即所得: 支持多节点管理，自动化管理远程节点，自动化申请/续签证书，面板内编辑节点，远程服务实时修改节点配置

## 系统要求

系统: CentOS 7+ / Ubuntu 18+ / Debian 10+

CPU: linux/amd64 / linux/arm/v6 / linux/arm/v7 / linux/arm64 / linux/s390x / linux/ppc64le / linux/386

内存: ≥ 1G

## 安装

- 联机（推荐）

    ```shell
    source <(curl -L https://github.com/trojanpanel/install-script/raw/main/install_script.sh)
    ```

- 单机

    ```shell
    source <(curl -L https://github.com/trojanpanel/install-script/raw/main/install_script_standalone.sh)
    ```

- [安装旧版本](README_ARCHIVE_ZH.md)

### 定制化分离部署

此 fork 新增 `custom_install.sh`，用于非交互的一键分离部署。

- web 端：部署 Caddy HTTPS、Trojan Panel 前端、后端、MariaDB、Redis，不部署 `trojan-panel-core`。
- node 端：部署 Caddy 伪装站/证书和 `trojan-panel-core`，连接 web 端的 MariaDB/Redis。
- GHCR 测试镜像：默认使用 `ghcr.io/1linhao/trojan-panel:singbox`、`ghcr.io/1linhao/trojan-panel-ui:singbox`、`ghcr.io/1linhao/trojan-panel-core:singbox`。首次由 GitHub Actions 推送后，需要在 GitHub Packages 页面把对应 package 设置为 Public，VPS 即可匿名拉取。
- 本地镜像测试模式：在本机编译并打包定制镜像，手动传到 VPS 后再用 `custom_install.sh` 一键运行。

部署 web 端：

```shell
curl -fsSL https://raw.githubusercontent.com/1linhao/trojan-panel-install-script/feature/sing-box-subscribe/custom_install.sh -o /tmp/tp-custom.sh && \
curl -fsSL https://raw.githubusercontent.com/1linhao/trojan-panel-install-script/feature/sing-box-subscribe/examples/web.env.yaml -o ./web.env.yaml && \
chmod +x /tmp/tp-custom.sh && \
bash /tmp/tp-custom.sh web ./web.env.yaml
```

部署 node 端：

```shell
curl -fsSL https://raw.githubusercontent.com/1linhao/trojan-panel-install-script/feature/sing-box-subscribe/custom_install.sh -o /tmp/tp-custom.sh && \
curl -fsSL https://raw.githubusercontent.com/1linhao/trojan-panel-install-script/feature/sing-box-subscribe/examples/node.env.yaml -o ./node.env.yaml && \
chmod +x /tmp/tp-custom.sh && \
bash /tmp/tp-custom.sh node ./node.env.yaml
```

本机构建测试镜像：

```shell
bash ./build_test_images.sh ./examples/build-images.env.yaml
scp -r ./dist/test-images root@your-vps:/root/trojan-panel-test-images
```

使用已传输的本地镜像部署 web 端：

```shell
curl -fsSL https://raw.githubusercontent.com/1linhao/trojan-panel-install-script/feature/sing-box-subscribe/custom_install.sh -o /tmp/tp-custom.sh && \
chmod +x /tmp/tp-custom.sh && \
bash /tmp/tp-custom.sh web /root/trojan-panel-test-images/web-local-image.env.yaml
```

使用已传输的本地镜像部署 node 端：

```shell
curl -fsSL https://raw.githubusercontent.com/1linhao/trojan-panel-install-script/feature/sing-box-subscribe/custom_install.sh -o /tmp/tp-custom.sh && \
chmod +x /tmp/tp-custom.sh && \
bash /tmp/tp-custom.sh node /root/trojan-panel-test-images/node-local-image.env.yaml
```

配置示例：

- [web.env.yaml](examples/web.env.yaml)
- [node.env.yaml](examples/node.env.yaml)
- [build-images.env.yaml](examples/build-images.env.yaml)
- [web-local-image.env.yaml](examples/web-local-image.env.yaml)
- [node-local-image.env.yaml](examples/node-local-image.env.yaml)

设置 `force: "1"` 可重建已有容器。执行 `remove-web ./web.env.yaml` 或 `remove-node ./node.env.yaml` 时设置 `purge_data: "1"` 可同时删除生成的数据目录。

## 其他

Telegram Channel: https://t.me/jonssonyan_channel

You can subscribe to my channel on YouTube: https://www.youtube.com/@jonssonyan

## 文档

访问 [https://trojanpanel.github.io](https://trojanpanel.github.io) 查看完整文档

## 更新日志

访问 [https://trojanpanel.github.io/change/change-log.html](https://trojanpanel.github.io/change/change-log.html) 查看完整日志

## 报告缺陷与问题

[Issues](https://github.com/trojanpanel/install-script/issues)

## 致谢

- [trojan](https://github.com/trojan-gfw/trojan)
- [trojan-go](https://github.com/p4gefau1t/trojan-go)
- [Xray-core](https://github.com/XTLS/Xray-core)
- [hysteria](https://github.com/HyNetwork/hysteria)
- [naiveproxy](https://github.com/klzgrad/naiveproxy)

## Star随时间变化

[![Stargazers over time](https://starchart.cc/trojanpanel/install-script.svg)](https://github.com/trojanpanel/install-script)
