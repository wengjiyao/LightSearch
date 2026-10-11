#!/usr/bin/env python3
"""
Generate LightSearch app icon in all required macOS sizes.

Creates a modern icon with:
- Gradient blue background (sky blue to deep blue)
- White magnifying glass with light rays
- Clean, minimal design suitable for macOS
"""

from PIL import Image, ImageDraw
import math
import os

def draw_icon(size):
    """Draw LightSearch icon at specified size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Gradient background (rounded square)
    corner_radius = int(size * 0.225)  # macOS standard corner radius

    # Draw rounded rectangle with gradient
    for y in range(size):
        # Gradient from light blue to deep blue
        ratio = y / size
        r = int(100 + (30 - 100) * ratio)
        g = int(150 + (80 - 150) * ratio)
        b = int(255 + (180 - 255) * ratio)
        color = (r, g, b, 255)

        # Draw horizontal line with rounded corners
        if y < corner_radius:
            # Top rounded corners
            x_offset = corner_radius - int(math.sqrt(corner_radius**2 - (corner_radius - y)**2))
            draw.line([(x_offset, y), (size - x_offset - 1, y)], fill=color, width=1)
        elif y >= size - corner_radius:
            # Bottom rounded corners
            dy = y - (size - corner_radius)
            x_offset = corner_radius - int(math.sqrt(corner_radius**2 - dy**2))
            draw.line([(x_offset, y), (size - x_offset - 1, y)], fill=color, width=1)
        else:
            # Middle section
            draw.line([(0, y), (size - 1, y)], fill=color, width=1)

    # Draw magnifying glass
    center_x = size * 0.45
    center_y = size * 0.42
    lens_radius = size * 0.18
    handle_width = size * 0.08
    handle_length = size * 0.25

    # Magnifying glass lens (circle with white stroke)
    lens_thickness = max(2, int(size * 0.04))
    for thickness_offset in range(lens_thickness):
        draw.ellipse(
            [
                center_x - lens_radius - thickness_offset,
                center_y - lens_radius - thickness_offset,
                center_x + lens_radius + thickness_offset,
                center_y + lens_radius + thickness_offset
            ],
            outline=(255, 255, 255, 255),
            width=1
        )

    # Magnifying glass handle
    handle_x1 = center_x + lens_radius * 0.6
    handle_y1 = center_y + lens_radius * 0.6
    handle_x2 = handle_x1 + handle_length * math.cos(math.pi / 4)
    handle_y2 = handle_y1 + handle_length * math.sin(math.pi / 4)

    # Draw thick handle
    handle_thickness = int(handle_width)
    for offset in range(-handle_thickness // 2, handle_thickness // 2):
        draw.line(
            [
                (handle_x1 + offset * math.cos(math.pi / 4 + math.pi / 2),
                 handle_y1 + offset * math.sin(math.pi / 4 + math.pi / 2)),
                (handle_x2 + offset * math.cos(math.pi / 4 + math.pi / 2),
                 handle_y2 + offset * math.sin(math.pi / 4 + math.pi / 2))
            ],
            fill=(255, 255, 255, 255),
            width=2
        )

    # Draw light rays emanating from top-right
    ray_origin_x = size * 0.75
    ray_origin_y = size * 0.25
    ray_angles = [-30, -15, 0, 15, 30]  # degrees from horizontal
    ray_length = size * 0.3

    for angle_deg in ray_angles:
        angle_rad = math.radians(angle_deg - 45)  # Offset to point toward bottom-left
        end_x = ray_origin_x + ray_length * math.cos(angle_rad)
        end_y = ray_origin_y + ray_length * math.sin(angle_rad)

        # Draw ray with gradient opacity
        segments = 20
        for i in range(segments):
            t = i / segments
            x1 = ray_origin_x + (end_x - ray_origin_x) * t
            y1 = ray_origin_y + (end_y - ray_origin_y) * t
            x2 = ray_origin_x + (end_x - ray_origin_x) * (t + 1 / segments)
            y2 = ray_origin_y + (end_y - ray_origin_y) * (t + 1 / segments)

            # Fade from opaque to transparent
            opacity = int(200 * (1 - t))
            width = max(1, int((1 - t) * size * 0.02))

            draw.line([(x1, y1), (x2, y2)], fill=(255, 255, 255, opacity), width=width)

    return img

def main():
    """Generate all required icon sizes."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    icon_dir = os.path.join(script_dir, '..', 'LightSearch', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')

    # macOS icon sizes: 1x and 2x variants
    sizes = [
        (16, '16x16', '1x'),
        (32, '16x16', '2x'),
        (32, '32x32', '1x'),
        (64, '32x32', '2x'),
        (128, '128x128', '1x'),
        (256, '128x128', '2x'),
        (256, '256x256', '1x'),
        (512, '256x256', '2x'),
        (512, '512x512', '1x'),
        (1024, '512x512', '2x'),
    ]

    print("Generating LightSearch app icons...")

    for pixel_size, logical_size, scale in sizes:
        icon = draw_icon(pixel_size)
        filename = f"icon_{logical_size}@{scale}.png"
        filepath = os.path.join(icon_dir, filename)
        icon.save(filepath, 'PNG')
        print(f"  ✓ {filename} ({pixel_size}x{pixel_size})")

    print(f"\n✓ All icons generated in {icon_dir}")
    print("\nNext steps:")
    print("1. Update Contents.json to reference the generated images")
    print("2. Rebuild the project to see the new icon")

if __name__ == '__main__':
    main()
