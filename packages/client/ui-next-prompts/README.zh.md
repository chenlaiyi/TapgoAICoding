---
description: "通过上下文推荐按钮填入输入框，不自动发送。"
kind: "package-reference"
---

# @deepseek-ai/dsh-client-ui-next-prompts

[English](README.md) | 中文

## 概述

在 Web 和桌面端最新完成的回复下方显示一至三条下一步提示词。点击按钮会填入空输入框，或追加到已有草稿，保留附件和内联引用，并聚焦输入框。由用户编辑并明确发送。

## 目录

- [使用此包](#use-this-package)
- [理解实现](#understand-the-implementation)
- [模型体验](#model-experience)
- [已知限制与后续工作](#known-limitations-and-deferred-work)
- [开发备注](#dev-note)

<a id="use-this-package"></a>
## 使用此包

Web bundle 将此浏览器插件与[主机生成器](../../session/next-prompts/README.zh.md)一起挂载。推荐使用用户的语言。窄屏下按钮换行，触摸时最小高度为 44px，支持键盘聚焦和激活。生成失败时显示简短提示，仍可正常输入。

<a id="understand-the-implementation"></a>
## 理解实现

插件注册到 `conversation.chat.turnTail`，通过框架读取 `nextPrompts` 投影，只在匹配的已完成轮次展示。点击回调解析当前显示会话的保留绑定，以 `whenDraftExists: 'append'` 调用 `conversation.input.requestDraftInitialization`；锁定或已释放的输入框拒绝修改。不调用发送操作。卸载会移除插槽和语言字典贡献。

<a id="model-experience"></a>
## 模型体验

### 用户确认的提示词

#### 模型看到的内容

只有用户明确发送后，选中的推荐才作为 `user/message` 事件的文字内容进入模型输入。渲染和草稿编辑不提供模型输入；推荐措辞由主机负责。

#### Token 影响

用户发送草稿前没有直接 token 影响；发送时按普通用户消息计算 token。

#### KV Cache 影响

渲染和草稿修改不改变模型输入。明确发送建议时追加普通用户消息。

<a id="known-limitations-and-deferred-work"></a>
## 已知限制与后续工作

- 禁用主机会停止新请求，但已记录的最新结果仍可展示。生成尚未完成或结果为空时不展示推荐。
- 提交过程锁定输入框时，点击不会改变草稿。

<a id="dev-note"></a>
### 开发备注

非规范性的开发备注：无。
