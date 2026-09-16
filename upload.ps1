# ============================================================
#  העלאת שיעורי פרשת שבוע - סקריפט אוטומטי מלא
#  1. מעלה ל-R2   2. מייצר list.json
#  3. דוחף ל-GitHub   4. שולח מייל לרשימת תפוצה
#  שימוש: powershell -ExecutionPolicy Bypass -File .\upload.ps1
#  עם -NoEmail: אותו דבר, בלי שלב המייל (למשל בהעלאת גיבוי/backlog)
# ============================================================
param([switch]$NoEmail)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

# תיקיות שאינן חומשים - לדלג עליהן!
$skip = @('.github', '.git', 'shiurim-parasha')

# ---- דף סטטוס חי (נוסף אוגוסט 2026) ----
# בעיה שהתעוררה בפועל: כשההעלאה רצה, אין דרך לדעת "מה קורה עכשיו" בלי
# להביט בחלון קונסולה טכני. הפתרון: כל שלב נכתב גם לקובץ HTML פשוט
# (upload-status.html, לא עולה לגיטהאב - ראו .gitignore), שנפתח אוטומטית
# בדפדפן ומתרענן כל 2 שניות (meta refresh - עובד גם על קובץ מקומי,
# בניגוד ל-fetch/AJAX שחסום ב-file:// מטעמי אבטחה של הדפדפן).
Add-Type -AssemblyName System.Web
$statusPath = Join-Path $root 'upload-status.html'
$script:statusLog = New-Object System.Collections.Generic.List[hashtable]

function Write-Status {
    param([string]$Text, [string]$Kind = 'progress', [switch]$Final)
    $script:statusLog.Add(@{ text = $Text; kind = $Kind })
    $rows = ($script:statusLog | ForEach-Object {
        $c = switch ($_.kind) { 'done' {'#1f4a33'} 'error' {'#b3261e'} default {'#8a6d1f'} }
        $icon = switch ($_.kind) { 'done' {'✅'} 'error' {'⚠️'} default {'⏳'} }
        $esc = [System.Web.HttpUtility]::HtmlEncode($_.text)
        "<div style='color:$c;padding:6px 0;font-size:17px'>$icon&nbsp;&nbsp;$esc</div>"
    }) -join "`n"
    $refreshTag = if ($Final) { '' } else { '<meta http-equiv="refresh" content="2">' }
    $footer = if ($Final) { 'ההרצה הסתיימה - אפשר לסגור את הדף הזה.' } else { 'הדף מתרענן לבד כל 2 שניות...' }
    $html = @"
<!DOCTYPE html><html lang="he" dir="rtl"><head><meta charset="UTF-8">$refreshTag
<title>סטטוס העלאת שיעורים</title>
<style>
body { font-family: 'David', 'Segoe UI', sans-serif; direction: rtl; background:#faf7ef; padding: 40px; max-width: 700px; margin: 0 auto; }
h1 { color: #1f4a33; font-size: 24px; }
.log { background: white; border-radius: 12px; padding: 20px 26px; box-shadow: 0 2px 8px rgba(0,0,0,.08); }
.foot { margin-top: 18px; color: #8a7f68; font-size: 14px; }
</style></head>
<body><h1>📖 סטטוס העלאת שיעורים</h1><div class="log">$rows</div><div class="foot">$footer</div></body></html>
"@
    [System.IO.File]::WriteAllText($statusPath, $html, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Status "מתחיל..."
Start-Process $statusPath

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  העלאת שיעורי פרשת שבוע - תהליך אוטומטי" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---- תיקון אוטומטי לשמות קבצים ----
# וואטסאפ שומר הודעות קוליות בתור .mp4 (קונטיינר שמע, לא וידאו), ולא .m4a.
# בודקים בתוך הקובץ (לא רק לפי הסיומת) שאין בו track וידאו לפני שנוגעים בו -
# כדי שלעולם לא ישונה בטעות קובץ וידאו אמיתי שהגיע לכאן בטעות.
function Test-IsAudioOnlyMp4 {
    param([string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $text = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
        $hasVideo = $false; $hasAudio = $false
        $idx = 0
        while ($true) {
            $idx = $text.IndexOf('hdlr', $idx)
            if ($idx -lt 0) { break }
            if ($idx + 16 -le $text.Length) {
                $type = $text.Substring($idx + 12, 4)
                if ($type -eq 'vide') { $hasVideo = $true }
                if ($type -eq 'soun') { $hasAudio = $true }
            }
            $idx += 4
        }
        return ($hasAudio -and -not $hasVideo)
    } catch { return $false }
}

$mp4Files = Get-ChildItem -Path $root -Recurse -File -Filter '*.mp4' |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }
$spacedFiles = Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.Extension -match '^\.(m4a|mp3)$' -and $_.Name -match ' ' -and $_.FullName -notmatch '\\\.git\\' }

if ($mp4Files -or $spacedFiles) {
    Write-Host "[0/4] מתקן שמות קבצים (וואטסאפ / רווחים)..." -ForegroundColor Yellow
    Write-Status "מתקן שמות קבצים..."

    # mp4 מוואטסאפ: קודם בודקים שהוא שמע בלבד, ואז מתקנים סיומת + רווחים ביחד
    foreach ($f in $mp4Files) {
        if (Test-IsAudioOnlyMp4 -Path $f.FullName) {
            $newName = ($f.BaseName -replace ' ', '_') + '.m4a'
            $newPath = Join-Path $f.DirectoryName $newName
            if (Test-Path $newPath) {
                Write-Host "      !! $($f.Name) - כבר קיים קובץ בשם $newName, לא הוחלף (בדקו ידנית)" -ForegroundColor Red
            } else {
                Rename-Item -Path $f.FullName -NewName $newName
                Write-Host "      תוקן: $($f.Name) -> $newName" -ForegroundColor Green
            }
        } else {
            Write-Host "      !! $($f.Name) נראה כקובץ וידאו אמיתי - לא נגעתי בו, בדקו ידנית" -ForegroundColor Red
        }
    }

    # m4a/mp3 עם רווחים בשם (למשל קובץ שהגיע במייל או הוקלד ידנית) - רק מחליפים רווחים
    foreach ($f in $spacedFiles) {
        $newName = $f.Name -replace ' ', '_'
        $newPath = Join-Path $f.DirectoryName $newName
        if (Test-Path $newPath) {
            Write-Host "      !! $($f.Name) - כבר קיים קובץ בשם $newName, לא הוחלף (בדקו ידנית)" -ForegroundColor Red
        } else {
            Rename-Item -Path $f.FullName -NewName $newName
            Write-Host "      תוקן: $($f.Name) -> $newName" -ForegroundColor Green
        }
    }

    Write-Host ""
}

$chumashim = Get-ChildItem -Path $root -Directory |
    Where-Object { $_.Name -notmatch '^\.' -and $skip -notcontains $_.Name }

# ---- זיהוי שיעורים חדשים (לפני ש-list.json נכתב מחדש) ----
# קוראים עם קידוד UTF-8 מפורש (לא Get-Content רגיל) כי list.json נשמר בכוונה
# בלי BOM (כדי שהאתר יקרא אותו תקין) - ובלי לציין קידוד מפורש, PowerShell
# מפרש את זה לא נכון ומייצר עברית ג'יבריש. מפרקים גם ידנית עם regex במקום
# ConvertFrom-Json, כי בבדיקות זה התנהג לא אמין על המחרוזת הזו.
$listJsonPath = Join-Path $root 'list.json'
$oldFiles = @()
if (Test-Path $listJsonPath) {
    try {
        $rawOld = [System.IO.File]::ReadAllText($listJsonPath, [System.Text.Encoding]::UTF8)
        $oldFiles = @([regex]::Matches($rawOld, '"((?:[^"\\]|\\.)*)"') | ForEach-Object { $_.Groups[1].Value })
    } catch { $oldFiles = @() }
}

# רשימת השמע בלבד (לא כולל pdf)
$audioFiles = @()
foreach ($m in $chumashim) {
    Get-ChildItem -Path $m.FullName -Recurse -File |
        Where-Object { $_.Extension -match '^\.(m4a|mp3)$' } |
        ForEach-Object { $audioFiles += ($_.FullName.Substring($root.Length + 1) -replace '\\', '/') }
}
# "חדש" לצורך *המייל* = לא היה ב-list.json הקודם. זה חייב להישאר כך,
# אחרת היינו שולחים שוב מייל על שיעור ישן.
$newAudioPaths = @($audioFiles | Where-Object { $oldFiles -notcontains $_ })

# ---- שלב 1: העלאה ל-R2 ----
Write-Host "[1/4] מעלה שיעורים ל-R2..." -ForegroundColor Yellow
Write-Status "[1/4] מעלה שיעורים לענן..."
foreach ($m in $chumashim) {
    Write-Host ("      -> " + $m.Name)
    & "$root\rclone.exe" copy "$($m.FullName)" "r2:shiurim-parasha/$($m.Name)" --transfers 8 --checkers 8
    if ($LASTEXITCODE -ne 0) { Write-Host "      !! שגיאה בהעלאת $($m.Name)" -ForegroundColor Red }
}
Write-Host "      העלאה ל-R2 הושלמה." -ForegroundColor Green
Write-Status "ההעלאה לענן הושלמה." -Kind done
Write-Host ""

# ---- שלב 2: יצירת list.json ----
Write-Host "[2/4] מייצר list.json..." -ForegroundColor Yellow
Write-Status "[2/4] מעדכן את רשימת השיעורים באתר..."

$files = @()
foreach ($m in $chumashim) {
    Get-ChildItem -Path $m.FullName -Recurse -File |
        Where-Object { $_.Extension -match '^\.(m4a|mp3|pdf)$' } |
        ForEach-Object { $files += ($_.FullName.Substring($root.Length + 1) -replace '\\', '/') }
}
$files = $files | Sort-Object
$json = ConvertTo-Json @($files) -Depth 1
[System.IO.File]::WriteAllText($listJsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("      list.json נוצר עם " + $files.Count + " קבצים.") -ForegroundColor Green
Write-Status "רשימת השיעורים עודכנה." -Kind done
Write-Host ""

# ---- שלב 3: דחיפה ל-GitHub ----
Write-Host "[3/4] דוחף ל-GitHub..." -ForegroundColor Yellow
Write-Status "[3/4] מפרסם את העדכון באתר..."
git add list.json index.html 2>$null
$changes = git status --porcelain list.json index.html
if ($changes) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    git commit -m "עדכון שיעורים $stamp" | Out-Null
    git push origin HEAD:main
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      נדחף ל-GitHub בהצלחה!" -ForegroundColor Green
        Write-Status "האתר עודכן בהצלחה." -Kind done
    } else {
        Write-Host "      !! שגיאה בדחיפה ל-GitHub" -ForegroundColor Red
        Write-Status "פרסום העדכון באתר נכשל." -Kind error
    }
} else {
    Write-Host "      אין שינויים חדשים ל-GitHub." -ForegroundColor Green
    Write-Status "אין שינויים חדשים לפרסם." -Kind done
}
Write-Host ""

# ---- שלב 4: מייל לרשימת תפוצה על פרשות חדשות (נוסף אוגוסט 2026) ----
# רץ רק אם יש קבצי הגדרה - אם אין, פשוט מדלגים בשקט.
# עם -NoEmail (למשל בהעלאת גיבוי/backlog של שיעורים ישנים) - מדלגים
# על השלב הזה לגמרי, בלי לגעת בשאר התהליך (R2, list.json, git).
if ($NoEmail) {
    Write-Host "[4/4] דילוג על שלב המייל (הורץ עם -NoEmail)." -ForegroundColor Yellow
    Write-Status "דילוג על שליחת מייל (הורץ בלי מייל)." -Kind done
    Write-Host ""
} else {
Write-Host "[4/4] בודק אם צריך לשלוח מייל לרשימת תפוצה..." -ForegroundColor Yellow
Write-Status "[4/4] בודק אם צריך לשלוח מייל..."

$PAIRS = @(
    @('ויקהל','פקודי'), @('תזריע','מצורע'), @('אחרי מות','קדושים'),
    @('בהר','בחוקותי'), @('מטות','מסעי'), @('נצבים','וילך')
)
# אותה רשימת מועדים שמוגדרת בקוד ב-index.html (CHUMASHIM["מועדים"]) - חייבת
# להישאר זהה, כדי שהמייל יציג "מועד X" ולא "פרשת X" לשיעורי מועדים.
$MOADIM = @('ראש השנה','יום כיפור','סוכות','שמחת תורה','חנוכה','עשרה בטבת','טו בשבט','תענית אסתר','פורים','פסח','לג בעומר','שבועות','שבעה עשר בתמוז','תשעה באב')
function Get-ItemPrefix([string]$name) { if ($MOADIM -contains $name) { 'מועד' } else { 'פרשת' } }
function Get-PageKey([string]$name) {
    foreach ($p in $PAIRS) {
        $combined = $p[0] + ' ' + $p[1]
        if ($name -eq $combined -or $name -eq $p[0] -or $name -eq $p[1]) { return $combined }
    }
    return $name
}
function Get-ParashaKey([string]$relativePath) {
    $filename = Split-Path $relativePath -Leaf
    $base = $filename -replace '\.(mp3|m4a)$', ''
    $tokens = @($base -split '_' | Where-Object { $_ })
    if ($tokens.Count -gt 0 -and ($tokens[0] -eq 'פרשת' -or $tokens[0] -eq 'מועד')) { $tokens = $tokens[1..($tokens.Count - 1)] }
    # דגל "עיון" (עיוני/הלכתי, בלי ערך אחריו) - תמיד בסוף השם. חייב להיות
    # מוסר לפני חיתוך שיעור/חלק, אחרת הוא נחשב בטעות לשנה. זהה ל-index.html.
    if ($tokens.Count -gt 0 -and $tokens[$tokens.Count - 1] -eq 'עיון') { $tokens = $tokens[0..($tokens.Count - 2)] }
    # תגית "שבת <מילה>" (הגדול/שובה/זכור/פרה/החודש/חזון/נחמו וכו') - שיעור
    # ששייך לתיקיית ולשם הקובץ של מועד אחר (למשל שבת הגדול -> פסח). זוג
    # טוקנים, תמיד לפני "עיון" אם קיים. זהה ל-index.html.
    if ($tokens.Count -ge 2 -and $tokens[$tokens.Count - 2] -eq 'שבת') { $tokens = $tokens[0..($tokens.Count - 3)] }
    # חותכים בתגית המוקדמת מבין "שיעור" (שיעור נפרד) ו"חלק" (המשך אותו שיעור),
    # כדי שיישארו רק שם הפרשה והשנה. חייב להיות זהה ללוגיקה ב-index.html.
    $marks = @()
    foreach ($mark in @('שיעור','חלק')) {
        $i = [array]::IndexOf($tokens, $mark)
        if ($i -ge 0) { $marks += $i }
    }
    if ($marks.Count -gt 0) {
        $cut = ($marks | Measure-Object -Minimum).Minimum
        if ($cut -lt 1) { return $null }
        $tokens = $tokens[0..($cut - 1)]
    }
    if ($tokens.Count -lt 2) { return $null }
    $name = ($tokens[0..($tokens.Count - 2)]) -join ' '
    return Get-PageKey $name
}

$newPaths = $newAudioPaths
$newKeys = @($newPaths | ForEach-Object { Get-ParashaKey $_ } | Where-Object { $_ } | Sort-Object -Unique)

# מגבלת Gmail היא 25MB לכל ההודעה, וקידוד base64 לצירוף מוסיף כ-37% לגודל -
# אז קובץ גולמי צריך להיות מתחת ל~18MB כדי שבטוח יעבור. אם החדש של ההרצה הזו
# (בסך הכל) גדול מזה - לא מצרפים בכלל, רק שולחים קישור, כדי שלא ניכשל בשקט.
$maxAttachBytes = 18 * 1024 * 1024
$attachPaths = @($newPaths | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ })
$attachTotalBytes = ($attachPaths | ForEach-Object { (Get-Item $_).Length } | Measure-Object -Sum).Sum
$canAttach = ($attachPaths.Count -gt 0) -and ($attachTotalBytes -le $maxAttachBytes)

$mailConfigPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'shiurim-mail\mail-config.json'
$mailingListPath = Join-Path $root 'mailing-list.txt'

if ($newKeys.Count -eq 0) {
    Write-Host "      אין פרשה חדשה בהרצה הזו - לא נשלח מייל." -ForegroundColor Green
    Write-Status "אין פרשה חדשה - לא נשלח מייל." -Kind done
} elseif (-not (Test-Path $mailConfigPath)) {
    Write-Host "      הקמת המייל טרם הושלמה (חסר $mailConfigPath) - מדלג." -ForegroundColor Yellow
    Write-Status "הקמת המייל טרם הושלמה - מדלג." -Kind error
} elseif (-not (Test-Path $mailingListPath)) {
    Write-Host "      אין קובץ mailing-list.txt - מדלג." -ForegroundColor Yellow
    Write-Status "אין רשימת תפוצה - מדלג." -Kind error
} else {
    $recipients = @(Get-Content $mailingListPath | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    if ($recipients.Count -eq 0) {
        Write-Host "      רשימת התפוצה ריקה - לא נשלח מייל." -ForegroundColor Green
        Write-Status "רשימת התפוצה ריקה - לא נשלח מייל." -Kind done
    } else {
        try {
            $cfg = Get-Content $mailConfigPath -Raw | ConvertFrom-Json
            if ($cfg.AppPassword -match 'PASTE_') {
                Write-Host "      עדיין לא הוזן App Password אמיתי ב-$mailConfigPath - מדלג." -ForegroundColor Yellow
            } else {
                $siteBase = "https://danvlado1234-sketch.github.io/shiurim-parasha/"
                $items = $newKeys | ForEach-Object {
                    $link = $siteBase + "?parasha=" + [uri]::EscapeDataString($_)
                    "<li><a href=`"$link`">$(Get-ItemPrefix $_) $_</a></li>"
                }
                $linksHtml = "<ul>" + ($items -join "") + "</ul>"
                if ($canAttach) {
                    $body = "<p>שיעורים חדשים עלו, מצורפים לנוחיותכם. קישור ישיר (למי שמעדיף):</p>$linksHtml"
                } else {
                    $body = "<p>שיעורים חדשים עלו. הקובץ גדול מדי לצירוף ישיר במייל - להאזנה דרך הקישור:</p>$linksHtml"
                }
                $subject = if ($newKeys.Count -eq 1) { "שיעור חדש: $(Get-ItemPrefix $newKeys[0]) $($newKeys[0])" } else { "שיעורים חדשים עלו" }

                $securePw = ConvertTo-SecureString $cfg.AppPassword -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PSCredential($cfg.FromEmail, $securePw)
                # Send-MailMessage מחייב -To גם כשמשתמשים ב-Bcc, אז שמים שם את השולח עצמו.
                # הנמענים האמיתיים ב-Bcc בלבד - כדי שאף נמען לא יראה את כתובות האחרים.
                # -Encoding חובה: בלי זה Send-MailMessage שולח את הכותרת/הגוף בקידוד
                # שלא תומך בעברית, וכל הטקסט העברי מגיע אצל הנמען כסימני "?????".
                $mailParams = @{
                    From = $cfg.FromEmail; To = $cfg.FromEmail; Bcc = $recipients
                    Subject = $subject; Body = $body; BodyAsHtml = $true
                    Encoding = [System.Text.Encoding]::UTF8
                    SmtpServer = "smtp.gmail.com"; Port = 587; UseSsl = $true; Credential = $cred
                }
                if ($canAttach) { $mailParams.Attachments = $attachPaths }
                Send-MailMessage @mailParams
                if ($canAttach) {
                    Write-Host "      מייל נשלח ל-$($recipients.Count) נמענים (Bcc), עם השיעור מצורף." -ForegroundColor Green
                    Write-Status "מייל נשלח ל-$($recipients.Count) נמענים, עם השיעור מצורף." -Kind done
                } else {
                    Write-Host "      מייל נשלח ל-$($recipients.Count) נמענים (Bcc), רק קישור - הקובץ ($([math]::Round($attachTotalBytes/1MB,1))MB) גדול מדי לצירוף." -ForegroundColor Green
                    Write-Status "מייל נשלח ל-$($recipients.Count) נמענים, עם קישור בלבד." -Kind done
                }
            }
        } catch {
            Write-Host "      !! שליחת המייל נכשלה: $($_.Exception.Message)" -ForegroundColor Red
            Write-Status "שליחת המייל נכשלה." -Kind error
        }
    }
}
}

Write-Status "🎉 הכל הושלם!" -Kind done -Final

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "              הכל הושלם!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "לחץ Enter לסגירה"
