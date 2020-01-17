function Get-VMStat {
    $VMS = get-vm 
    $Res = @()
    foreach ($Vm in $VMS) {
        $VMDiskCn0 = (Get-VMHardDiskDrive $Vm.Name  -ControllerNumber 0).path 
        $DisksPathArray = $VMDiskCn0.Split("\")
        [string]$DisksPath = ($DisksPathArray | Select-Object  -SkipLast 1) -join "\"
        if (test-path $DisksPath) {
            $DisksSize = (Get-ChildItem -Path $DisksPath | Measure-Object "Length" -Sum).sum / 1Gb
        }
        Else { Write-host "Disk doesnt exist - $VMDiskCn0"; $DisksSize = 0 }

        $VMData = [PSCustomObject]@{
            Name       = $Vm.name
            State      = $VM.State
            Created    = $Vm.CreationTime
            Gen        = $VM.Generation
            Ver        = $VM.Version
            SnapShots  = (Get-VMSnapshot $VM.Name | Measure-Object).count
            HDDCount   = ($VM | Select-Object -ExpandProperty  HardDrives | Measure-Object).count
            DVDCount   = ($VM | Select-Object -ExpandProperty  DVDDrives | Measure-Object).count
            NetCount   = ($VM | Select-Object -ExpandProperty  NetworkAdapters | Measure-Object).count
            ProcCnt    = $VM.ProcessorCount
            Mem        = $VM.MemoryStartup / 1Mb
            DisksSize  = [math]::round($DisksSize , 2)
            VMPath     = $Vm.path
            VMConfig   = $Vm.configurationlocation
            VMSnapShot = $Vm.snapshotfilelocation
            DisksPath  = $DisksPath 
            DiskCn0    = $VMDiskCn0           
        }
        $Res += $VMData
    }
    return $Res
}

function Remove-AllVMSnapshots ($VM) {
    Remove-VMSnapshot -VMName $VM 
}

Function OptimizeVHD($DiskPath, $Mode = "Full") {
   $Job = Optimize-VHD -Path $DiskPath -Mode $Mode -AsJob
    while ($Job.State -eq "Running") {
        Write-Host "Running optimization $DiskPath."
        start-sleep -Seconds 5    
    }
}

Function MoveVMFirstHDD ($VMName, $DestinationPath) {    
    $VMFirstHDD = (Get-VMHardDiskDrive $VMName | Select-Object *)[0]
    $SourcePath = $VMFirstHDD.Path
    if (Test-Path $SourcePath) {
        if (!(Test-Path $DestinationPath)) {
            New-Item $DestinationPath
        }
        if (Test-Path $DestinationPath) {
            $DestinatioHDDPath = $DestinationPath + ($SourcePath.split("\") | Select-Object -Last 1)
      
            $Job = Copy-Item $SourcePath $DestinatioHDDPath -AsJob 
            while ($Job.State -eq "Running") {
                Write-Host "Running copy $SourcePath to $DestinatioHDDPath"
                start-sleep -Seconds 5    
            }
            if (Test-Path $DestinatioHDDPath) {                
                OptimizeVHD $DestinatioHDDPath
                Remove-Item $SourcePath -Force
                Remove-VMHardDiskDrive -VMname $VMName -ControllerType $VMFirstHDD.ControllerType -ControllerNumber $VMFirstHDD.ControllerNumber -ControllerLocation $VMFirstHDD.ControllerLocation
                Add-VMHardDiskDrive -VMName $VMName -path $DestinatioHDDPath -ControllerType $VMFirstHDD.ControllerType -ControllerNumber $VMFirstHDD.ControllerNumber -ControllerLocation $VMFirstHDD.ControllerLocation             
            }
        }
        Else { write-host "Destination path not found!" }
    }
    Else { write-host "HDD file not found!" }
}

Function VMAction ($VMName, $Action) {
    switch ($Action) {
        "Start" {
            if ((get-vm $VM).state -eq "off") {
                $Job = start-job  -ScriptBlock { start-vm $VM } 
                DisplayJobStatus $Job "Starting VM $VM"               
            } 
        }        
        "Stop" {
            if ((get-vm $VM).state -eq "Running") {
                $Job = start-job  -ScriptBlock { stop-vm $VM } 
                DisplayJobStatus $Job "Stopping VM $VM"
            }
        }
        Default { }
    }    
}

Function ExportAllVM ($ExportPath) {
    Remove-Item $ExportPath -force
    New-Item $ExportPath -type directory
    $VMS = Get-VM
    foreach ($VM in $VMS) {
        $Job = export-VM -name $VM.name -path $ExportPath -AsJob
        DisplayJobStatus $Job "Exporting VM $VM"
    }
}

Function CreateRDPShortcutsForVMConsoles ($VMHostIp, $ShortcutsFolderPath){
    if(test-path $ShortcutsFolderPath){
        Remove-Item $ShortcutsFolderPath -Recurse -force
    }
    New-Item $ShortcutsFolderPath -type directory
    $VMS = Get-VM
    DATA RDPTemplate {
        "full address:s:%HostIp%
pcb:s:%VMId%
server port:i:2179
negotiate security layer:i:0"
    }

    foreach ($VM in $VMS) {
        $RDP = $RDPTemplate.clone()
        $RDPPath = $ShortcutsFolderPath + (Get-VMHost).name + "(" + $VM.Name + ").rdp"
        $RDP = $RDP.replace("%HostIp%", $VMHostIp)
        $RDP = $RDP.replace("%VMId%", $VM.Id)
        Set-Content  -path $RDPPath $RDP -NoNewline
    }
}

Function DisplayJobStatus ($Job, $Message){
    $Cntr = 1
    while ($Job.State -eq "Running") {
        $Jobtime = (get-date - $Job.PSBeginTime).Minutes
        Write-Host "$Cntr. $Message "
        $Cntr+=1
        start-sleep -Seconds 5    
    }
}

#function 
Clear-Host
#$Cim = New-CimSession -ComputerName 192.168.7.220 -Credential "ab\administrator" 
$Session = New-PSSession 192.168.7.220 -Credential  "ab\administrator" 
$Imp = Import-PSSession -Session $Session -AllowClobber -Module "Hyper-V"
$Imp1 = Import-PSSession -Session $Session -AllowClobber -Module "Microsoft.PowerShell.Management"

#Start-VM "AB-TACS-001"

#$VM = $VMS[2] 
#$VM | Format-Table -auto
#Remove-AllVMSnapshots "AB-TACS-001"

#$VM | Stop-VM
$VMStat = Get-VMStat

$VMStat | Select-Object * | Sort-Object State | Format-Table -Property * -AutoSize
$MemCons = ($VMStat | Where-Object { $_.State -eq "Running" } | Measure-Object -Sum -Property Mem).Sum
$HostMem = [math]::round((Get-VMHost).MemoryCapacity / 1mb, 0)

write-host "Memory consumption: $MemCons/$HostMem, Free memory: $($HostMem-$MemCons)  on $((Get-VMHost).name)"


$VMHostIp = "192.168.7.220"
$ShortcutsFolderPath = "D:\RDP\"
CreateRDPShortcutsForVMConsoles $VMHostIp $ShortcutsFolderPath

#$VM              = "AB-113"
#$DestinationPath = "c:\HYPER-V\AB-113\Hyper-V\" 
#$DestinationVMPath = $DestinationPath + $VM + "\Virtual Hard Disks\"
#VMAction $VM "Stop"
#MoveVMFirstHDD $VM $DestinationVMPath
#VMAction $VM "Start"

#ExportAllVM "D:\EXPORT\"

#OptimizeVHD ($VMStat | Where-Object { $_.name -eq "AB-TACS-001" })[0].DiskCn0 
#Get-VMHost | fl
#Get-VMSnapshot $VMS[2]
#Get-PSSession | Remove-PSSession
