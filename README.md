# img2b

macOS 原生博客图床工具。拖入图片 → 自动转 AVIF → 上传 R2/S3 → TOML 输出。

## 安装

从 [Releases](https://github.com/laloe74/img2b/releases) 下载 DMG，拖入 Applications 安装。

## 使用

### 1. 配置图床

打开设置（菜单栏 **img2b → Settings...** 或工具栏齿轮图标）：

- **Account ID** — Cloudflare R2 的 Account ID
- **Access Key ID / Secret Access Key** — R2 API Token
- **Bucket Name** — 储存桶名称
- **Public URL Base** — 图片公开访问域名，如 `https://image.yourdomain.com`

### 2. 上传图片

- 从桌面/Finder 拖图片到右侧虚线框
- 在顶部工具栏为图片选择分类（design / photography / physics / typography）
- 点击 **Upload All** 或右键图片 → Upload
- 上传成功后 URL 自动复制到剪贴板，TOML 条目自动写入文件

### 3. TOML 输出

设置里配置 TOML File Path（如 `~/blog/content/photos.toml`），每次上传后条目自动插入文件顶部：

```toml
[[items]]
category = "photography"
date = 2026-05-24
title = "img-5a833392f4b928b1-20260524"
url = "https://image.tongmingzhi.com/img-5a833392f4b928b1-20260524.avif"
width = 2560
height = 1440
```

模板可在设置中自定义。

### 4. 命名规则

默认 `img-{hash16}-{date}`，可在设置中自定义：

| 占位符 | 说明 |
|--------|------|
| `{hash}` | SHA256 完整值 |
| `{hash16}` | SHA256 前 16 位 |
| `{hash8}` | SHA256 前 8 位 |
| `{date}` | 日期 yyyyMMdd |

### 5. 压缩设置

6 级压缩（Zipic 风格）：

| 级别 | 标签 | 说明 |
|------|------|------|
| 1 | Near Lossless | 最小数据移除，最高画质 |
| 2 | Light | 肉眼几乎不可察觉 |
| 3 | Balanced | 推荐，适合大多数图片 |
| 4 | Moderate | 近距离观察可见差异 |
| 5 | Aggressive | 显著减小体积 |
| 6 | Extreme | 最小文件，画质可见下降 |

可设置最大宽度（超过则等比缩放），0 表示不限制。

## 技术栈

- SwiftUI (macOS 15+)
- ImageIO (原生 AVIF 编码)
- AWS Signature V4 (手写签名，无需 AWS SDK)
- GitHub Releases (更新检测)

## License

MIT
