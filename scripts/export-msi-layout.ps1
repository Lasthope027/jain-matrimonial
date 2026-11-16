param([Parameter(Mandatory=$true)][string]$Msi, [Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
$installer = New-Object -ComObject WindowsInstaller.Installer
$db = $installer.OpenDatabase($Msi, 0)
$result = @{}
foreach ($table in @('Directory', 'Component', 'File', 'Media')) {
    $query = switch ($table) {
        Directory { 'SELECT `Directory`,`Directory_Parent`,`DefaultDir` FROM `Directory`' }
        Component { 'SELECT `Component`,`Directory_` FROM `Component`' }
        File { 'SELECT `File`,`Component_`,`FileName` FROM `File`' }
        Media { 'SELECT `Cabinet` FROM `Media`' }
    }
    $view = $db.OpenView($query)
    $view.Execute()
    $rows = [System.Collections.Generic.List[object]]::new()
    while ($null -ne ($record = $view.Fetch())) {
        $values = @()
        $count = switch ($table) { Directory {3} Component {2} File {3} Media {1} }
        for ($i=1; $i -le $count; $i++) { $values += $record.StringData($i) }
        $rows.Add($values)
    }
    $result[$table] = $rows.ToArray()
    $view.Close()
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Output -Encoding utf8
