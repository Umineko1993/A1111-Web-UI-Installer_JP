. "$PSScriptRoot\shared.ps1"
Import-Module "$PSScriptRoot\logger.psm1" -Force -Global -Prefix "logger."

#Startup fonctions
#-----------------------------
function Search-RegForPyPath {
    $regPaths = @("hkcu:\Software\Python\PythonCore\3.10\InstallPath", "hklm:\Software\Python\PythonCore\3.10\InstallPath")

    foreach ($path in $regPaths) {
        $pyCore = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        if ($pyCore) {
            $pyPath = $pyCore.'(default)'
            $pyVersion = (Get-Command -Name "$pyPath\python.exe").Version
            logger.info "���W�X�g���� Python $pyVersion ��������܂����F" "$pyPath"
            if ($pyVersion -notlike "3.10.6150.1013") {
                $Exprompt = [system.windows.messagebox]::Show("Python 3.10 ($pyVersion)���ȑO�ɃC���X�g�[�����܂������A�������o�[�W�����ł͂���܂���B �G���[�ɂȂ���\��������܂��B`n`n��������ɂ́A�V�X�e������Python 3.10�̑S�Ẵo�[�W�������A���C���X�g�[�����A�����`���[���ċN�����ĉ������B`n`n�����܂���?", "Python $pyVersion�͐�������܂���B", 'Yes No')
                logger.warn "�����Python�̐����o�[�W�����ł͂Ȃ��̂ŁA�����炭�G���[���������܂��B"
                if ($Exprompt -eq "No") {
                    exit
                }
            }
            return $pyPath
        }
    }
    return ""
}
function Install-py {
    $Global:pyPath = Search-RegForPyPath
    if ($Global:pyPath -eq "") {
        logger.web -Type "download" -Object "Python 3.10 ��������Ȃ��̂ŁA�_�E�����[�h�ƃC���X�g�[�����{���B�b�����҂�������"
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.10.6/python-3.10.6-amd64.exe" -OutFile "$tempFolder\python.exe"
        ."$tempFolder\python.exe" /quiet InstallAllUsers=0 PrependPath=1
        logger.success "Done"
        $Global:pyPath = Search-RegForPyPath
    }
    logger.info "PATH����Python�̋L�q���폜���܂�"
    $env:Path = [System.String]::Join(";", $($env:Path.split(';') | Where-Object { $_ -notmatch "python" }))
    logger.action "Python 3.10���p�X�ɒǉ����܂�" -success
    $env:Path += ";$Global:pyPath"
    logger.success
    return
}
function Install-git {
    $gitInPath = Get-Command git -ErrorAction SilentlyContinue
    if ($gitInPath) {
        $Global:gitPath = $gitInPath.Source
        logger.info "Git��������APATH�Ɋ��ɂ���܂�:" "$($gitInPath.Source)"
        return
    }
    else {
        if (!(Test-Path "$gitPath\bin\git.exe")) {
            logger.web -Type "download" -Object "Git��������Ȃ��̂ŁA�_�E�����[�h�ƃC���X�g�[�������{���B�b�����҂������� "
            Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.38.1.windows.1/Git-2.38.1-64-bit.exe" -OutFile "$tempFolder\git.exe"
            ."$tempFolder\git.exe" /VERYSILENT /NORESTART
            logger.success
        }
        else {
            logger.info "Git���m�F" "$("$env:ProgramFiles\Git")"
        }
        if (!(Get-Command git -ErrorAction SilentlyContinue)) {
            logger.action "PATH��Git��������Ȃ��̂ŁA�ǉ����܂�" -success
            $env:Path += ";$gitPath\bin"
            logger.success
            return
        }
        else {
            logger.info "Git��PATH�ɂ���"
        }
    }
}
function Install-WebUI {
    if (!(Test-Path $webuiPath)) {
        logger.web -Type "download" -Object "Automatic1111 SD WebUI git�̃N���[����"
        git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui $webuiPath
        logger.success "����"
        return
    }
    logger.info "Automatic1111 SD WebUI��������܂����B:" "$webuiPath"
}
function Reset-WebUI {
    $Exprompt = [system.windows.messagebox]::Show("����́AWebUI�t�H���_�����S�ɏ������Agithub����č쐬������̂ŁA�S�Ă̏d�v�ȃf�[�^�ƃ��f�����o�b�N�A�b�v���Ă��鎖���m�F���ĉ������B`n`n �{����WebUI�t�H���_�����Z�b�g�������ł���?", '�C�����Ă�������', 'Yes No', '�x��')
    if ($Exprompt -eq "Yes") {
        logger.action "Webui�t�H���_�̍폜" -success
        Remove-Item $webuiPath -Recurse -Force
        logger.success
        Install-WebUI 
    }
}
function Import-BaseModel {
    $ckptDirSetting = $settings | Where-Object { $_.arg -eq "ckpt-dir" }
    if (($ckptDirSetting.enabled -eq $false) -and !(Get-ChildItem $modelsPath | Where-Object { $_.extension -ne ".txt" })) {
        $Exprompt = [system.windows.messagebox]::Show("���Ȃ��̃C���X�g�[����Ƀ��f����������܂���ł����BStable Diffusion 1.5 �x�[�X���f�����_�E�����[�h���܂����H`n`n�ڍׂ�������Ȃ��ꍇ�uYes�v�̃N���b�N�������܂��B`n`n����͂��΂炭���Ԃ�������̂ŁA�b�����҂��������B", 'SD 1.5���f�����C���X�g�[�����܂����H', 'Yes No')
        if ($Exprompt -eq "Yes") {
            $url = "https://anga.tv/ems/model.ckpt"
            $destination = "$modelsPath\SD15NewVAEpruned.ckpt"
            $request = [System.Net.HttpWebRequest]::Create($url)
            $response = $request.GetResponse()
            $fileSize = [int]$response.ContentLength
            Start-Job -ScriptBlock {
                param($url, $destination)
                $WebClient = New-Object System.Net.WebClient
                $WebClient.DownloadFile($url, $destination)
                Write-Host "�_�E�����[�h����"
            } -ArgumentList $url, $destination | Out-Null

            while (!(Test-Path $destination)) {
                logger.info "�t�@�C���쐬�҂�..."
                Start-Sleep -Seconds 1
            }
            $timePassed = 0.1
            while ((Get-Item $destination).Length -lt $fileSize) {              
                $downloadSize = (Get-Item $destination).Length
                $ratio = [Math]::Ceiling($downloadSize / $fileSize * 100)
                $dlRate = $ratio / $timePassed
                $remainingPercent = (100 - $ratio)
                $remainingTime = [Math]::Floor($remainingPercent / $dlRate)
                logger.dlprogress "���f�����_�E�����[�h��: $ratio % | ~ �c�� $remainingTime �b  "
                Start-Sleep -Seconds 1
                $timePassed += 1
            }
            logger.success
        }
    }
    else {
        logger.info "1�ȏ�̃`�F�b�N�|�C���g���f�����m�F���܂���"
    }
}
function Get-Version {
    $result = @{
        Long  = ""
        Short = ""
    }
    $softInfo = Get-ItemProperty -LiteralPath 'hkcu:\Software\Empire Media Science\A1111 Web UI Autoinstaller'
    if ($softInfo) {
        logger.info "�����`���[�o�[�W���� $($softInfo.Version)"
        $short = $softInfo.Version.Split(".")
        $result.Long = $softInfo.Version
        $result.Short = $short[0] + "." + $short[1]
    }
    else {
        logger.warn "�o�[�W�����s��"
        $result.Long = "�o�[�W�����s��"
        $result.Short = "2023.01"
    }
    return $result
}
function Get-GPUInfo {
    $adapterMemory = (Get-ItemProperty -Path "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*" -Name "HardwareInformation.AdapterString", "HardwareInformation.qwMemorySize" -Exclude PSPath -ErrorAction SilentlyContinue)

    $adapters = @()

    foreach ($adapter in $adapterMemory) {
        if ($adapter."HardwareInformation.AdapterString" -ilike "NVIDIA*") {
            $adapterObject = @{
                Model = $adapter."HardwareInformation.AdapterString"
                VRAM  = [math]::round($adapter."HardwareInformation.qwMemorySize" / 1GB)
            }
            $adapters += $adapterObject
        }
    }
    switch ($adapters.Count) {
        { $_ -gt 0 } { return @($adapters)[0] }
        { $_ -eq 0 } { return $false }
    }
}
function Get-WebUICommitHash {
    $hash = Get-Content $hashPath
    if ($hash) { return $hash }
}

#Settings related functions
#-----------------------------
function Write-Settings($settings) {
    logger.action "�ݒ�t�@�C���̍X�V" -success
    $settings | ConvertTo-Json -Depth 100 | Out-File $settingsPath
    logger.success
}
function New-Settings ($oldsettings) {   
    $defs = Import-Defs
    $newSettings = @()
    foreach ($def in $defs) { 
        $newSettings += @{ 
            arg     = $def.arg
            enabled = $false
            value   = "" 
        }
    }
    if ($oldsettings) {
        foreach ($oldSetting in $oldsettings) {
            $newSetting = $newSettings | Where-Object { $_.arg -eq $oldSetting.arg }
            if ($newSetting) {
                $newSetting.arg = $oldSetting.arg
                $newSetting.enabled = $oldSetting.enabled
                $newSetting.value = $oldSetting.value
            }
        }
    }
    Write-Settings $newSettings
    return $newSettings
}
function Restore-Settings {    
    $oldsettings = ""
    if (Test-Path $settingsPath) {
        $settingsfile = Get-Content $settingsPath
        logger.info "�ݒ�t�@�C����������܂���B �ǂݍ��ݒ�"
        $oldsettings = $settingsfile | ConvertFrom-Json
    }
    else {
        logger.info "�ݒ�t�@�C����������܂���, �쐬��"
    }
    $settings = New-Settings $oldsettings
    return $settings
}
function Update-Settings($param, $settings) {
    $setting = $settings | Where-Object { $_.arg -ilike $param.name }
    if ($param.Tag -eq "path") {
        if ($setting.arg -ilike "*dir") {
            $path = Select-Folder -InitialDirectory $setting.value
        }
        else {
            $path = Select-File -InitialDirectory $setting.value
        }
        if ($path) {
            logger.info "$($param.text) ���X�V $path"
            $setting.value = $path
            $setting.enabled = $true
        }
    }
    elseif ($param.Tag -eq "string") {
        logger.info "Args�̒ǉ��X�V"
        $setting.value = $param.text
    }
    else {
        logger.info "$($param.text) ���X�V $($param.Checked)"
        $setting.enabled = $param.Checked
    }
    Write-Settings $settings
        
}
function Import-Defs {
    $defs = Get-Content .\definitions.json | ConvertFrom-Json
    return $defs
}
function Convert-SettingsToArguments ($settings) {
    $string = ""
    foreach ($setting in $settings) {
        if ($setting.arg -ilike "git*" ) {
            # Not Command Line Arg Related
        }
        elseif ($setting.arg -eq "Add" ) {
            $string += "$($setting.value) "
        }
        else {
            if ($setting.enabled -eq $true) {
                if ($setting.value -eq "") {
                    $string += "--$($setting.arg) "
                }
                else {
                    $string += "--$($setting.arg) '$($setting.value )' "
                }
            }
        }
    }
    if ($string -ne " ") {
        logger.info "���݂̈���:", $string
    }
    else {
        logger.info "�������ݒ肳��Ă��Ȃ�"
    }
    return $string
}
function Convert-BatToGitOptions ($batFile) {
    $GitOptions = @( 
        @{
            arg     = "git-Ext"
            enabled = $false
        },
        @{
            arg     = "git-UI"
            enabled = $false
        }
    )
    if ($batFile -notcontains "::") {
        logger.info "git�I�v�V������������܂���"
    }
    else {
        if ($batFile -contains "�g���@�\�̍X�V") {
            $GitOptions[0].enabled = $true
        }
        if ($batFile -contains "WebUI�̍X�V") {
            $GitOptions[1].enabled = $true
        }
    }
    return $GitOptions
}


#UI related functions
#-----------------------------
function Select-Folder ([string]$InitialDirectory) {
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, "�t�H���_��I�����ĉ�����", 0, "")
        
    if ($folder) { return $folder.Self.Path } else { return '' }
}
function Select-File([string]$InitialDirectory) { 
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = $webuiPath
    $dialog.Title = "�t�@�C����I�����ĉ�����"
    If ($dialog.ShowDialog() -eq "�L�����Z��") {
        return ''
    }   
    return $dialog.FileName 
}


#General Settings functions
#-----------------------------
function Update-WebUI ($enabled) {
    if ($enabled) {
        logger.web -Type "�X�V" -Object "Webui�̍X�V��"
        Set-Location $webuiPath
        git pull origin
        logger.success "����"
    }
}
function Update-Extensions ($enabled) {
    if ($enabled) {
        Set-Location $extPath
        $exts = Get-ChildItem $extPath -Directory
        if ($exts) {
            foreach ($ext in $exts) {         
                logger.web -Type "�X�V" -Object "�g���@�\�̍X�V��: $ext"
                Set-Location $ext.Fullname
                git pull origin 
            }
            logger.success "����"
            return
        }
        logger.info "extensions�t�H���_�[��extension������܂���"
    }
}
function Clear-Outputs {
    $Exprompt = [system.windows.messagebox]::Show("�ȑO�ɐ��������摜�͑S�č폜����܂����A�X�����ł����H`n`n����͉摜���폜���Ȃ��ꍇ�́A�uNo�v���N���b�N���ĉ������B`n`n���̋@�\�𖳌��ɂ���ɂ́A�����`���[�́u�������ꂽ�摜����������v�̃`�F�b�N���O���ĉ������B", '�x��', 'Yes No', '�x��')
    if ($Exprompt -eq "Yes") {
        logger.action "�o�̓f�B���N�g���̑S�o�͂��폜��"
        if ($webuiConfig -ne "" -and $webUIConfig.outdir_samples -ne "") {
            logger.info "$($webUIConfig.outdir_samples)�ɂ���J�X�^���o�̓f�B���N�g�����������܂��B"
            Get-ChildItem $webUIConfig.outdir_samples -Force -Recurse -File | Where-Object { $_.Extension -eq ".png" -or $_.Extension -eq ".jpg" } | Remove-Item -Force
        }
        else {
            if ($outputsPath) {
                logger.info "�f�t�H���g�̏o�̓f�B���N�g�����폜��"
                Get-ChildItem $outputsPath -Force -Recurse -File | Where-Object { $_.Extension -eq ".png" -or $_.Extension -eq ".jpg" } | Remove-Item -Force
            }
        }
        logger.success "����"
    }
}