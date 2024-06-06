param(
    [string]$SwitchName = "Default Switch",

    [Parameter(Mandatory=$true)]
    [string]$ISOFilePath,

    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$true)]
    [string]$UserName,

    [Parameter(Mandatory=$true)]
    [string]$Pass,

    [string]$KubernetesVersion,

    [ValidateSet("Hyper-V", "VirtualBox", "QEMU")]
    [string]$Platform = "Hyper-V"
)

Import-Module -Name "$PSScriptRoot\k8Tools.psm1" -Force

if ([string]::IsNullOrEmpty($KubernetesVersion)) {
    $KubernetesVersion = Get-k8LatestVersion
    Write-Output "* The latest Kubernetes version is $KubernetesVersion"
    $KubernetesVersion = $KubernetesVersion.TrimStart('v')
}

"{0} - * Starting the $VMName Virtual Machine ..." -f (Get-Date) > logs
Write-Output "* Starting the $VMName Virtual Machine ..."

if ($Platform -eq "Hyper-V") {
    $VM = @{
        Name = $VMName;
        Generation = 1;
        MemoryStartupBytes = 1GB;
        NewVHDPath = "${env:homepath}\.minikube\machines\$VMName\VHD.vhdx";
        NewVHDSizeBytes = 15GB;
        BootDevice = "VHD";
        Path = "${env:homepath}\.minikube\machines\";
        SwitchName = $SwitchName
    }  
    Write-Output "* Please wait as we set up the $VMName Virtual Machine ..."
    "{0} - Please wait as we set up the $VMName Virtual Machine ..." -f (Get-Date) >> logs
    New-VM @VM | Out-Null
    Set-VM -Name $VMName -ProcessorCount 2 -AutomaticCheckpointsEnabled $false
    Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
    Set-VMDvdDrive -VMName $VMName -Path $ISOFilePath
    Start-VM -Name $VMName | Out-Null

    $timeout = 600 
    $retryInterval = 15 
    $elapsedTime = 0

    do {
        Start-Sleep -Seconds $retryInterval

        "{0} - Waiting for the VM to start  ..." -f (Get-Date) >> logs
        $heartbeat = Get-VMIntegrationService -VMName $VMName -Name "Heartbeat"
        $elapsedTime += $retryInterval

        if ($elapsedTime -ge $timeout) {
            Write-Output "* Timeout reached. Unable to start the VM ..."
            Write-Output "* Exiting the script ..."
            "Timeout reached. Exiting the script ..." >> logs
            "Exiting the script ..." >> logs
            exit
        }
    } while ($heartbeat.PrimaryStatusDescription -ne "OK")

    Write-Output "* The $VMName Virtual Machine is started ..."

    $SecurePassword = ConvertTo-SecureString -String $Pass -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword

    $VMStatus = Get-VM -Name $VMName | Select-Object -ExpandProperty State

    $VMName = Get-VM | Select-Object -ExpandProperty Name

    if ($VMStatus -eq 'Running') {
        "The $VMName Virtual Machine is running" >> logs

        $retryInterval = 45 
        $timeout = 120 
        $elapsedTime = 0
        
        do {
            try {
                $os = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock { Get-WmiObject -Query "SELECT * FROM Win32_OperatingSystem" } -ErrorAction Stop
                
                if ($os) {
                    Write-Output "* Windows is successfully installed on $VMName"
                    "Windows is successfully installed on $VMName" >> logs
                    . .\Run.ps1
                    RUN -VMName $VMName -UserName $UserName -Pass $Pass -Credential $Credential -KubernetesVersion $KubernetesVersion
                    break
                } else {
                    Write-Output "* Windows is not installed on $VMName"
                }
            } catch {
                Write-Output "* An error occurred while checking if Windows is installed on ${VMName}: $_"
            }
            Start-Sleep -Seconds $retryInterval
            $elapsedTime += $retryInterval
        } while ($elapsedTime -lt $timeout)

    } else {
        Write-Output "The VM $VMName is not running"
    }

} elseif ($Platform -eq "VirtualBox") {
    $VM = @{
        Name = $VMName;
        OSType = "Windows10_64";
        Register = $true;
        BaseFolder = "${env:homepath}\VirtualBox VMs";
    }
    & VBoxManage createvm --name $VM.Name --ostype $VM.OSType --register --basefolder $VM.BaseFolder
    & VBoxManage modifyvm $VMName --cpus 2 --memory 1024 | Out-Null
    & VBoxManage createmedium disk --filename "${env:homepath}\VirtualBox VMs\$VMName\VHD.vhdx" --size 15000 | Out-Null
    & VBoxManage storagectl $VMName --name "IDE Controller" --add ide
    & VBoxManage storageattach $VMName --storagectl "IDE Controller" --port 0 --device 0 --type hdd --medium "${env:homepath}\VirtualBox VMs\$VMName\VHD.vhdx" | Out-Null     
    & VBoxManage storageattach $VMName --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium $ISOFilePath | Out-Null
    & VBoxManage startvm $VMName --type headless | Out-Null
    $runningVMs = & VBoxManage list runningvms
    if ($runningVMs -like "*$VMName*") {
        Write-Output "The $VMName Virtual Machine is running" >> logs
        $retryInterval = 45 
        $timeout = 120 
        $elapsedTime = 0
        do {
            try {
                $os = & VBoxManage guestproperty get $VMName "/VirtualBox/GuestInfo/OS/Product"
                if ($os) {
                    Write-Output "* Windows is successfully installed on $VMName"
                    "Windows is successfully installed on $VMName" >> logs
                    . .\Run.ps1
                    RUN -VMName $VMName -UserName $UserName -Pass $Pass -Credential $Credential -KubernetesVersion $KubernetesVersion -Platform $Platform
                    break
                } else {
                    Write-Output "* Windows is not installed on $VMName"
                }
            } catch {
                Write-Output "* An error occurred while checking if Windows is installed on ${VMName}: $_"
            }
            Start-Sleep -Seconds $retryInterval
            $elapsedTime += $retryInterval
        } while ($elapsedTime -lt $timeout)
    } else {
        Write-Output "The VM $VMName is not running"
    }

} elseif ($Platform -eq "QEMU") {
    $VM = @{
        Name = $VMName;
        Memory = 1024;
        CPUs = 2; 
        DiskPath = "${env:homepath}\QEMU\$VMName\VHD.vhdx";
        DiskSize = "15G";
        ISOPath = $ISOFilePath;
    }
    $diskPath = $VM.DiskPath
    $diskDir = Split-Path -Path $diskPath -Parent
    if (-Not (Test-Path -Path $diskDir)) {
        New-Item -ItemType Directory -Path $diskDir -Force | Out-Null
    }
    & qemu-img create -f vhdx $VM.DiskPath $VM.DiskSize | Out-Null

    if (-not [int]::TryParse($VM.CPUs, [ref]$null)) {
        Write-Output "Error: CPUs value '$($VM.CPUs)' is not a valid integer."
        exit
    }

    Write-Output "Debug: CPUs value is $($VM.CPUs)"

    & qemu-system-x86_64 -m $VM.Memory -smp $VM.CPUs -drive file="$($VM.DiskPath)",format=vhdx -cdrom "$($VM.ISOPath)" -boot d -net nic -net user,hostfwd=tcp::2222-:22 -machine type=pc

    $timeout = 600 
    $retryInterval = 15 
    $elapsedTime = 0

    do {
        Start-Sleep -Seconds $retryInterval

        "{0} - Waiting for the VM to start  ..." -f (Get-Date) >> logs
        $result = & qemu-system-x86_64 -machine query-status | ConvertFrom-Json
        $elapsedTime += $retryInterval

        if ($elapsedTime -ge $timeout) {
            Write-Output "* Timeout reached. Unable to start the VM ..."
            Write-Output "* Exiting the script ..."
            "Timeout reached. Exiting the script ..." >> logs
            "Exiting the script ..." >> logs
            exit
        }
    } while ($result.Status -ne "running")

    Write-Output "* The $VMName Virtual Machine is started ..."

    $SecurePassword = ConvertTo-SecureString -String $Pass -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword

    $retryInterval = 45 
    $timeout = 120 
    $elapsedTime = 0
    
    do {
        try {
            $os = Invoke-Command -Hostname localhost -Port 2222 -Credential $Credential -ScriptBlock { Get-WmiObject -Query "SELECT * FROM Win32_OperatingSystem" } -ErrorAction Stop
            
            if ($os) {
                Write-Output "* Windows is successfully installed on $VMName"
                "Windows is successfully installed on $VMName" >> logs
                . .\Run.ps1
                RUN -VMName $VMName -UserName $UserName -Pass $Pass -Credential $Credential -KubernetesVersion $KubernetesVersion
                break
            } else {
                Write-Output "* Windows is not installed on $VMName"
            }
        } catch {
            Write-Output "* An error occurred while checking if Windows is installed on ${VMName}: $_"
        }
        Start-Sleep -Seconds $retryInterval
        $elapsedTime += $retryInterval
    } while ($elapsedTime -lt $timeout)
} else {
    Write-Output "* Unsupported platform specified: $Platform"
    exit
}
    