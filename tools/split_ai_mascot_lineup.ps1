param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

Add-Type -AssemblyName System.Drawing

$source = [System.Drawing.Bitmap]::new($InputPath)
try {
    $regions = @(
        @{ Name = 'mira'; Left = 20; Width = 540 },
        @{ Name = 'nia'; Left = 610; Width = 495 },
        @{ Name = 'aira'; Left = 1125; Width = 500 },
        @{ Name = 'kiro'; Left = 1615; Width = 557 }
    )

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    foreach ($region in $regions) {
        $rectangle = [System.Drawing.Rectangle]::new($region.Left, 0, $region.Width, $source.Height)
        $character = $source.Clone($rectangle, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $outputPath = Join-Path $OutputDirectory ($region.Name + '.png')
            $character.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $character.Dispose()
        }
    }
} finally {
    $source.Dispose()
}
