# img2b

macOS 26 原生博客图床工具。拖入图片 → 自动转 WebP → 上传 R2/S3 → TOML 输出。

## 安装

### Homebrew

```bash
brew tap laloe74/img2b
brew install --cask img2b
```

### 手动安装

从 [Releases](https://github.com/laloe74/img2b/releases) 下载 DMG，拖入 Applications。

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
url = "https://image.tongmingzhi.com/img-5a833392f4b928b1-20260524.webp"
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

- **Lossless** — 无损压缩（像素完美，文件大）
- **Quality** — 75-100，90 接近无损
- **Target Size** — 目标文件大小，超标自动降质+缩图

## 技术栈

- SwiftUI (macOS 26)
- libvips (图片压缩)
- AWS Signature V4 (S3/R2 上传)
- GitHub Releases (自动更新)

## License

MIT
