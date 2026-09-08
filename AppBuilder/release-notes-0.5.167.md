# Tapgo AICoding 0.5.167

## PlanModeBanner persistent 模式背景更深（视觉区分常驻 vs 普通）

之前 PlanModeBanner 两种状态都用 `DSHTheme.brand` 背景，仅靠文字"Plan mode 已开启"/"Plan mode（常驻）"区分。persistent 模式背景加 `0.75` opacity，让 user 一眼看出常驻 vs 普通模式（普通模式浅，常驻模式深）。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner` 背景：`isPersistent ? DSHTheme.brand : DSHTheme.brand.opacity(0.75)`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
