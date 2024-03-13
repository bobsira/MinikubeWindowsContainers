
param(
    [string]$SwitchName = "Default Switch",

    [Parameter(Mandatory=$true)]
    [string]$VMName
)

if ($VMName) {
    try{
        Stop-VM -Name $VMName -Force
        Remove-Vm -Name $VMName -Force

        $dirPath = "C:\Users\$env:USERNAME\.minikube\machines\$VMName"
        
        if (Test-Path $dirPath) {
            Remove-Item -Path $dirPath -Recurse -Force
            "{0} - * The $dirPath directory has been removed." -f (Get-Date) >> logs
        }
        else {
            Write-Warning "The $dirPath directory doesn't exist."
        }

        "{0} - * The $VMName Virtual Machine has been removed." -f (Get-Date) > logs
    }
    catch {
        Write-Warning "Couldn't remove the $VMName Virtual Machine. It doesn't exist. $_"
    }
    
}
else {
    Write-Warning "VMName is required"
}