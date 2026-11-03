param([switch]$WithoutCover)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskRoot = Split-Path $PSScriptRoot
$taskMod = Join-Path $taskRoot 'SuQingWeightTraining\42'

# Deterministic format/size exports. The illustrations themselves are generated
# with imagegen; the tiny category glyph is authored as native vector geometry.
function Save-ScaledPng([string]$Source, [string]$Destination, [int]$Size) {
    $taskImage = [Drawing.Image]::FromFile($Source)
    $taskBitmap = [Drawing.Bitmap]::new($Size,$Size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $taskGraphics = [Drawing.Graphics]::FromImage($taskBitmap)
    try {
        if ($taskImage.Width -ne $taskImage.Height) { throw 'Square source required; cropping is not allowed' }
        $taskGraphics.Clear([Drawing.Color]::Transparent)
        $taskGraphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $taskGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $taskAttributes = [Drawing.Imaging.ImageAttributes]::new()
        try {
            $taskAttributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $taskGraphics.DrawImage($taskImage,[Drawing.Rectangle]::new(0,0,$Size,$Size),0,0,$taskImage.Width,$taskImage.Height,[Drawing.GraphicsUnit]::Pixel,$taskAttributes)
        } finally { $taskAttributes.Dispose() }
        New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
        $taskBitmap.Save($Destination,[Drawing.Imaging.ImageFormat]::Png)
    } finally { $taskGraphics.Dispose(); $taskBitmap.Dispose(); $taskImage.Dispose() }
}

function Save-CategoryGlyph([string]$Destination,[int]$Size) {
    [xml]$taskSvg = Get-Content -LiteralPath (Join-Path $taskRoot 'art\category-training-belt.svg') -Raw
    $taskBitmap = [Drawing.Bitmap]::new($Size,$Size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $taskGraphics = [Drawing.Graphics]::FromImage($taskBitmap)
    $taskBrush = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($taskSvg.svg.g.fill))
    try {
        $taskGraphics.Clear([Drawing.Color]::Transparent)
        $taskGraphics.ScaleTransform($Size/128.0,$Size/128.0)
        $taskGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        foreach($taskNode in $taskSvg.svg.g.ChildNodes) {
            $taskPath = [Drawing.Drawing2D.GraphicsPath]::new()
            try {
                if($taskNode.LocalName -eq 'rect') {
                    $x=[single]$taskNode.x; $y=[single]$taskNode.y; $w=[single]$taskNode.width; $h=[single]$taskNode.height; $d=2*[single]$taskNode.rx
                    $taskPath.AddArc($x,$y,$d,$d,180,90)
                    $taskPath.AddArc($x+$w-$d,$y,$d,$d,270,90)
                    $taskPath.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90)
                    $taskPath.AddArc($x,$y+$h-$d,$d,$d,90,90)
                    $taskPath.CloseFigure()
                } elseif($taskNode.LocalName -eq 'path') {
                    $taskTokens = [regex]::Matches($taskNode.d,'[MLHVZ]|-?\d+(?:\.\d+)?')
                    $i=0; $x=[single]0; $y=[single]0
                    while($i -lt $taskTokens.Count) {
                        $taskCommand=$taskTokens[$i++].Value
                        switch($taskCommand) {
                            'M' { $x=[single]$taskTokens[$i++].Value; $y=[single]$taskTokens[$i++].Value; $taskPath.StartFigure() }
                            'L' { $nx=[single]$taskTokens[$i++].Value; $ny=[single]$taskTokens[$i++].Value; $taskPath.AddLine($x,$y,$nx,$ny); $x=$nx; $y=$ny }
                            'H' { $nx=[single]$taskTokens[$i++].Value; $taskPath.AddLine($x,$y,$nx,$y); $x=$nx }
                            'V' { $ny=[single]$taskTokens[$i++].Value; $taskPath.AddLine($x,$y,$x,$ny); $y=$ny }
                            'Z' { $taskPath.CloseFigure() }
                            default { throw "Unsupported vector command $taskCommand" }
                        }
                    }
                    $taskPath.FillMode=[Drawing.Drawing2D.FillMode]::Alternate
                } else { throw "Unsupported SVG element $($taskNode.LocalName)" }
                $taskGraphics.FillPath($taskBrush,$taskPath)
            } finally { $taskPath.Dispose() }
        }
        New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
        $taskBitmap.Save($Destination,[Drawing.Imaging.ImageFormat]::Png)
    } finally { $taskBrush.Dispose(); $taskGraphics.Dispose(); $taskBitmap.Dispose() }
}

Save-ScaledPng (Join-Path $taskRoot 'art\masters\training-belt-master.png') (Join-Path $taskMod 'media\textures\Item_SQWT_TrainingBelt.png') 128
Save-ScaledPng (Join-Path $taskRoot 'art\masters\training-belt-master.png') (Join-Path $taskMod 'icon.png') 128
Save-CategoryGlyph (Join-Path $taskMod 'media\ui\CategoryIcon\SuQingTrainingBelt.png') 128
Save-CategoryGlyph (Join-Path $taskRoot 'art\category-preview-32.png') 32
Save-ScaledPng (Join-Path $taskRoot 'art\masters\training-belt-master.png') (Join-Path $taskRoot 'art\item-preview-64.png') 64
if(-not $WithoutCover) {
    Save-ScaledPng (Join-Path $taskRoot 'art\masters\cover-master.png') (Join-Path $taskMod 'poster.png') 512
    Save-ScaledPng (Join-Path $taskRoot 'art\masters\cover-master.png') (Join-Path $taskRoot 'publishing\preview.png') 256
    Save-ScaledPng (Join-Path $taskRoot 'art\masters\cover-master.png') (Join-Path $taskRoot 'publishing\cover-1024.png') 1024
}
Write-Output 'Artwork exports complete.'
