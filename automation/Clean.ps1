
param(
    [string]$SwitchName = "Default Switch",

    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter()]
    [string]$Platform = "Hyper-V"
)

if ($VMName) {
    try{
        if ($Platform -eq "Hyper-V") {
            $dirPath = "C:\Users\$env:USERNAME\.minikube\machines\$VMName"
            Stop-VM -Name $VMName -Force
            Remove-Vm -Name $VMName -Force
        }
        elseif ($Platform -eq "VirtualBox") {
            $dirPath = "C:\Users\$env:USERNAME\VirtualBox VMs\$VMName"
            & VBoxManage controlvm $VMName poweroff --type headless
            & VBoxManage unregistervm $VMName --delete
        }
        Start-Sleep -Seconds 10
    }
    catch {
        Write-Warning "Couldn't stop the $VMName Virtual Machine. It doesn't exist. $_"
    }
    try{
        if (Test-Path $dirPath) {
            Remove-Item -Path $dirPath -Recurse -Force
            "{0} - * The $dirPath directory has been removed." -f (Get-Date) >> logs
            $VHDPath = "${env:homepath}\VirtualBox VMs\$VMName\VHD.vhdx"
            # Unregister and delete the existing hard disk if it exists
            if (Test-Path $VHDPath) {
                & VBoxManage closemedium disk $VHDPath --delete
            }
        }
        else {
            Write-Warning "The $dirPath directory doesn't exist."
        }

        "{0} - * The $VMName Virtual Machine has been removed." -f (Get-Date) > logs
    }
    catch {
        Write-Warning "Couldn't remove the $VMName directory. It doesn't exist. $_"
    }
}
else {
    Write-Warning "VMName is required"
}