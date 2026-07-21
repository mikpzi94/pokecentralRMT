param(
  [string]$InputPath = (Join-Path $PSScriptRoot '..\assets\pack-icones.png'),
  [string]$OutputRoot = (Join-Path $PSScriptRoot '..\icons\ui')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$names = @(
  'hub', 'rentabilidade', 'preco', 'loja',
  'leilao', 'conta', 'vender-pokemon', 'confiavel',
  'valor-fixo', 'aceita-propostas', 'compartilhar', 'denunciar'
)

function Test-BackgroundPixel([System.Drawing.Color]$color) {
  if ($color.A -eq 0) { return $true }
  $max = [Math]::Max($color.R, [Math]::Max($color.G, $color.B))
  $min = [Math]::Min($color.R, [Math]::Min($color.G, $color.B))
  $light = ($color.R + $color.G + $color.B) / 3
  return (($max - $min) -le 16 -and $light -ge 145 -and $light -le 248)
}

function Remove-ConnectedBackground([System.Drawing.Bitmap]$bitmap) {
  $width = $bitmap.Width
  $height = $bitmap.Height
  $seen = New-Object 'bool[]' ($width * $height)
  $queue = [System.Collections.Generic.Queue[int]]::new()

  function Add-EdgePixel([int]$x, [int]$y) {
    $index = $y * $width + $x
    if (-not $seen[$index] -and (Test-BackgroundPixel $bitmap.GetPixel($x, $y))) {
      $seen[$index] = $true
      $queue.Enqueue($index)
    }
  }

  for ($x = 0; $x -lt $width; $x++) {
    Add-EdgePixel $x 0
    Add-EdgePixel $x ($height - 1)
  }
  for ($y = 0; $y -lt $height; $y++) {
    Add-EdgePixel 0 $y
    Add-EdgePixel ($width - 1) $y
  }

  while ($queue.Count -gt 0) {
    $index = $queue.Dequeue()
    $x = $index % $width
    $y = [Math]::Floor($index / $width)
    $bitmap.SetPixel($x, $y, [System.Drawing.Color]::Transparent)

    $neighbors = @(
      @(([int]$x - 1), [int]$y),
      @(([int]$x + 1), [int]$y),
      @([int]$x, ([int]$y - 1)),
      @([int]$x, ([int]$y + 1))
    )
    foreach ($pair in $neighbors) {
      $nx = $pair[0]; $ny = $pair[1]
      if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $width -or $ny -ge $height) { continue }
      $next = $ny * $width + $nx
      if (-not $seen[$next] -and (Test-BackgroundPixel $bitmap.GetPixel($nx, $ny))) {
        $seen[$next] = $true
        $queue.Enqueue($next)
      }
    }
  }
}

function Get-VisibleBounds([System.Drawing.Bitmap]$bitmap) {
  $left = $bitmap.Width; $top = $bitmap.Height; $right = -1; $bottom = -1
  for ($y = 0; $y -lt $bitmap.Height; $y++) {
    for ($x = 0; $x -lt $bitmap.Width; $x++) {
      if ($bitmap.GetPixel($x, $y).A -gt 10) {
        if ($x -lt $left) { $left = $x }
        if ($x -gt $right) { $right = $x }
        if ($y -lt $top) { $top = $y }
        if ($y -gt $bottom) { $bottom = $y }
      }
    }
  }
  if ($right -lt $left -or $bottom -lt $top) { return $null }
  return [System.Drawing.Rectangle]::FromLTRB($left, $top, $right + 1, $bottom + 1)
}

function Resize-PixelArt([System.Drawing.Bitmap]$source, [int]$size) {
  $result = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($result)
  $graphics.Clear([System.Drawing.Color]::Transparent)
  $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $graphics.DrawImage($source, 0, 0, $size, $size)
  $graphics.Dispose()
  return $result
}

$source = [System.Drawing.Bitmap]::new((Resolve-Path $InputPath).Path)
$sizes = @(128, 64, 32, 20)
foreach ($size in $sizes) {
  New-Item -ItemType Directory -Force -Path (Join-Path $OutputRoot $size) | Out-Null
}

for ($row = 0; $row -lt 3; $row++) {
  for ($col = 0; $col -lt 4; $col++) {
    $index = $row * 4 + $col
    $x1 = [Math]::Round($col * $source.Width / 4)
    $x2 = [Math]::Round(($col + 1) * $source.Width / 4)
    $y1 = [Math]::Round($row * $source.Height / 3)
    $y2 = [Math]::Round(($row + 1) * $source.Height / 3)
    $cellRect = [System.Drawing.Rectangle]::new($x1, $y1, $x2 - $x1, $y2 - $y1)
    $cell = $source.Clone($cellRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    Remove-ConnectedBackground $cell

    $bounds = Get-VisibleBounds $cell
    if ($null -eq $bounds) { throw "Nenhum conteúdo encontrado em $($names[$index])" }
    $trimmed = $cell.Clone($bounds, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $cell.Dispose()

    $master = [System.Drawing.Bitmap]::new(128, 128, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($master)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $scale = [Math]::Min(104 / $trimmed.Width, 104 / $trimmed.Height)
    $drawWidth = [Math]::Max(1, [Math]::Round($trimmed.Width * $scale))
    $drawHeight = [Math]::Max(1, [Math]::Round($trimmed.Height * $scale))
    $drawX = [Math]::Floor((128 - $drawWidth) / 2)
    $drawY = [Math]::Floor((128 - $drawHeight) / 2)
    $graphics.DrawImage($trimmed, $drawX, $drawY, $drawWidth, $drawHeight)
    $graphics.Dispose()
    $trimmed.Dispose()

    foreach ($size in $sizes) {
      $out = if ($size -eq 128) { $master.Clone() } else { Resize-PixelArt $master $size }
      $path = Join-Path (Join-Path $OutputRoot $size) ($names[$index] + '.png')
      $out.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
      $out.Dispose()
    }
    $master.Dispose()
  }
}

$source.Dispose()
Write-Output "12 ícones exportados para $OutputRoot"
