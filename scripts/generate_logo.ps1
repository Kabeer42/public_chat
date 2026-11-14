Add-Type -AssemblyName System.Drawing

function Create-RoundedRectanglePath {
    param(
        [System.Drawing.RectangleF]$rect,
        [float]$radius
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2

    # Top-Left
    $path.AddArc($rect.X, $rect.Y, $diameter, $diameter, 180, 90)
    # Top-Right
    $path.AddArc($rect.Right - $diameter, $rect.Y, $diameter, $diameter, 270, 90)
    # Bottom-Right
    $path.AddArc($rect.Right - $diameter, $rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    # Bottom-Left
    $path.AddArc($rect.X, $rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Generate-VaultChatLogo {
    param([int]$size = 512)

    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $scale = $size / 512.0

    # 1. Outer App Icon Squircle Background
    $bgMargin = 16.0 * $scale
    $bgRect = New-Object System.Drawing.RectangleF $bgMargin, $bgMargin, ($size - 2 * $bgMargin), ($size - 2 * $bgMargin)
    $bgRadius = 100.0 * $scale
    $bgPath = Create-RoundedRectanglePath $bgRect $bgRadius

    $bgColorTop = [System.Drawing.Color]::FromArgb(255, 15, 23, 42)    # Slate 900
    $bgColorBottom = [System.Drawing.Color]::FromArgb(255, 30, 27, 75) # Deep Indigo 950
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF 0, 0),
        (New-Object System.Drawing.PointF $size, $size),
        $bgColorTop,
        $bgColorBottom
    )
    $g.FillPath($bgBrush, $bgPath)
    $bgBrush.Dispose()

    # Subtle glowing border
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 99, 102, 241), (3.0 * $scale))
    $g.DrawPath($borderPen, $bgPath)
    $borderPen.Dispose()
    $bgPath.Dispose()

    # 2. Main Chat Bubble + Shield Emblem
    # Centered Bubble Dimensions
    $bubbleLeft = 100.0 * $scale
    $bubbleTop = 90.0 * $scale
    $bubbleWidth = 312.0 * $scale
    $bubbleHeight = 280.0 * $scale
    $bubbleRadius = 60.0 * $scale

    $bubblePath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bRect = New-Object System.Drawing.RectangleF $bubbleLeft, $bubbleTop, $bubbleWidth, $bubbleHeight
    $bDiameter = $bubbleRadius * 2

    # Top-Left
    $bubblePath.AddArc($bRect.X, $bRect.Y, $bDiameter, $bDiameter, 180, 90)
    # Top-Right
    $bubblePath.AddArc($bRect.Right - $bDiameter, $bRect.Y, $bDiameter, $bDiameter, 270, 90)
    # Bottom-Right
    $bubblePath.AddArc($bRect.Right - $bDiameter, $bRect.Bottom - $bDiameter, $bDiameter, $bDiameter, 0, 90)
    
    # Bottom speech tail:
    $tailTipX = 140.0 * $scale
    $tailTipY = ($bubbleTop + $bubbleHeight + 45.0 * $scale)
    $bubblePath.AddLine(($bubbleLeft + 160.0 * $scale), $bRect.Bottom, $tailTipX, $tailTipY)
    $bubblePath.AddLine($tailTipX, $tailTipY, ($bubbleLeft + 110.0 * $scale), $bRect.Bottom)

    # Bottom-Left
    $bubblePath.AddArc($bRect.X, $bRect.Bottom - $bDiameter, $bDiameter, $bDiameter, 90, 90)
    $bubblePath.CloseFigure()

    # Vibrant Gradient (Indigo to Cyan/Emerald)
    $gradStart = [System.Drawing.Color]::FromArgb(255, 99, 102, 241) # Vibrant Indigo
    $gradEnd = [System.Drawing.Color]::FromArgb(255, 16, 185, 129)   # Emerald / Cyan
    $bubbleBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF $bubbleLeft, $bubbleTop),
        (New-Object System.Drawing.PointF ($bubbleLeft + $bubbleWidth), ($bubbleTop + $bubbleHeight + 45.0 * $scale)),
        $gradStart,
        $gradEnd
    )
    $g.FillPath($bubbleBrush, $bubblePath)
    $bubbleBrush.Dispose()
    $bubblePath.Dispose()

    # 3. Vault Padlock Icon (Center of Bubble)
    $centerX = 256.0 * $scale
    $centerY = 220.0 * $scale

    # Padlock Shackle (Arch)
    $shackleWidth = 70.0 * $scale
    $shackleHeight = 70.0 * $scale
    $shackleThickness = 14.0 * $scale
    $shackleX = $centerX - ($shackleWidth / 2.0)
    $shackleY = $centerY - 65.0 * $scale

    $shacklePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, $shackleThickness)
    $shacklePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $shacklePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    $shacklePath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $shacklePath.AddArc($shackleX, $shackleY, $shackleWidth, $shackleHeight, 180, 180)
    $shacklePath.AddLine($shackleX, ($shackleY + $shackleHeight / 2), $shackleX, ($shackleY + $shackleHeight * 0.9))
    $shacklePath.AddLine(($shackleX + $shackleWidth), ($shackleY + $shackleHeight / 2), ($shackleX + $shackleWidth), ($shackleY + $shackleHeight * 0.9))
    $g.DrawPath($shacklePen, $shacklePath)
    $shacklePen.Dispose()
    $shacklePath.Dispose()

    # Padlock Body (Rounded Rect)
    $bodyWidth = 104.0 * $scale
    $bodyHeight = 84.0 * $scale
    $bodyRadius = 16.0 * $scale
    $bodyX = $centerX - ($bodyWidth / 2.0)
    $bodyY = $centerY - 10.0 * $scale

    $bodyRect = New-Object System.Drawing.RectangleF $bodyX, $bodyY, $bodyWidth, $bodyHeight
    $bodyPath = Create-RoundedRectanglePath $bodyRect $bodyRadius
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillPath($whiteBrush, $bodyPath)
    $whiteBrush.Dispose()
    $bodyPath.Dispose()

    # Padlock Keyhole Dot & Slot (Indigo cutout)
    $keyholeColor = [System.Drawing.Color]::FromArgb(255, 79, 70, 229)
    $khBrush = New-Object System.Drawing.SolidBrush($keyholeColor)
    $khDotRadius = 8.0 * $scale
    $g.FillEllipse($khBrush, ($centerX - $khDotRadius), ($bodyY + 24.0 * $scale), ($khDotRadius * 2), ($khDotRadius * 2))

    $khSlotWidth = 7.0 * $scale
    $khSlotHeight = 16.0 * $scale
    $g.FillRectangle($khBrush, ($centerX - $khSlotWidth / 2.0), ($bodyY + 30.0 * $scale), $khSlotWidth, $khSlotHeight)
    $khBrush.Dispose()

    $g.Dispose()
    return $bmp
}

# Ensure directories exist
$frontendDir = "D:\Projects\ChatAPP\frontend"
$assetImagesDir = Join-Path $frontendDir "assets\images"
if (-not (Test-Path $assetImagesDir)) { New-Item -ItemType Directory -Path $assetImagesDir -Force }

# 1. Generate master 512x512
$master = Generate-VaultChatLogo 512
$masterPath = Join-Path $assetImagesDir "logo.png"
$master.Save($masterPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Saved Master Logo: $masterPath"

# 2. Generate Native Splash Logo (256x256)
$splashBmp = New-Object System.Drawing.Bitmap $master, (New-Object System.Drawing.Size 256, 256)
$splashDir = Join-Path $frontendDir "android\app\src\main\res\drawable"
$splashPath = Join-Path $splashDir "splash_logo.png"
$splashBmp.Save($splashPath, [System.Drawing.Imaging.ImageFormat]::Png)
$splashBmp.Dispose()
Write-Host "Saved Splash Logo: $splashPath"

# 3. Generate Android Mipmap Icons
$resDir = Join-Path $frontendDir "android\app\src\main\res"
$mipmapSizes = @{
    "mipmap-mdpi" = 48
    "mipmap-hdpi" = 72
    "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144
    "mipmap-xxxhdpi" = 192
}

foreach ($folder in $mipmapSizes.Keys) {
    $dim = $mipmapSizes[$folder]
    $iconBmp = New-Object System.Drawing.Bitmap $master, (New-Object System.Drawing.Size $dim, $dim)
    $targetPath = Join-Path $resDir "$folder\ic_launcher.png"
    $iconBmp.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $iconBmp.Dispose()
    Write-Host "Saved Icon ($dim x $dim): $targetPath"
}

# 4. Web icons & favicon
$webIconsDir = Join-Path $frontendDir "web\icons"
if (Test-Path $webIconsDir) {
    $i192 = New-Object System.Drawing.Bitmap $master, (New-Object System.Drawing.Size 192, 192)
    $i192.Save((Join-Path $webIconsDir "Icon-192.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $i192.Save((Join-Path $webIconsDir "Icon-maskable-192.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $i192.Dispose()

    $i512 = New-Object System.Drawing.Bitmap $master, (New-Object System.Drawing.Size 512, 512)
    $i512.Save((Join-Path $webIconsDir "Icon-512.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $i512.Save((Join-Path $webIconsDir "Icon-maskable-512.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $i512.Dispose()
}

$favBmp = New-Object System.Drawing.Bitmap $master, (New-Object System.Drawing.Size 64, 64)
$favBmp.Save((Join-Path $frontendDir "web\favicon.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$favBmp.Dispose()

$master.Dispose()
Write-Host "All icons generated successfully!" -ForegroundColor Green
