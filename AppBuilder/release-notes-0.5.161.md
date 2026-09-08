# Tapgo AICoding 0.5.161

## 修复 v0.5.160 hover 反馈无效（@State in func 被忽略）

v0.5.160 在 `actionCard` 普通函数里写 `@State var hovering = false` —— SwiftUI PropertyWrapper **必须**在 View struct 属性里声明，函数内声明被编译器忽略。`hovering` 永远是 false，hover 反馈没工作。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 把 `actionCard` 函数改成 `ActionCard` View struct， `@State var hovering` 写在 struct 属性里，hover 反馈正确工作。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
