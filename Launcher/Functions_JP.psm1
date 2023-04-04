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
            logger.info "レジストリに Python $pyVersion が見つかりました：" "$pyPath"
            if ($pyVersion -notlike "3.10.6150.1013") {
                $Exprompt = [system.windows.messagebox]::Show("Python 3.10 ($pyVersion)を以前にインストールしましたが、正しいバージョンではありません。 エラーにつながる可能性があります。`n`n解決するには、システムからPython 3.10の全てのバージョンをアンインストールし、ランチャーを再起動して下さい。`n`n続けますか?", "Python $pyVersionは推奨されません。", 'Yes No')
                logger.warn "これはPythonの推奨バージョンではないので、おそらくエラーが発生します。"
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
        logger.web -Type "download" -Object "Python 3.10 が見つからないので、ダウンロードとインストール実施中。暫くお待ち下さい"
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.10.6/python-3.10.6-amd64.exe" -OutFile "$tempFolder\python.exe"
        ."$tempFolder\python.exe" /quiet InstallAllUsers=0 PrependPath=1
        logger.success "Done"
        $Global:pyPath = Search-RegForPyPath
    }
    logger.info "PATHからPythonの記述を削除します"
    $env:Path = [System.String]::Join(";", $($env:Path.split(';') | Where-Object { $_ -notmatch "python" }))
    logger.action "Python 3.10をパスに追加します" -success
    $env:Path += ";$Global:pyPath"
    logger.success
    return
}
function Install-git {
    $gitInPath = Get-Command git -ErrorAction SilentlyContinue
    if ($gitInPath) {
        $Global:gitPath = $gitInPath.Source
        logger.info "Gitが見つかり、PATHに既にあります:" "$($gitInPath.Source)"
        return
    }
    else {
        if (!(Test-Path "$gitPath\bin\git.exe")) {
            logger.web -Type "download" -Object "Gitが見つからないので、ダウンロードとインストールを実施中。暫くお待ち下さい "
            Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.38.1.windows.1/Git-2.38.1-64-bit.exe" -OutFile "$tempFolder\git.exe"
            ."$tempFolder\git.exe" /VERYSILENT /NORESTART
            logger.success
        }
        else {
            logger.info "Gitを確認" "$("$env:ProgramFiles\Git")"
        }
        if (!(Get-Command git -ErrorAction SilentlyContinue)) {
            logger.action "PATHにGitが見つからないので、追加します" -success
            $env:Path += ";$gitPath\bin"
            logger.success
            return
        }
        else {
            logger.info "GitはPATHにある"
        }
    }
}
function Install-WebUI {
    if (!(Test-Path $webuiPath)) {
        logger.web -Type "download" -Object "Automatic1111 SD WebUI gitのクローン化"
        git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui $webuiPath
        logger.success "完了"
        return
    }
    logger.info "Automatic1111 SD WebUIが見つかりました。:" "$webuiPath"
}
function Reset-WebUI {
    $Exprompt = [system.windows.messagebox]::Show("これは、WebUIフォルダを完全に消去し、githubから再作成するもので、全ての重要なデータとモデルをバックアップしている事を確認して下さい。`n`n 本当にWebUIフォルダをリセットしたいですか?", '気をつけてください', 'Yes No', '警告')
    if ($Exprompt -eq "Yes") {
        logger.action "Webuiフォルダの削除" -success
        Remove-Item $webuiPath -Recurse -Force
        logger.success
        Install-WebUI 
    }
}
function Import-BaseModel {
    $ckptDirSetting = $settings | Where-Object { $_.arg -eq "ckpt-dir" }
    if (($ckptDirSetting.enabled -eq $false) -and !(Get-ChildItem $modelsPath | Where-Object { $_.extension -ne ".txt" })) {
        $Exprompt = [system.windows.messagebox]::Show("あなたのインストール先にモデルが見つかりませんでした。Stable Diffusion 1.5 ベースモデルをダウンロードしますか？`n`n詳細が分からない場合「Yes」のクリック推奨します。`n`nこれはしばらく時間がかかるので、暫くお待ち下さい。", 'SD 1.5モデルをインストールしますか？', 'Yes No')
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
                Write-Host "ダウンロード完了"
            } -ArgumentList $url, $destination | Out-Null

            while (!(Test-Path $destination)) {
                logger.info "ファイル作成待ち..."
                Start-Sleep -Seconds 1
            }
            $timePassed = 0.1
            while ((Get-Item $destination).Length -lt $fileSize) {              
                $downloadSize = (Get-Item $destination).Length
                $ratio = [Math]::Ceiling($downloadSize / $fileSize * 100)
                $dlRate = $ratio / $timePassed
                $remainingPercent = (100 - $ratio)
                $remainingTime = [Math]::Floor($remainingPercent / $dlRate)
                logger.dlprogress "モデルをダウンロード中: $ratio % | ~ 残り $remainingTime 秒  "
                Start-Sleep -Seconds 1
                $timePassed += 1
            }
            logger.success
        }
    }
    else {
        logger.info "1つ以上のチェックポイントモデルを確認しました"
    }
}
function Get-Version {
    $result = @{
        Long  = ""
        Short = ""
    }
    $softInfo = Get-ItemProperty -LiteralPath 'hkcu:\Software\Empire Media Science\A1111 Web UI Autoinstaller'
    if ($softInfo) {
        logger.info "ランチャーバージョン $($softInfo.Version)"
        $short = $softInfo.Version.Split(".")
        $result.Long = $softInfo.Version
        $result.Short = $short[0] + "." + $short[1]
    }
    else {
        logger.warn "バージョン不明"
        $result.Long = "バージョン不明"
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
    logger.action "設定ファイルの更新" -success
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
        logger.info "設定ファイルが見つかりません。 読み込み中"
        $oldsettings = $settingsfile | ConvertFrom-Json
    }
    else {
        logger.info "設定ファイルが見つかりません, 作成中"
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
            logger.info "$($param.text) を更新 $path"
            $setting.value = $path
            $setting.enabled = $true
        }
    }
    elseif ($param.Tag -eq "string") {
        logger.info "Argsの追加更新"
        $setting.value = $param.text
    }
    else {
        logger.info "$($param.text) を更新 $($param.Checked)"
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
        logger.info "現在の引数:", $string
    }
    else {
        logger.info "因数が設定されていない"
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
        logger.info "gitオプションが見つかりません"
    }
    else {
        if ($batFile -contains "拡張機能の更新") {
            $GitOptions[0].enabled = $true
        }
        if ($batFile -contains "WebUIの更新") {
            $GitOptions[1].enabled = $true
        }
    }
    return $GitOptions
}


#UI related functions
#-----------------------------
function Select-Folder ([string]$InitialDirectory) {
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, "フォルダを選択して下さい", 0, "")
        
    if ($folder) { return $folder.Self.Path } else { return '' }
}
function Select-File([string]$InitialDirectory) { 
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = $webuiPath
    $dialog.Title = "ファイルを選択して下さい"
    If ($dialog.ShowDialog() -eq "キャンセル") {
        return ''
    }   
    return $dialog.FileName 
}


#General Settings functions
#-----------------------------
function Update-WebUI ($enabled) {
    if ($enabled) {
        logger.web -Type "更新" -Object "Webuiの更新中"
        Set-Location $webuiPath
        git pull origin
        logger.success "成功"
    }
}
function Update-Extensions ($enabled) {
    if ($enabled) {
        Set-Location $extPath
        $exts = Get-ChildItem $extPath -Directory
        if ($exts) {
            foreach ($ext in $exts) {         
                logger.web -Type "更新" -Object "拡張機能の更新中: $ext"
                Set-Location $ext.Fullname
                git pull origin 
            }
            logger.success "成功"
            return
        }
        logger.info "extensionsフォルダーにextensionがありません"
    }
}
function Clear-Outputs {
    $Exprompt = [system.windows.messagebox]::Show("以前に生成した画像は全て削除されますが、宜しいですか？`n`n今回は画像を削除しない場合は、「No」をクリックして下さい。`n`nこの機能を無効にするには、ランチャーの「生成された画像を消去する」のチェックを外して下さい。", '警告', 'Yes No', '警告')
    if ($Exprompt -eq "Yes") {
        logger.action "出力ディレクトリの全出力を削除中"
        if ($webuiConfig -ne "" -and $webUIConfig.outdir_samples -ne "") {
            logger.info "$($webUIConfig.outdir_samples)にあるカスタム出力ディレクトリを検索します。"
            Get-ChildItem $webUIConfig.outdir_samples -Force -Recurse -File | Where-Object { $_.Extension -eq ".png" -or $_.Extension -eq ".jpg" } | Remove-Item -Force
        }
        else {
            if ($outputsPath) {
                logger.info "デフォルトの出力ディレクトリを削除中"
                Get-ChildItem $outputsPath -Force -Recurse -File | Where-Object { $_.Extension -eq ".png" -or $_.Extension -eq ".jpg" } | Remove-Item -Force
            }
        }
        logger.success "完了"
    }
}