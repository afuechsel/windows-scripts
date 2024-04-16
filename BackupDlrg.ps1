Write-Host "Deleting all network connections"
net use * /delete /yes >NUL

$Servers = @('192.168.100.26')
$Backup = E:

foreach ($Server in $Servers)
{
    (net view $Server /all) | ForEach-Object {
        if($_.IndexOf(' Platte ') -gt 0)
        {
            $shareName = $_.Split('  ')[0]
            Write-Host "Backing Up \\$Server\$shareName"
            net use x: /persistent:yes "\\$Server\$shareName" >NUL
            Robocopy "\\$Server\$shareName" "$Backup\$shareName" /MIR /FFT /Z /XA:H /W:5 /NDL /NJS /NJH
            net use x: /delete /yes >NUL
        }
    }
}

