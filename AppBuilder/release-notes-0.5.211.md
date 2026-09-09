# Tapgo AICoding 0.5.211

## 图像文件阅读对齐 Codex 实机（查看图像）

- 之前 `.read` 工具调用对所有文件统一显示「读取」。Codex 在用户截图里对图像文件专门显示「已查看 N 张图像」。
- 现在工具调用解析到图像扩展（png/jpg/jpeg/gif/webp/heic/bmp）的文件路径时，显示「查看图像」+ photo 图标；其他文件仍按原状显示「读取」。
- 应用于所有读类工具（read_file / view / get / open 等）。

## 测试

构建 OK + 三机安装回读。
