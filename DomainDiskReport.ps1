<#==============================================================================
         File Name : DomainDiskReport.ps1
   Original Author : Kenneth C. Mazie (kcmjr @ kcmjr.com)
                   :
       Description : This script uses WMI to poll the current domain and extract
                   : disk statistics. Output is gathered in HTML format and emailed
                   : to a list of recipients. Output can be all systems (full)
                   : or only systems that are below preset threshold (brief).
                   :
         Arguments : Named commandline parameters: (all are optional)
                   : "-display" - Displays console output during run.
                   : "-debug" - Switches email recipient and target criteria. Also dumps HTML output to script folder
                   : "-detail" - Can be set to "full" or "brief". Default to "brief".
                   : "-mode" - Can be "all", "pc", "video", or "server". Defaults to "all" which polls all 3.
                   : Note that mode setting has been moved to the XML file.
                   :
             Notes : Allows setting a threshold of the lowest remaining space. Colors all others in red.
                   : Numerous parameters are adjustable from within the main function.
                   : !!! -- Best run from a scheduled job as a domain admin user -- !!!
                   :
          Warnings : None
                   :
             Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                   : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF
                   : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                   : That being said please let me know if you find bugs!
                   :
           Credits : Code snippets and/or ideas came from many sources around the web.
                   :
    Last Update by : Kenneth C. Mazie (email kcmjr AT kcmjr.com for comments or to report bugs)
   Version History : v1.00 - 05-03-14 - Original
    Change History : v2.00 - 11-01-14 - Changed HTML formatting. Added commandline options.
                   : v2.01 - 12-10-14 - Changed input arguments to be named
                   : v2.02 - 02-11-15 - Added Win8x detection. Moved notes to bottom of report.
                   : v3.00 - 05-28-15 - Numerous changes. Retooled report wording. Added ignore list for
                   : large data drives. Added video server option.
                   : v3.01 - 10-20-15 - Minor edits, updated syntax.
                   : v4.00 - 02-19-16 - Fixed issue detecting PC and Video. Re-enabled video check.
                   : v4.10 - 07-22-16 - Adjusted "woo-hoo" message locations and function.
                   : v4.20 - 01-03-18 - Adjusted external config file, changed console formatting
                   : v4.30 - 05-18-18 - Excluded workstations since VDIs are no longer in use.
                   : Fixed missing credential call on get-adcomputers (line 325)
                   : v4.40 - 06-12-18 - Added support for server 2016
                   : v4.41 - 06-26-18 - Fixed minor bug with output.
                   : v4.50 - 06-29-18 - Output bug still exists. Now corrected. Adjusted for Win10,
                   : removed Win 7 & 8. Altered output colors.
                   : v4.60 - 07-20-18 - Fixed another output bug (nothing found message not in output)
                   : v4.70 - 07-23-18 - Added ping failure to "brief" output. Altered no ping and failure notations.
                   : v4.80 - 08-16-18 - Added multiple connectivity tests
                   : v4.81 - 01-10-19 - Fixed typo in credential. Changed domain detecion.
                   :
#===============================================================================#>
<#PSScriptInfo
.VERSION 4.81
.AUTHOR Kenneth C. Mazie (kcmjr AT kcmjr.com)
.DESCRIPTION
This script uses WMI to poll the current domain and extract disk statistics.
Output is gathered in HTML format and emailed to a list of recipients.
Output can be all systems (full) or only systems that are below preset threshold (brief).
#>
#requires -version 5.0

#--[ Set input variables ]--
Param (
    [Switch]$Debug = $false,
    [Switch]$Console = $False,
    $Detail = "brief",
    $Mode = ""
)    

Clear-Host
If ($Debug){
    $Script:Debug = $True
    $Script:Console = $True
}

#--[ For Testing ]-------------
#$Script:Debug = $True
#$Script:Console = $True
$Script:Mode = "pc"
#$Script:Detail = "full"
#------------------------------

If ($Console){$Script:Console = $True}
[string]$Script:Detail = [string]$Detail 
#[string]$Script:Mode = [string]$Mode #--[ Moved to XML file load area. If set on command line, that setting will over-ride the XML. ]--

if (!(Get-Module -Name ActiveDirectory)){Import-Module ActiveDirectory}

$Script:ScriptName = $MyInvocation.MyCommand.Name 
$Script:ScriptFullPath = $PSScriptRoot+"\"+$MyInvocation.MyCommand.Name 
$Script:ConfigFile = $Script:ScriptFullPath.Split(".")[0]+".xml"
$Script:LogFile = $Script:ScriptFullPath.Split(".")[0]+"_{0:MM-dd-yyyy_HHmmss}.html" -f (Get-Date)
$Script:GlobalCounter = 0
$ErrorActionPreference = "silentlycontinue"  

Function LoadConfig { #--[ Read and load configuration file ]-----------------------------------------
    If (!(Test-Path $Script:ConfigFile)){       #--[ Error out if configuration file doesn't exist ]--
        Write-Host "---------------------------------------------" -ForegroundColor Red
        Write-Host "--[ MISSING CONFIG FILE. Script aborted. ]--" -ForegroundColor Red
        Write-Host "---------------------------------------------" -ForegroundColor Red
        SendEmail
        break
    }Else{
        [xml]$Script:Configuration = Get-Content $Script:ConfigFile       
        $Script:ExclusionList = ($Script:Configuration.Settings.General.Exclusion).split(",")
        If ([string]::IsNullOrEmpty($Mode)){                          
            $Script:Mode = $Script:Configuration.Settings.General.Mode
        }Else{
            [string]$Script:Mode = [string]$Mode
        }
        $Script:SrvCDriveMin = $Script:Configuration.Settings.General.SrvCDriveMin
        $Script:WksCDriveMin = $Script:Configuration.Settings.General.WksCDriveMin
        $Script:PercentWarning = $Script:Configuration.Settings.General.PercentWarning
        $Script:IgnoreList = ($Script:Configuration.Settings.General.Ignore).split(",")
        $Script:ReportName = $Script:Configuration.Settings.General.ReportName
        $Script:DebugTarget = $Script:Configuration.Settings.General.DebugTarget   
        $Script:Retention = $Script:Configuration.Settings.General.Retention
        $Script:Subject = $Script:Configuration.Settings.Email.Subject
        $Script:EmailTo = $Script:Configuration.Settings.Email.To
        $Script:EmailFrom = $Script:Configuration.Settings.Email.From
        $Script:EmailHTML = $Script:Configuration.Settings.Email.HTML
        $Script:SmtpServer = $Script:Configuration.Settings.Email.SmtpServer
        $Script:DebugEmail = $Script:Configuration.Settings.Email.Debug
        $Script:UN = $Script:Configuration.Settings.Credentials.Username
        $Script:EPW = $Script:Configuration.Settings.Credentials.Password
        $Script:B64 = $Script:Configuration.Settings.Credentials.Key   
        $BA = [System.Convert]::FromBase64String($B64)
        $Script:SC = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UN, ($EPW | ConvertTo-SecureString -Key $BA)  
        $Script:SP = $SC.GetNetworkCredential().Password 
    }
} 
      
Function SendEmail {
    $email = New-Object System.Net.Mail.MailMessage
    $email.From = $Script:EmailFrom
    $email.IsBodyHtml = $Script:EmailHTML
    If ($Script:Debug){
        $email.To.Add($Script:DebugEmail)
    }Else{
        $email.To.Add($Script:EmailTo)
    }
    $email.Subject = $Script:Subject
    $email.Body = $Script:ReportBody
    $smtp = new-object System.Net.Mail.SmtpClient($Script:SMTPServer)
    $smtp.Send($email)
    If ($Script:Console){Write-Host "`nEmail sent..." -ForegroundColor Green}
}

Function Process ($Script:Target){  #--[ Main process loop. Analyze the target systems disks ]------------------------
    $Aflag = $False    #--[ Identifies Avigilon security video servers ]--
    $TargetLoopFlag = $False
    $Script:EmailFlag = $False

    $Size = "";$Freespace="";$PercentFree="";$SizeGB="";$FreeSpaceGB="";$Win32_Hardware = "";$Win32_OS = ""
    $Script:Target=$Script:Target.Name
    $TargetHash = @{"Target" = $Script:Target}
    
    If ($Script:Console){
        Write-Host "`r`n--[ " -ForegroundColor White -NoNewline
        write-host $Script:Target.Toupper() -ForegroundColor Yellow -NoNewline
        Write-Host " ]-------------------------------------------------------------------".PadRight((110-$Script:Target.length),"-") -ForegroundColor White
    }    

    Function TestConnection {    #--[ Multiple Connectivity Tests ]--
        $Script:IPCConnect = $false
        $Script:WMIConnect = $false
        $Script:PingConnect = $false

        Try{    #--[ Test IPC$ Connection ]--
            If ($Script:Debug){net use \\$Script:Target\ipc$ /d | Out-Null }
            net use \\$Script:Target\ipc$ /user:$Script:UN $Script:SP | Out-Null 
            $Script:IPCConnect = $true
        }Catch{
        }    

        Try{    #--[ Test WMI Connection ]--
            $Result = Get-WmiObject -query "SELECT * FROM Win32_OperatingSystem" -ComputerName $Script:Target -Credential $Script:SC
            if(!([string]::IsNullOrEmpty($Result.SystemDirectory))){
                $Script:WMIConnect = $true
            }
        }Catch{

        }

        #--[ Standard PS Connection Test ]--
        If(Test-Connection -ComputerName $Script:Target -count 1 -BufferSize 16 -ErrorAction SilentlyContinue ) {
            $Script:PingConnect = $true
        }   
        
        If ($Script:Debug){
            If ($Script:Console){Write-host "IPC Connection : $Script:IPCConnect " -ForegroundColor yellow}
            If ($Script:Console){Write-host "WMI Connection : $Script:WMIConnect " -ForegroundColor yellow}
            If ($Script:Console){Write-host "Ping Connection: $Script:PingConnect " -ForegroundColor yellow}
        }
    }   

    TestConnection

    If($Script:IPCConnect -or $Script:PingConnect -or $Script:WMIConnect) {
        If ($Script:Target -like "*avigilon*"){$Aflag = $true}     
      
        #--[ Gather system data ]----------------------------------------------------------------------
        $WMIJob = Get-WMIObject win32_logicaldisk -Filter "DriveType = 3" -ComputerName $Script:Target -AsJob -Credential $Script:SC
        Wait-Job -ID $WMIJob.ID -Timeout 5 | Out-Null 
        $Disks = Receive-Job $WMIJob.ID -ErrorAction SilentlyContinue
        #----------------------------------------------------------------------------------------------
        $WMIJob = Get-WMIObject Win32_OperatingSystem -computer $Script:Target -AsJob -Credential $Script:SC
        Wait-Job -ID $WMIJob.ID -Timeout 5 | Out-Null 
        $Win32_OS = Receive-Job $WMIJob.ID -ErrorAction SilentlyContinue | select Caption
        $Win32_OS = ($Win32_OS.caption -replace("\(R\)","")).Replace("Microsoft ","")
        $TargetHash.Add("OS",$Win32_OS)
        #-----------------------------------------------------------------------------------------------
        $WMIJob = Get-WMIObject -ComputerName $Script:Target -class Win32_ComputerSystemProduct -AsJob -Credential $Script:SC
        Wait-Job -ID $WMIJob.ID -Timeout 5 | Out-Null 
        $Win32_Hardware = Receive-Job $WMIJob.ID -ErrorAction SilentlyContinue    
        if(([string]::IsNullOrEmpty($Win32_Hardware.Name)) -or ($Win32_Hardware.Name -eq " ")){
            $MFG = "Unknown"
        }ElseIf ($Win32_Hardware.Name -eq "VMware Virtual Platform"){
            $MFG = "VMware Virtual"
        }Else{
            $MFG = $Win32_Hardware.Name.trimend()
        }
        $TargetHash.Add("MFG",$MFG)
        #-----------------------------------------------------------------------------------------------
            $Count = 0
            foreach($Disk in $Disks){
                $DeviceID = $Disk.DeviceID;
                [float]$Size = $Disk.Size;
                [float]$Freespace = $Disk.FreeSpace;
                [string]$PercentFree = [Math]::Round(($Freespace / $Size) * 100, 0);
                [string]$SizeGB = [Math]::Round($Size / 1073741824, 0);
                [string]$FreeSpaceGB = [Math]::Round($Freespace / 1073741824, 2);        
                
                $DriveHash =  @{"Drive" = $DeviceID;"Size" = $SizeGB;"PercFree" = $PercentFree;"FreeSpace" = $FreeSpaceGB}
                $TargetHash.Add($Count,$DriveHash)    
                $Count++
            }  #--[End - ForEach disk ]--

        #----------------------------------------- START OF OUTPUT -----------------------------------------------------
            $HtmlData += '<td><font color="blue">' + $Script:Target + '</td>'
            If([string]::IsNullOrEmpty($Win32_OS)){$Win32_OS = "Unknown"}

            If (($Win32_OS -eq "Unknown") -and ($MFG -eq "Unknown")){
                 If ($Script:Console){Write-Host "Failed to extract any information from target system..." -ForegroundColor cyan}
                $HtmlData += '<td colspan=6><center><font color="darkcyan">Failed to extract any information from target system.</center></td></tr>'
                $Script:EmailFlag = $true 
                $Script:GlobalCounter++
                $TargetLoopFlag = $true 

                #--[ NOTE: The line below determines what operating systems show up as green or red. We no longer allow Windows 7 so I left it off. ]--
            }Else{
                If (($Win32_OS -like "*2016*") -or ($Win32_OS -like "*R2*") -or ($Win32_OS -like "*2012*") -or ($Win32_OS -like "*Windows 10*") -or ($Win32_OS -like "*Embedded*")){
                    If ($Script:Console){Write-Host "OS = $Win32_OS".PadRight(56," ") -ForegroundColor Green -NoNewline }
                    $HtmlData += '<td><font color="green">' + $Win32_OS + "</font></td>"
                }Else{
                    #If([string]::IsNullOrEmpty($Win32_OS)){$Win32_OS = "Unknown"}
                    If ($Script:Console){Write-Host "OS = $Win32_OS".PadRight(56," ") -ForegroundColor Red -NoNewline }
                    $TargetLoopFlag = $true  
                    $Script:EmailFlag = $true
                    $Script:GlobalCounter++
                    $HtmlData += '<td><font color="red">' + $Win32_OS + "</font></td>"
                }
        
                If($MFG -like "*VMware*"){
                    If ($Script:Console){Write-Host "Hardware = $MFG" -ForegroundColor cyan -NoNewline} 
                    $HtmlData += '<td><font color="green">VMware Virtual</font></td>'
                }ElseIf ($MFG -like "*Unknown*"){
                    If ($Script:Console){Write-Host "Hardware = $MFG" -ForegroundColor Magenta -NoNewline }
                    $HtmlData += '<td><font color="magenta">' + $MFG + ' </font></td>'
                }Else{
                    If ($Script:Console){Write-Host "Hardware = $MFG" -ForegroundColor Green -NoNewline }
                    $HtmlData += '<td><font color="green">' + $MFG + ' </font></td>'
                }
                
                If ($Script:Console){
                    If($AFlag){
                        Write-Host " ( Video Surveillance Server )" -ForegroundColor Yellow
                    }Else{
                        Write-Host ""
                    } 
                }
                
                $Count = 0
                While ($Count -lt $TargetHash.count-3 ){
                    #--[ For Testing ]--------------------------
                    #$TargetHash.Item($Count).Item("Drive")
                    #$TargetHash.Item($Count).Item("Size")
                    #$TargetHash.Item($Count).Item("FreeSpace")
                    #$TargetHash.Item($Count).Item("PercFree")
                    #-------------------------------------------
                    If ($Script:Console){Write-Host "Drive =" $TargetHash.Item($Count).Item("Drive").PadRight(15," ") -NoNewline }
                    
                    If ($Count -gt 0){
                        $HtmlData += "<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>" + $TargetHash.Item($Count).Item("Drive") +"</td>"
                    }Else{
                        $HtmlData += "<td>" + $TargetHash.Item($Count).Item("Drive") + "</td>"
                    }
                
                    #--[ report if server C: drive size is less than specified in config file - #$TargetHash.Item($Count).Item("Size") ]--
                    If (($TargetHash.Item($Count).Item("Drive") -eq "C:") -and ([int]$TargetHash.Item($Count).Item("Size") -lt [int]$SrvCDriveMin) -and (($Win32_OS -like "*Server*") -or ($Script:Mode -eq "video"))){
                        If ($Script:Console){Write-Host "Size (GB) = "($TargetHash.Item($Count).Item("Size").PadRight(20," ")) -NoNewline -ForegroundColor red}
                        $HtmlData += '<td><font color="red">' + $TargetHash.Item($Count).Item("Size") + '</font></td>'
                        $TargetLoopFlag = $True
                        $Script:EmailFlag = $true
                        $Script:GlobalCounter ++
                    }Else{
                        If ($Script:Console){Write-Host "Size (GB) = "($TargetHash.Item($Count).Item("Size").PadRight(20," ")) -NoNewline -ForegroundColor green}
                        $HtmlData += '<td><font color="green">' + $TargetHash.Item($Count).Item("Size") + '</font></td>'
                    }
    
                    #--[ $TargetHash.Item($Count).Item("SpaceFree") ]--
                    If ($Script:Console){Write-Host "FreeSpace =" $TargetHash.Item($Count).Item("FreeSpace").PadRight(20," ") -NoNewline }
                    $HtmlData += "<td>" + $TargetHash.Item($Count).Item("FreeSpace") + "</td>"

                    #--[ $TargetHash.Item($Count).Item("PercFree") ]--
                    If($TargetHash.Item($Count).Item("Drive") -eq "C:"){  #--[ Process the C: drive ]--
                        If(($TargetHash.Item($Count).Item("PercFree")) -lt ($Script:PercentWarning)){
                            $TargetLoopFlag = $True
                            $Script:EmailFlag = $True
                            If ($Script:Console){Write-Host "Percent Free = "(($TargetHash.Item($Count).Item("PercFree").PadLeft(2,"0")) + " %").PadRight(10," ") -ForegroundColor Red} # -NoNewline }
                            $HtmlData += '<td><font color="red">' + $TargetHash.Item($Count).Item("PercFree") + ' %</font></td></tr>'
                            $Script:GlobalCounter ++
                        }Else{
                              If ($Script:Console){Write-Host "Percent Free = "(($TargetHash.Item($Count).Item("PercFree").PadLeft(2,"0")) + " %").PadRight(10," ") -ForegroundColor Green} # -NoNewline }
                              $HtmlData += '<td><font color="green">' + $TargetHash.Item($Count).Item("PercFree") + ' %</font></td></tr>'
                        }
                    }Else{
                        if (($IgnoreList -contains $Script:Target) -or ($Script:AFlag)) {  #--[ Check the ignore list, ignore the drive if matched or is video server ]--
                            #If(([int]$TargetHash.Item($Count).Item("PercFree")) -lt ([int]$Script:PercentWarning)){
                                If ($Script:Console){Write-Host ("Percent Free = IGNORED").PadRight(10," ") -ForegroundColor Gray } # -NoNewline }
                                $HtmlData += '<td><font color="gray">IGNORED</font></td></tr>'
                                $Script:GlobalCounter ++
                            #}Else{
                              # If ($Script:Console){Write-Host "Percent Free = "(($TargetHash.Item($Count).Item("PercFree").PadLeft(2,"0")) + " %").PadRight(10," ") -ForegroundColor Green} # -NoNewline }
                              # $HtmlData += '<td><font color="green">' + $TargetHash.Item($Count).Item("PercFree") + ' %</font></td></tr>'
                            #}
                        }Else{  #--[ Ignore list was not matched ]--
                            If(($TargetHash.Item($Count).Item("PercFree")) -lt ($Script:PercentWarning)){
                                $TargetLoopFlag = $True
                                $Script:EmailFlag = $True
                                If ($Script:Console){Write-Host "Percent Free = "(($TargetHash.Item($Count).Item("PercFree").PadLeft(2,"0")) + " %").PadRight(10," ") -ForegroundColor Red} # -NoNewline }
                                $HtmlData += '<td><font color="red">' + $TargetHash.Item($Count).Item("PercFree") + ' %</font></td></tr>'
                                $Script:GlobalCounter ++
                            }Else{
                                If ($Script:Console){Write-Host "Percent Free = "(($TargetHash.Item($Count).Item("PercFree").PadLeft(2,"0")) + " %").PadRight(10," ") -ForegroundColor Green} # -NoNewline }
                                $HtmlData += '<td><font color="green">' + $TargetHash.Item($Count).Item("PercFree") + ' %</font></td></tr>'
                            }
                        }
                    }
                    $Count++ 
                }
            }
        #---------------------------END OF OUTPUT-------------------------------------------------------
        If ($Script:Console -And $Script:EmailFlag){Write-Host "-- Adding to output --" -ForegroundColor DarkBlue}
        If ($Script:EmailFlag){$Script:SectionFlag = $True}
        If ($TargetLoopFlag){$Script:ReportBody += $HtmlData}
        If ($Detail -ne "brief"){$Script:ReportBody += $HtmlData}
    }Else{
        If ($Script:Console){
            Write-Host "Failed to successfully ping target system..." -ForegroundColor Cyan
            Write-Host "-- Adding to output --" -ForegroundColor DarkBlue
        }
        $Script:ReportBody += '<tr><td><font color="blue">' + $Script:Target + '</td><td colspan=6><center><font color="darkcyan">Failed to successfully ping target system.</center></td></tr>'
        $Script:EmailFlag = $True
        $Script:GlobalCounter ++          
        $Script:ReportBody += $HtmlData
    }  #--[ End - test-connection ]--
    If ($Script:Debug){Write-Host "Items in output:"$Script:GlobalCounter}
    Return 
}  #--[ End of main loop ]--

#--[ End of Functions ]---------------------------------------------------------

LoadConfig

$Datetime = Get-Date -Format "MM-dd-yyyy_HH:mm"
$TextInfo = (Get-Culture).TextInfo
$Domain = (Get-ADDomain -Credential $Script:SC).DNSroot

If ($Script:Debug){
    Write-Host "`n--- DEBUG MODE ---`n" -ForegroundColor Yellow   
    $Script:eMailRecipient = $Script:DebugEmail           #--[ Switch destination email address during debug. ]--
    Write-Host "Email Recipient = "$Script:eMailRecipient -ForegroundColor Cyan   
}  

#--[ Retain only the prior X number of reports. ]--
Get-ChildItem -Path "$PSScriptRoot\*.html" | Where-Object { -not $_.PsIsContainer } | Sort-Object -Descending -Property CreationTime | Select-Object -Skip $Script:Retention | Remove-Item     

#--[ Add header to html log file ]--
$Script:ReportBody = @() | Select Target,Drive,SizeGB,FreeSpaceGB,PercentFree,Manufacturer
$Script:ReportBody += '<style type="text/css">
table.myTable { border:5px solid black;border-collapse:collapse; }
table.myTable td { border:2px solid black;padding:5px;background: #E6E6E6 }, table.myTable th { border:2px solid black;padding:5px;background: #A4A4A4 }
#table.bottomBorder { border-collapse:collapse; }
#table.bottomBorder td, table.bottomBorder th { border-bottom:1px dotted black;padding:5px; }
</style>
The following report displays disks configured on every '
If($Script:Mode -eq "server"){$Script:ReportBody += 'server'}
If($Script:Mode -eq "all"){$Script:ReportBody += 'server and PC'}
If($Script:Mode -eq "video"){$Script:ReportBody += 'video server'}
$Script:ReportBody += ' in the domain. See bottom of page for notations.<br><br>'
$Script:ReportBody += 'Results for<strong> '+$Domain+' </strong>Domain:<br><br>'

If ($Console){ 
    Write-Host "`n--[ " -ForegroundColor White -NoNewline 
    Write-Host "Current Script Run-Mode = " -ForegroundColor Yellow -NoNewLine 
    Write-Host $Script:mode.ToUpper() -ForegroundColor Magenta -NoNewline 
       Write-Host " ]".PadRight(78,"-") -ForegroundColor White
}

If ($Script:Debug){
    $Computers = Get-ADComputer $Script:DebugTarget -Credential $Script:SC 
    $Script:ReportBody += '<table class="myTable"><tr><th colspan=7>--- Debugging Group ---</th></tr>'
    $Script:ReportBody += '<tr><th>Target System</th><th>Operating System</th><th>Hardware</th><th>Drive</th><th>SizeGB</th><th>FreeSpaceGB</th><th>PercentFree</th></tr>'
    ForEach ( $Script:Target in $Computers ){
        If ($Target.Name -notlike $Script:ExclusionList){               #=====[ Use this to skip systems that conform to the listed patterns ]=====
            Process $Script:Target
        }
    }
    If ($Script:GlobalCounter -le 0){$Script:ReportBody += '<tr><td colspan=7><strong><center><font color="green";size=14pt>Nothing to report today in this section!</font></center></strong></td></tr>'} 
    $Script:ReportBody += '</table><br>'
}Else{
    #--[ Inspect all servers ]--------------------------------------------------
    If (($Script:Mode -eq "server") -or ($Script:Mode -eq "all")){
        $Script:SectionFlag = $False
        $Computers = Get-ADComputer -Credential $Script:SC -Properties * -Filter { operatingsystem -like "*server*" -and name -notlike "*esx*" -and name -notlike "*avigilon*" -and name -notlike "*test*" } | sort name
        $Script:ServerCount = $Computers.count
        $Script:ReportBody += '<table class="myTable"><tr><th colspan=7>--- Server Group ---</th></tr>'
        $Script:ReportBody += '<tr><th>Target System</th><th>Operating System</th><th>Hardware</th><th>Drive</th><th>SizeGB</th><th>FreeSpaceGB</th><th>PercentFree</th></tr>'
        ForEach($Script:Target in $Computers ){
            If ($Target.Name -notlike $Script:ExclusionList){               #=====[ Use this to skip systems that conform to the listed patterns ]=====
                Process $Script:Target
            }
        }
        If ($Script:GlobalCounter -le 0){$Script:ReportBody += '<tr><td colspan=7><strong><center><font color="green";size=14pt>Nothing to report today in this section!</font></center></strong></td></tr>'} 
        $Script:ReportBody += '</table><br>'
    }

    #--[ Inspect all PC's ]-----------------------------------------------------
    If (($Script:Mode -eq "pc") -or ($Script:Mode -eq "all")){
        $Script:SectionFlag = $False
        $Computers = Get-ADComputer -Credential $Script:SC -Properties * -Filter { operatingsystem -notlike "*server*" -and name -notlike "*esx*" -and name -like "*c40its*" -and name -notlike "*test*"} | sort name
        $Script:PCCount = $Computers.count
        $Script:ReportBody += '<table class="myTable"><tr><th colspan=7>--- Workstation Group ---</th></tr>'
        $Script:ReportBody += '<tr><th>Target System</th><th>Operating System</th><th>Hardware</th><th>Drive</th><th>SizeGB</th><th>FreeSpaceGB</th><th>PercentFree</th></tr>'
        ForEach($Script:Target in $Computers ){
            If ($ExclusionList -notcontains $Script:Target.name){
                Process $Script:Target 
            }
           }
        If ($Script:GlobalCounter -le 0){$Script:ReportBody += '<tr><td colspan=7><strong><center><font color="green";size=14pt>Nothing to report today in this section!</font></center></strong></td></tr>'} 
        $Script:ReportBody += "</table><br>"
    }

    #--[ Inspect all Video Systems ]--------------------------------------------
    If (($Script:Mode -eq "video") -or ($Script:Mode -eq "all")){
        $Script:SectionFlag = $False
        $Computers = Get-ADComputer -Credential $Script:SC -Properties * -Filter { name -like "*avigilon*" -and name -notlike "*test*"} | sort name
        $Script:VidServerCount = $Computers.count
        $Script:ReportBody += '<table class="myTable"><tr><th colspan=7>--- Video Server Group ---</th></tr>'
        $Script:ReportBody += '<tr><th>Target System</th><th>Operating System</th><th>Hardware</th><th>Drive</th><th>SizeGB</th><th>FreeSpaceGB</th><th>PercentFree</th></tr>'
        ForEach($Script:Target in $Computers ){
            If ($ExclusionList -notcontains $Script:Target.name){
                Process $Script:Target 
            }
           }
        If ($Script:GlobalCounter -le 0){$Script:ReportBody += '<tr><td colspan=7><strong><center><font color="green";size=14pt>Nothing to report today in this section!</font></center></strong></td></tr>'} 
        $Script:ReportBody += "</table><br>"
    }
}

If($Detail -eq "brief"){$Script:ReportBody += '<br><strong>Note:</strong>&nbspScript has been executed with the "brief" option enabled.<br>'}

$Script:ReportBody += '
    Script executed on '+$Datetime+'<br>
    <br><strong>NOTES:</strong><br><ul>
      <li>If the "brief" option was used only systems with disks in need of attention are listed.</li>
      <li>Operating systems that can be dynamically grown are shown in green, all others in red.</li>
      <li>Under the Hardware heading physical systems are noted in red since the disks cannot be grown.</li>
      <li>Any PC C: drives smaller than '+$Script:WksCDriveMin+' GB, or server C: drives smaller than '+$Script:SrvCDriveMin+' GB are flagged in red.</li>
      <li>All other disks are red only if the remaining free disk space is below 10%.</li>
      <li>Systems that are not reachable for whatever reason are noted as such.</li>
      <li>Select server D:, E:, and F:, drives are always ignored regardless of remaining C: drive space.</li>
    </ul>'
    
If ($Script:Debug){$Script:ReportBody | Out-File $Script:LogFile}

SendEmail           #--[ Send the email. ]--
  
If ($Script:Console){Write-Host "`n--- COMPLETED ---" -ForegroundColor Red}

<#--[ Sample Configuration File ]-----------------------------------------
 
<!-- Settings & Configuration File -->
<Settings>
    <General>
        <ReportName>Domain Disk Check Report</ReportName>
        <DebugTarget>debug-server</DebugTarget>
        <Exclusion>"*test-server*|*server2*"</Exclusion>   
        <Retention>10</Retention>                         <!--[ Number of report files to retain ]-->  
        <Ignore>"BADServer1"</Ignore>
        <PercentWarning>10</PercentWarning>               <!--[ Issue warning if free disk space is below this % ]-->
        <SrvCDriveMin>99</SrvCDriveMin>                   <!--[ Set to minimum allowable server C: size GB minus 1 ]--> 
        <WksCDriveMin>99</WksCDriveMin>                   <!--[ Set to minimum allowable PC C: size GB minus 1 ]-->
           <Mode>all</Mode>                               <!--[ determines what gets scanned ]-->
    </General>
    <Email>
        <From>DailyReports@domain.com</From>
        <To>email1@domain.com,email2@domain.com.com,email3@domain.com</To>
        <Debug>youremail@yourdomain.com</Debug>
        <Subject>Domain Daily Disk Status Report</Subject>
        <HTML>$true</HTML>
        <SmtpServer>10.10.5.5</SmtpServer>
    </Email>
    <Credentials>
        <UserName>domain\serviceaccount</UserName>
        <Password>76492d111674ANAA4AGQAZEaADcAYwBtAHAAWQBYQAwADYA3f0423413b16050a5345MgB8AHIAegB2AHYAQEaADcAYwBtAHAAWQBYAZQBmAA0AGEAMAAwADQAZgBiAGMAYQyADUEaADcAYwBtAHAAWQBABhAGEAYQBhAGQANQBkADGQAOAA0ADEANgBiADAANwBkADEZAA3AGUAZgBkAGYAZAA=</Password>
        <Key>kdhCh7HCvLA3f0423413b16050a53HAAWQB6AHoAeQA08mE=</Key>
    </Credentials>
</Settings> 
#>
