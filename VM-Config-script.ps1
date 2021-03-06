﻿# Name:      EN:Virtual mashine configuration RU:Настройка виртуальных машин
# Ver:       1.0
# Date:      04.03.2018
# Platform:  Windows server 2016
# PSVer:     5.1.14393.1944
# Author:    AlexK

# EN
# Setup parameters in SetVMConfig()
# Looking for the VM which name contains host name from parameters
# Setup VM with parameters

# RU
# Настроим параметры в SetVMConfig()
# Среди запущеных виртуальных машин, ищем те у которых в названии, есть название узла.
# Конфигурируем в соответствии с настройками 
##############################################################################
function CopyData ([string]$DataDST,$DataSRC)
{
    write-host "1.Скопируем файлы на виртуальную машину"

    Invoke-Command -Session $Global:PSSession1 -ScriptBlock {`
        New-Item  -Path $Using:DataDST  -ItemType Directory -ErrorAction SilentlyContinue}
        #get-item ":DataDST\*.*"

    Copy-Item -ToSession $Global:PSSession1 -Path "$DataSRC\*.*"  -Destination  $DataDST  -Recurse -Force
}
function RenameComp ([SecureString]$SecurePassword,$UserName,$NewName,$Descr)
{
    write-host @{"en-US"="2.Rename remote computer";"ru-Ru"="2.Переименуем удаленный компьютер"}[$CurLang]
    Invoke-Command -Session $Global:PSSession1  -ScriptBlock {`
        $User = "$env:computername\$Using:UserName" 
        $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $User,  $using:SecurePassword 
        $WS = Get-WmiObject Win32_ComputerSystem -ComputerName $env:computername -Authentication 6 
        $WS.Rename($using:NewName , $Credentials.GetNetworkCredential().Password, $Credentials.Username)
        $OSWMI = Get-WmiObject -class Win32_OperatingSystem
        $OSWMI.Description = $Using:Descr
        $OSWMI.put()} | out-null
}
function SetIp ([string]$NewIp,$NetMask,$NetGW,$NetDNS)
{
    write-host @{"en-US"="3.Change NIC settings";"ru-Ru"="3.Изменим сетевые настройки включеного адаптера"}[$CurLang]
    Invoke-Command -Session $Global:PSSession1  -ScriptBlock {`
            $NICs = Get-WMIObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true}
        Foreach ($NIC in $NICs) {`
            $NIC.EnableStatic($Using:NewIp , @($Using:NetMask))
            $NIC.SetGateways($Using:NetGW) 
            $NIC.SetDNSServerSearchOrder($Using:NetDNS)
            $NIC.SetDynamicDNSRegistration("FALSE") 
        } 
    }| out-null
}
function EnableRDPAcc ()
{
    write-host @{"en-US"="4.Open RDP Access";"ru-Ru"="4.Откроем доступ по RDP"}[$CurLang]
    Invoke-Command -Session $Global:PSSession1  -ScriptBlock {`
        $ts = get-WMIObject Win32_TerminalServiceSetting -Namespace ROOT\CIMV2\TerminalServices
        $ts.SetAllowTSConnections(1)
        #Добавим правило фаервола
        $InstanceID = (Get-NetFirewallPortFilter | Where-Object {($_.localport -eq "3389") -and ($_.Protocol -eq "TCP") } )[0].InstanceID
        $Rule = Get-NetFirewallRule | Where-Object {$_.InstanceID -eq $InstanceID}
        Set-NetFirewallRule -Name $Rule.Name -Enabled True} | out-null
}
function ConfigKeyboard ()
{
    write-host @{"en-US"="5.Set keyboard layout";"ru-Ru"="5.Установим раскладку клавиатур"}[$CurLang]
    Invoke-Command -Session $Global:PSSession1   -ScriptBlock {`
        Set-ItemProperty -path "HKCU:\Keyboard Layout\Preload" -name "1" -value "00000409" #Eng
        Set-ItemProperty -path "HKCU:\Keyboard Layout\Preload" -name "2" -value "00000419" #Ru
        Set-ItemProperty -path "HKCU:\Keyboard Layout\Toggle"  -name "Language Hotkey" -value "2" } | out-null #Ctrl-Shift
}
function CreateSchTask ([string]$UserName,$Pass,$DataDST)
{
    write-host ""
    write-host @{"en-US"="6.Create task BGInfo";"ru-Ru"="6.Создадим задачу BGinfo"}[$CurLang]
    $ScriptPath = "$DataDST\BG-Task.ps1"
    Invoke-Command -Session $Global:PSSession1 -ScriptBlock {powershell.exe `
        -file $Using:ScriptPath $env:computername $Using:UserName $Using:Pass $Using:DataDST}| out-null
}
function RebootComp ()
{
    write-host @{"en-US"="7.Restart remote VM";"ru-Ru"="7.Перезагрузим компьютер"}[$CurLang]
    write-host 
    Invoke-Command -Session $Global:PSSession1  -ScriptBlock {Restart-Computer -Force}
}
function SetVMConfig ()
{
    $Oslo = [pscustomobject]@{
        Name  = "OSLO";
        Descr = "Корневой ЦС"
        Ip    = "192.168.0.101";
    }
    
    $TOKYO = [pscustomobject]@{
        Name  = "TOKYO";
        Descr = "Подчинённый ЦС"
        Ip    = "192.168.0.102";
    }
    
    $LONDON = [pscustomobject]@{
        Name  = "LONDON";
        Descr = "Контроллер домена"
        Ip    = "192.168.0.103";
    }
            
    $PARIS = [pscustomobject]@{
        Name  = "PARIS";
        Descr = "Веб-сервер"
        Ip    = "192.168.0.104";
    }
    
    
    $Global:WS += $Oslo
    $Global:WS += $TOKYO
    $Global:WS += $LONDON
    $Global:WS += $PARIS
}
##############################################################################
    #Language settings
    #Выбор языка 
        $CurLang = "ru-Ru" #=$psu1culture
    #Common network settings
    #Общие настройки сети для ВМ
        $NetMask = "255.255.255.0"
        $NetGW = "192.168.0.254"
        $NetDNS = "192.168.0.254"
    #Default accounts
    #Учетные записи по умолчанию
        $UserName = "администратор"
        $Pass = "123456*ф"
        $SecurePassword = $Pass | ConvertTo-SecureString -AsPlainText -Force
    #Data paths
    #Пути к данным
        $DataSRC = "c:\data\bg"
        $DataDST = "c:\data\bg"
        $Global:WS = @()
##############################################################################
Clear-Host

SetVMConfig

$RunningVM = Get-VM | Where-Object {$_.state -eq "Running"} | Select-Object *
$VMIpData = $RunningVM.NetworkAdapters | Select-Object vmname, IPAddresses, VmId

$IpList = @()

Foreach ($VM in $VMIpData) {
    $Object = [pscustomobject]@{
        Name    = $VM.vmname;
        NewName = [string]($ws | Where-Object {$VM.vmname -like ("*" + $_.Name + "*")})[0].name;
        Descr   = [string]($ws | Where-Object {$VM.vmname -like ("*" + $_.Name + "*")})[0].Descr;
        Ip      = $VM.IPAddresses[0];
        NewIp   = [string]($ws | Where-Object {$VM.vmname -like ("*" + $_.Name + "*")})[0].Ip;     
        VmId    = $VM.VmId;
    }
   
    if (!($Object.NewIp -eq $Object.Ip)) {$IpList += $Object}
}

$IpList = $IpList | Sort-Object Newip
$IpList | Format-Table

foreach ($VM in $IpList) {
    $VM| Format-Table

    $Comp    = $VM.ip
    $NewIp   = $VM.newip
    $Descr   = $VM.Descr
    $NewName = $VM.newname
    
    $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $Comp\$UserName, $SecurePassword 
    $Global:PSSession1 = New-PSSession -VMId $VM.VmId  -Credential $Credentials

    CopyData      $DataDST $DataSRC
    RenameComp   ($Pass| ConvertTo-SecureString -AsPlainText -force) $UserName $NewName $Descr
    SetIp         $NewIp $NetMask $NetGW $NetDNS
    EnableRDPAcc 
    ConfigKeyboard
    CreateSchTask $UserName $Pass $DataDST
    RebootComp
}