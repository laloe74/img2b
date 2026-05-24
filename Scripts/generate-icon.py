#!/usr/bin/env python3
"""Generate macOS 26 style app icon for Image2Blog."""

import math
from PIL import Image, ImageDraw

BASE_SIZE = 1024

def squircle_dist(x, y, w, h, radius):
    """Distance field for a squircle (continuous curvature rounded rect)."""
    cx, cy = w / 2, h / 2
    dx = abs(x - cx) / (w / 2 - radius * 0.3)
    dy = abs(y - cy) / (h / 2 - radius * 0.3)
    return (dx ** 4 + dy ** 4) ** (1 / 4)

def create_base_icon(size):
    """Create the base icon image at the given size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = size * 0.08
    inner_size = size - 2 * margin

    # macOS 26 style squircle background with gradient
    # Deep indigo to vibrant purple gradient
    for y in range(size):
        for x in range(size):
            d = squircle_dist(x, y, size, size, size * 0.22)
            if d <= 1.0:
                # Smooth anti-aliased edge
                alpha = 1.0 if d < 0.995 else max(0, (1.0 - d) / 0.005)

                # Gradient: top-left light indigo, bottom-right deep purple
                nx = x / size
                ny = y / size
                angle = math.atan2(ny - 0.5, nx - 0.5) / math.pi

                # Rich color palette - macOS 26 style vibrant gradient
                r = int(90 + 50 * nx + 30 * (1 - ny))
                g = int(70 + 30 * nx + 40 * (1 - ny))
                b = int(220 - 40 * nx + 30 * ny)

                # Clamp
                r = max(0, min(255, r))
                g = max(0, min(255, g))
                b = max(0, min(255, b))
                a = int(alpha * 255)

                img.putpixel((x, y), (r, g, b, a))

    # Inner glow / highlight at top
    for y in range(size):
        for x in range(size):
            d = squircle_dist(x, y, size, size, size * 0.22)
            if d <= 0.97:
                nx, ny = x / size, y / size
                # Top highlight
                highlight = max(0, 1.0 - ny * 1.8) * 0.12
                if highlight > 0:
                    r, g, b, a = img.getpixel((x, y))
                    r = min(255, int(r + highlight * 255))
                    g = min(255, int(g + highlight * 255))
                    b = min(255, int(b + highlight * 255))
                    img.putpixel((x, y), (r, g, b, a))

    return img

def draw_camera_symbol(draw, size):
    """Draw a minimal camera/photography symbol."""
    cx, cy = size / 2, size / 2
    scale = size / 1024

    # Camera body
    body_w = 480 * scale
    body_h = 360 * scale
    body_left = cx - body_w / 2
    body_top = cy - body_h / 2

    # Rounded rect body
    radius = 60 * scale
    draw.rounded_rectangle(
        [body_left, body_top + 60 * scale, body_left + body_w, body_top + body_h],
        radius=radius,
        fill=(255, 255, 255, 230),
    )

    # Camera lens (circle)
    lens_r = 100 * scale
    lens_cx = cx
    lens_cy = cy - 10 * scale
    draw.ellipse(
        [lens_cx - lens_r, lens_cy - lens_r, lens_cx + lens_r, lens_cy + lens_r],
        fill=(255, 255, 255, 200),
        outline=(255, 255, 255, 255),
        width=int(14 * scale),
    )

    # Lens inner ring
    inner_r = 55 * scale
    draw.ellipse(
        [lens_cx - inner_r, lens_cy - inner_r, lens_cx + inner_r, lens_cy + inner_r],
        fill=None,
        outline=(255, 255, 255, 180),
        width=int(10 * scale),
    )

    # Lens center dot
    dot_r = 20 * scale
    draw.ellipse(
        [lens_cx - dot_r, lens_cy - dot_r, lens_cx + dot_r, lens_cy + dot_r],
        fill=(255, 255, 255, 255),
    )

    # Flash circle (top right)
    flash_r = 25 * scale
    flash_x = cx + 140 * scale
    flash_y = body_top + 90 * scale
    draw.ellipse(
        [flash_x - flash_r, flash_y - flash_r, flash_x + flash_r, flash_y + flash_r],
        fill=(255, 255, 255, 200),
    )

    # Top bump for viewfinder
    bump_w = 120 * scale
    bump_h = 40 * scale
    draw.rounded_rectangle(
        [cx - bump_w / 2, body_top + 20 * scale, cx + bump_w / 2, body_top + 60 * scale],
        radius=int(20 * scale),
        fill=(255, 255, 255, 230),
    )

def create_final_icon(size):
    """Create the complete icon at the given size."""
    img = create_base_icon(size)
    draw = ImageDraw.Draw(img)
    draw_camera_symbol(draw, size)

    # Subtle drop shadow effect on inner surface
    # Add a gradient overlay for depth
    overlay = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)

    for y in range(size):
        for x in range(size):
            d = squircle_dist(x, y, size, size, size * 0.22)
            if d <= 1.0:
                ny = y / size
                shadow = max(0, (ny - 0.6) * 0.15)
                if shadow > 0:
                    overlay.putpixel((x, y), (0, 0, 0, int(shadow * 255)))

    img = Image.alpha_composite(img, overlay)
    return img

def main():
    print("Generating macOS 26 style Image2Blog icon...")

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    iconset = '/tmp/Image2Blog.iconset'
    import os
    os.makedirs(iconset, exist_ok=True)

    # Generate base icon at 1024
    base = create_final_icon(1024)

    for s in sizes:
        # 1x
        resized = base.resize((s, s), Image.LANCZOS)
        resized.save(f'{iconset}/icon_{s}x{s}.png')

        # 2x (retina)
        s2 = s * 2
        if s2 <= 1024:
            resized2 = base.resize((s2, s2), Image.LANCZOS)
            resized2.save(f'{iconset}/icon_{s}x{s}@2x.png')

    # Also ensure standard naming for iconutil
    for s in [16, 32, 128, 256, 512]:
        if not os.path.exists(f'{iconset}/icon_{s}x{s}@2x.png'):
            s2 = s * 2
            resized2 = base.resize((s2, s2), Image.LANCZOS)
            resized2.save(f'{iconset}/icon_{s}x{s}@2x.png')

    print(f'Iconset created at {iconset}')
    print('Run: iconutil -c icns /tmp/Image2Blog.iconset -o /tmp/Image2Blog.icns')

if __name__ == '__main__':
    main()
