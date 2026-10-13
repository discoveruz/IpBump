# Draws IpBump's icon (orange tile, white "IP" over a "next" arrow) and writes it as a multi-size .ico.
# Run it again after changing the design:   powershell -File tools\make-icon.ps1
param(
    [string] $Out = (Join-Path $PSScriptRoot '..\IpBump\Assets\IpBump.ico'),
    [string] $Preview = ''     # optional .png showing every size side by side
)

Add-Type -AssemblyName System.Drawing

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256

function New-RoundedSquare([single] $size, [single] $radius) {
    $d = $radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($size - $d, 0, $d, $d, 270, 90)
    $path.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
    $path.AddArc(0, $size - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $path
}

function New-IconBitmap([int] $s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # Tile: the same orange as the tray icon, slightly lighter at the top
    $tile = New-RoundedSquare $s ($s * 0.22)
    $rect = New-Object System.Drawing.RectangleF 0, 0, $s, $s
    $top = [System.Drawing.Color]::FromArgb(240, 140, 96)
    $bottom = [System.Drawing.Color]::FromArgb(222, 104, 62)
    $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 90.0
    $g.FillPath($fill, $tile)

    # Small sizes carry only the letters; from 32 px up there is room for the arrow underneath
    $withArrow = $s -ge 32
    $em = if ($withArrow) { $s * 0.50 } else { $s * 0.66 }
    $centerY = if ($withArrow) { $s * 0.40 } else { $s * 0.50 }

    $white = [System.Drawing.Brushes]::White
    $font = New-Object System.Drawing.Font 'Segoe UI', $em, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat ([System.Drawing.StringFormatFlags]::NoWrap -bor [System.Drawing.StringFormatFlags]::NoClip)
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $box = New-Object System.Drawing.RectangleF (-$s), ($centerY - $s), ($s * 3), ($s * 2)
    $g.DrawString('IP', $font, $white, $box, $format)

    if ($withArrow) {
        $y = $s * 0.76
        $x1 = $s * 0.27; $x2 = $s * 0.73
        $w = [Math]::Max(2.0, $s * 0.075)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), $w
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $head = $s * 0.11
        $g.DrawLine($pen, [single]$x1, [single]$y, [single]$x2, [single]$y)
        $g.DrawLines($pen, [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF ($x2 - $head), ($y - $head)),
            (New-Object System.Drawing.PointF $x2, $y),
            (New-Object System.Drawing.PointF ($x2 - $head), ($y + $head))))
        $pen.Dispose()
    }

    $font.Dispose(); $format.Dispose(); $fill.Dispose(); $tile.Dispose(); $g.Dispose()
    $bmp
}

# One .ico entry: PNG for 256 px, classic 32-bit bitmap for the rest (what every Windows tool understands)
function Get-IconEntry([System.Drawing.Bitmap] $bmp) {
    $s = $bmp.Width
    $ms = New-Object System.IO.MemoryStream
    if ($s -ge 256) {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        return , $ms.ToArray()
    }

    $bw = New-Object System.IO.BinaryWriter $ms
    $maskRow = [int]([Math]::Floor(($s + 31) / 32) * 4)
    $bw.Write([int]40); $bw.Write([int]$s); $bw.Write([int]($s * 2))       # header size, width, height (image + mask)
    $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]0)           # planes, bits per pixel, no compression
    $bw.Write([int]($s * $s * 4 + $maskRow * $s))
    $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)

    $area = New-Object System.Drawing.Rectangle 0, 0, $s, $s
    $data = $bmp.LockBits($area, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $row = New-Object byte[] ($s * 4)
    for ($y = $s - 1; $y -ge 0; $y--) {                                     # bitmap rows are stored bottom-up
        [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($data.Scan0, $y * $data.Stride), $row, 0, $row.Length)
        $bw.Write($row)
    }
    $bmp.UnlockBits($data)
    $bw.Write((New-Object byte[] ($maskRow * $s)))                          # transparency comes from the alpha channel
    $bw.Flush()
    return , $ms.ToArray()
}

$bitmaps = $sizes | ForEach-Object { New-IconBitmap $_ }
$entries = $bitmaps | ForEach-Object { , (Get-IconEntry $_) }

$Out = [System.IO.Path]::GetFullPath($Out)
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Out))
$file = [System.IO.File]::Create($Out)
$w = New-Object System.IO.BinaryWriter $file
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$sizes.Count)      # reserved, type = icon, number of images
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }                # 0 means 256
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int]$entries[$i].Length); $w.Write([int]$offset)
    $offset += $entries[$i].Length
}
foreach ($e in $entries) { $w.Write([byte[]]$e) }
$w.Dispose(); $file.Dispose()
Write-Host "Wrote $Out ($((Get-Item -LiteralPath $Out).Length) bytes, sizes: $($sizes -join ', '))"

if ($Preview) {
    $pad = 12
    [int] $width = ($sizes | Measure-Object -Sum).Sum + $pad * ($sizes.Count + 1)
    [int] $height = 256 + 2 * $pad
    foreach ($background in 'dark', 'light') {
        $sheet = New-Object System.Drawing.Bitmap $width, $height
        $g = [System.Drawing.Graphics]::FromImage($sheet)
        $g.Clear($(if ($background -eq 'dark') { [System.Drawing.Color]::FromArgb(32, 32, 32) } else { [System.Drawing.Color]::FromArgb(243, 243, 243) }))
        $x = $pad
        foreach ($b in $bitmaps) { $g.DrawImageUnscaled($b, $x, $pad); $x += $b.Width + $pad }
        $g.Dispose()
        $path = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetFullPath($Preview), "$background.png")
        $sheet.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $sheet.Dispose()
        Write-Host "Preview: $path"
    }
}
$bitmaps | ForEach-Object { $_.Dispose() }
