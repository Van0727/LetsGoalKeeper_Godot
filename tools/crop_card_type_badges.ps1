# 从已确认的 941×1672 参考截图裁切类型徽章；只清除连通外角底色并高质量缩放，保留原图文字与色块。
param([Parameter(Mandatory=$true)][string]$ReferencePath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectPath = Split-Path $PSScriptRoot -Parent
$outputPath = Join-Path $projectPath 'assets/ui/cards'
$source = [System.Drawing.Bitmap]::FromFile($ReferencePath)
try {
    if ($source.Width -ne 941 -or $source.Height -ne 1672) { throw '参考图尺寸与裁切坐标不一致，禁止继续写入。' }
    $badges = @(
        @{Name='card_type_skill';X=106;Y=1199;W=129;H=33;Width=49},
        @{Name='card_type_defense';X=410;Y=1199;W=123;H=33;Width=47},
        @{Name='card_type_attack';X=705;Y=1199;W=131;H=33;Width=50}
    )
    foreach ($badge in $badges) {
        $crop = $source.Clone([System.Drawing.Rectangle]::new($badge.X,$badge.Y,$badge.W,$badge.H), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        # 外角浅色底通过连通搜索去除；徽章内部深色字形及彩色背景不会被修改。
        $queue = [System.Collections.Generic.Queue[int]]::new()
        $visited = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($corner in @(0,($badge.W-1),($badge.W*($badge.H-1)),($badge.W*$badge.H-1))) { $queue.Enqueue($corner) }
        while ($queue.Count -gt 0) {
            $index = $queue.Dequeue()
            if (-not $visited.Add($index)) { continue }
            $x = $index % $badge.W
            $y = [int][Math]::Floor($index / $badge.W)
            $color = $crop.GetPixel($x,$y)
            $maximum = [Math]::Max($color.R,[Math]::Max($color.G,$color.B))
            $minimum = [Math]::Min($color.R,[Math]::Min($color.G,$color.B))
            if ($minimum -le 215 -or ($maximum-$minimum) -ge 32) { continue }
            $crop.SetPixel($x,$y,[System.Drawing.Color]::Transparent)
            if ($x -gt 0) { $queue.Enqueue($index-1) }
            if ($x -lt $badge.W-1) { $queue.Enqueue($index+1) }
            if ($y -gt 0) { $queue.Enqueue($index-$badge.W) }
            if ($y -lt $badge.H-1) { $queue.Enqueue($index+$badge.W) }
        }
        $result = [System.Drawing.Bitmap]::new($badge.Width,13,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($result)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($crop,[System.Drawing.Rectangle]::new(0,0,$badge.Width,13))
        $result.Save((Join-Path $outputPath ($badge.Name+'.png')),[System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $result.Dispose()
        $crop.Dispose()
        Write-Output ($badge.Name+' '+$badge.Width+'x13')
    }
} finally { $source.Dispose() }
