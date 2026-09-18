# 类型标签矢量重建：统一 200×52，使用纯色背景，保留英文与胶囊轮廓；文字转路径供 Godot 导入。
# 不放大小图、不裁切或缩放已确认插画；只生成独立的高分辨率标签资源。
Add-Type -AssemblyName System.Drawing
$badgeOutputDirectory = Join-Path $PSScriptRoot '../assets/ui/cards'
$badgeDefinitions = @(
    @{ Name = 'attack'; Text = 'ATTACK'; Color = '#FFD1CA' },
    @{ Name = 'defense'; Text = 'DEFENSE'; Color = '#92EFFF' },
    @{ Name = 'skill'; Text = 'SKILL'; Color = '#9AFFC4' }
)
function Format-BadgeNumber([single] $Value) {
    return $Value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}
foreach ($badge in $badgeDefinitions) {
    $badgePath = [Drawing.Drawing2D.GraphicsPath]::new()
    $badgeFamily = [Drawing.FontFamily]::new('Arial')
    $badgePath.AddString($badge.Text, $badgeFamily, [int][Drawing.FontStyle]::Bold, 36,
        [Drawing.PointF]::new(0, 0), [Drawing.StringFormat]::GenericTypographic)
    $badgeBounds = $badgePath.GetBounds()
    # 统一字高 28，文字居中；防御标签最长时也不挤压胶囊的圆角区域。
    $badgeScale = [Math]::Min(28 / $badgeBounds.Height, 160 / $badgeBounds.Width)
    $badgeTransform = [Drawing.Drawing2D.Matrix]::new()
    $badgeTransform.Translate([single](100 - $badgeBounds.Width * $badgeScale / 2),
        [single](26 - $badgeBounds.Height * $badgeScale / 2))
    $badgeTransform.Scale([single]$badgeScale, [single]$badgeScale)
    $badgeTransform.Translate(-$badgeBounds.X, -$badgeBounds.Y)
    $badgePath.Transform($badgeTransform)
    $badgePoints = $badgePath.PathPoints
    $badgeTypes = $badgePath.PathTypes
    $badgeCommands = [Collections.Generic.List[string]]::new()
    for ($badgeIndex = 0; $badgeIndex -lt $badgePoints.Length; $badgeIndex++) {
        $badgeKind = $badgeTypes[$badgeIndex] -band 7
        $badgeCommand = if ($badgeKind -eq 0) { 'M' } elseif ($badgeKind -eq 1) { 'L' } else { 'C' }
        $badgeSegment = "$badgeCommand $(Format-BadgeNumber $badgePoints[$badgeIndex].X) $(Format-BadgeNumber $badgePoints[$badgeIndex].Y)"
        if ($badgeKind -eq 3) {
            for ($badgeControl = 0; $badgeControl -lt 2; $badgeControl++) {
                $badgeIndex++
                $badgeSegment += " $(Format-BadgeNumber $badgePoints[$badgeIndex].X) $(Format-BadgeNumber $badgePoints[$badgeIndex].Y)"
            }
        }
        if (($badgeTypes[$badgeIndex] -band 128) -ne 0) { $badgeSegment += ' Z' }
        $badgeCommands.Add($badgeSegment)
    }
    $badgeSvg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="52" viewBox="0 0 200 52">
  <rect x="1" y="1" width="198" height="50" rx="25" fill="$($badge.Color)" stroke="#FFFFFF" stroke-width="2"/>
  <path d="$($badgeCommands -join ' ')" fill="#06162B"/>
</svg>
"@
    [IO.File]::WriteAllText((Join-Path $badgeOutputDirectory "card_type_$($badge.Name)_hires.svg"),
        $badgeSvg, [Text.UTF8Encoding]::new($false))
    $badgeTransform.Dispose()
    $badgePath.Dispose()
    $badgeFamily.Dispose()
}
