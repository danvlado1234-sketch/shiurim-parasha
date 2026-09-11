# ============================================================
#  העלאת שיעורי פרשת שבוע - סקריפט אוטומטי מלא
#  1. יוצר סיכום AI   2. מעלה ל-R2   3. מייצר list.json
#  4. דוחף ל-GitHub   5. שולח מייל לרשימת תפוצה
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

# ---- זיהוי מוקדם של שיעורים חדשים (לפני ההעלאה) ----
# חייב לקרות *לפני* שלב ההעלאה, כי סיכום ה-AI (בשלב הבא) צריך להיווצר
# מקומית לפני שהתיקייה מועתקת ל-R2 - אחרת ה-PDF ייווצר רגע אחרי
# שהתיקייה כבר הועלתה, ולא יעלה עד ההרצה הבאה.
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

# "צריך סיכום" לצורך *ה-AI* = פשוט אין לו קובץ PDF תואם. בכוונה לא לפי
# "חדש": אם יצירת הסיכום נכשלה בהרצה קודמת (למשל מגבלת קצב של Gemini),
# השיעור כבר נרשם ב-list.json ולעולם לא היה נחשב "חדש" שוב - והסיכום שלו
# לא היה נוצר לעולם. לפי הקריטריון הזה, ההרצה הבאה פשוט משלימה אותו.
$needSummary = @($audioFiles | Where-Object {
    $pdfRel = [System.IO.Path]::ChangeExtension($_, ".pdf")
    -not (Test-Path (Join-Path $root $pdfRel))
})

# ---- שלב 1: יצירת סיכום AI + PDF - היברידי (נוסף אוגוסט 2026) ----
# NotebookLM מתמלל (יציב מאוד, בלי הזיות - זה תמלול מילולי), Gemini כותב
# את הוורט מהתמלול בטקסט בלבד (לא שמע!). למה השילוב הזה, לא אחד מהשניים
# לבד:
#   - Gemini API ישיר על שמע סבל מ-503/תקיעות תכופות (אוגוסט 2026), אבל
#     קריאות טקסט הוכיחו את עצמן יציבות לגמרי גם באותם רגעים.
#   - NotebookLM עצמו (ask) כן יציב, אבל "מסגנן" את התשובה בקול שלו -
#     ציטוטים, הדגשות, הצעות המשך - ולא נותן שליטה מלאה על הסגנון כמו
#     קריאת API ישירה עם פרומפט מלוטש.
#   - התמלול המילולי (לא "הבנת שמע") הוא כשלעצמו הגנה חזקה נגד המצאות -
#     Gemini רואה את המילים בפועל, לא "מנחש" מהאזנה.
# אם משהו נכשל - לא עוצר את שאר התהליך, רק מדלג על הסיכום לאותו שיעור.
# השמע תמיד עולה בכל מקרה, וההרצה הבאה תשלים (ראו "צריך סיכום" למעלה).
if ($needSummary.Count -gt 0) {
    Write-Host "[1/5] יוצר סיכום AI ($($needSummary.Count) שיעורים ללא סיכום)..." -ForegroundColor Yellow
    Write-Status "[1/5] יוצר סיכום AI ל-$($needSummary.Count) שיעורים..."
    # $env:APPDATA ו-[Environment]::GetFolderPath('ApplicationData') שניהם
    # נכשלו בפועל (ספטמבר 2026) כשמריצים דרך לחיצה כפולה על ה-bat, למרות
    # שהקבצים תמיד נמצאים שם באמת כשבודקים ידנית - כנראה שני האמצעים קוראים
    # מאותו מקור (רישום/סביבה) שמיושן בתהליכים שנפתחים מ-Explorer. לכן לא
    # מנחשים איך לחשב את הנתיב הנכון - בודקים כמה נתיבים מועמדים ידועים
    # (כולל הנתיב המוחלט בפועל של המשתמש הזה) ולוקחים את הראשון שבאמת קיים.
    $candidateAppDataRoots = @(
        "$env:APPDATA",
        [Environment]::GetFolderPath('ApplicationData'),
        "$env:USERPROFILE\AppData\Roaming",
        'C:\Users\1\AppData\Roaming'
    ) | Where-Object { $_ } | Select-Object -Unique
    $nlmConfigPath = $null
    $geminiConfigPath = $null
    $configReady = $false
    for ($cfgAttempt = 1; $cfgAttempt -le 5 -and -not $configReady; $cfgAttempt++) {
        foreach ($candidateRoot in $candidateAppDataRoots) {
            $tryNlm = Join-Path $candidateRoot 'shiurim-ai\notebooklm-config.json'
            $tryGemini = Join-Path $candidateRoot 'shiurim-ai\gemini-config.json'
            if ((Test-Path $tryNlm) -and (Test-Path $tryGemini)) {
                $nlmConfigPath = $tryNlm; $geminiConfigPath = $tryGemini; $configReady = $true
                break
            }
        }
        if (-not $configReady -and $cfgAttempt -lt 5) { Start-Sleep -Seconds 2 }
    }
    if (-not $configReady) {
        Write-Host "         (קובצי ה-config לא נמצאו באף אחד מהנתיבים המועמדים: $($candidateAppDataRoots -join ' | '))" -ForegroundColor DarkGray
    }
    if ($configReady) {
        $nlmCfg = Get-Content $nlmConfigPath -Raw | ConvertFrom-Json
        $nlmExe = $nlmCfg.NotebookLmExe
        if (-not $nlmExe -or -not (Test-Path $nlmExe)) { $nlmExe = "notebooklm" }
        $notebookId = $nlmCfg.NotebookId

        # התחברות NotebookLM נצפתה פגה מדי פעם באמצע הרצה, בלי אזהרה מראש -
        # בעיה חמורה במיוחד להרצה ללא השגחה (בלי אף אחד שידע להריץ login).
        # לכן מרעננים אותה מראש, לפני שמתחילים בכלל, כדי לתפוס את זה מוקדם
        # ובבירור. NOTEBOOKLM_HEADLESS_REAUTH מונע פתיחת חלון דפדפן גלוי אם
        # אפשר לרענן בשקט; login עצמו, כשההתחברות עדיין תקפה בפועל (רק
        # הקובץ המקומי היה מיושן), רק שומר מחדש ולא דורש הזנת פרטים.
        $env:NOTEBOOKLM_HEADLESS_REAUTH = "1"
        $loginOk = $false
        $loginOut = $null
        try {
            # בלי 2>&1: login מדפיס הודעות סטטוס תקינות ("Already logged in.",
            # "Account: ...") ל-stderr, ו-2>&1 הופך אותן ב-Windows PowerShell
            # לשגיאה עוצרת - כלומר דיווח כוזב על כשל דווקא כשהכל עבד.
            $loginOut = & $nlmExe login
            # exe שנכשל לא זורק חריגה ב-PowerShell, ולכן try/catch לבדו לא
            # תופס כשל אמיתי - חייבים לבדוק exit code מפורשות.
            $loginOk = ($LASTEXITCODE -eq 0)
        } catch {
            # לכאן מגיעים רק אם ה-exe עצמו לא נמצא / לא ניתן להרצה.
            $loginOut = $_.Exception.Message
        }
        if (-not $loginOk) {
            Write-Host "      !! רענון התחברות NotebookLM נכשל - ייתכן שהסיכומים ידולגו." -ForegroundColor Red
            # מדפיסים את הפלט בפועל: בלי זה כשל התחברות נראה זהה לכל כשל אחר,
            # ואי אפשר לדעת אם צריך login ידני או שמדובר במשהו אחר לגמרי.
            if ($loginOut) {
                Write-Host "         $($loginOut -join ' ')" -ForegroundColor DarkGray
            }
            Write-Status "רענון התחברות NotebookLM נכשל." -Kind error
        }

        $geminiCfg = Get-Content $geminiConfigPath -Raw | ConvertFrom-Json
        $geminiKeys = @($geminiCfg.ApiKeys | Where-Object { $_ })
        $geminiModel = "gemini-3.5-flash"

        # תקלות זמניות מול NotebookLM (רשת, שרת עמוס) - ממתינים ומנסים שוב.
        # הרענון המקדים (login בתחילת ההרצה) לא תמיד מספיק: נצפה בפועל
        # (1.9.2026) מקרה שבו login דיווח הצלחה, אבל קריאת source בפועל
        # נכשלה בכל זאת עם "Authentication expired" - כנראה שהבדיקה של
        # login שטחית יותר מהאימות שקריאות ה-API עצמן דורשות. לכן: אם
        # השגיאה בפועל מכילה "Authentication expired/invalid", מרעננים
        # שוב עם login (לא רק ממתינים) לפני הניסיון הבא.
        function Invoke-NotebookLmWithRetry([scriptblock]$call) {
            $maxAttempts = 3
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try { return & $call }
                catch {
                    if ($attempt -eq $maxAttempts) { throw }
                    $msg = $_.Exception.Message
                    if ($msg -match 'Authentication expired|Authentication.*invalid') {
                        Write-Host "         (התחברות פגה באמצע - מרענן שוב)" -ForegroundColor Yellow
                        Write-Status "התחברות NotebookLM פגה באמצע - מרענן שוב..."
                        try { & $nlmExe login | Out-Null } catch {}
                    } else {
                        $wait = 20 * $attempt
                        Write-Host "         (תקלה זמנית מול NotebookLM - ממתין $wait שניות ומנסה שוב)" -ForegroundColor Yellow
                        Write-Status "תקלה זמנית מול NotebookLM - ממתין $wait שניות ומנסה שוב..."
                        Start-Sleep -Seconds $wait
                    }
                }
            }
        }

        function Invoke-GeminiTextLocal($prompt, $key) {
            $uri = "https://generativelanguage.googleapis.com/v1beta/models/$($geminiModel):generateContent?key=$key"
            $body = @{ contents = @(@{ parts = @(@{ text = $prompt }) }) } | ConvertTo-Json -Depth 10
            $resp = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json; charset=utf-8" -ErrorAction Stop -TimeoutSec 180
            return $resp.candidates[0].content.parts[0].text
        }
        # תקלות זמניות מול Gemini (429/5xx/ניתוק חיבור) - ממתינים ומנסים שוב.
        function Invoke-GeminiWithRetry([scriptblock]$call) {
            $maxAttempts = 4
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try { return & $call }
                catch {
                    $msg = $_.Exception.Message
                    $isTransient = ($msg -match '429|Too Many Requests|50[0234]|Server Unavailable|Internal Server Error|Bad Gateway|Timed out|connection.*closed|kept alive')
                    if (-not $isTransient -or $attempt -eq $maxAttempts) { throw }
                    $wait = 25 * $attempt
                    Write-Host "         (תקלה זמנית מול Gemini - ממתין $wait שניות ומנסה שוב)" -ForegroundColor Yellow
                    Write-Status "תקלה זמנית מול Gemini - ממתין $wait שניות ומנסה שוב..."
                    Start-Sleep -Seconds $wait
                }
            }
        }
        # עוברים על מפתחות Gemini לפי הסדר, כל אחד עם מלוא הניסיונות החוזרים.
        function Invoke-GeminiTextWithFallback($prompt) {
            $lastError = $null
            for ($i = 0; $i -lt $geminiKeys.Count; $i++) {
                if ($i -gt 0) {
                    Write-Host "         (מפתח Gemini $i נכשל - עובר למפתח $($i+1) מתוך $($geminiKeys.Count))" -ForegroundColor Yellow
                    Write-Status "מפתח Gemini $i מוצה - עובר למפתח $($i+1)..."
                }
                try { return Invoke-GeminiWithRetry { Invoke-GeminiTextLocal $prompt $geminiKeys[$i] } }
                catch { $lastError = $_ }
            }
            throw $lastError
        }

        $vortPromptParasha = "זהו תמלול (לא מדויק במאה אחוז - ייתכנו שגיאות הקלדה/הגייה קלות, התעלם מהן) של שיעור תורה בעברית על פרשת השבוע. כתוב את תוכן השיעור כוורט לשבת - בסיפור זורם, חי ועסיסי, עם שפה עשירה, חמה ומושכת, לא כרשימת נקודות יבשה ולא במבנה אקדמי. הימנע לגמרי מפנייה ישירה מדומה לקהל שאינו קיים בפועל - אל תפתח בהזמנה לשבת סביב שולחן, ואל תסיים בפניות כמו אהוביי או ברכות לקהל. התמקד רק בתוכן השיעור והסיפור עצמו, בגוף שלישי או בסגנון מספר-סיפור. כלל הפתיחה (הכי חשוב): המשפט הראשון חייב לעגן במפורש את שם הפרשה ואת הנושא או השאלה שבה עוסק השיעור - למשל בנוסח כמו בלב פרשת פלונית ניצבת, או במרכזה של פרשת פלונית. אסור לפתוח בתיאור אווירה ספרותי, בסצנה ציורית או בתיאור רגשות של דמות, שמעכבים את הבנת הנושא. הקורא חייב לדעת כבר מהמשפט הראשון על איזו פרשה מדובר ומה הנושא. בנוסף, שמור על לשון בהירה ולא מליצית מדי - עדיף משפט חד וברור על פני משפט מקושט. ארבעה כללי כתיבה נוספים: (1) אל תחזור על אותו רעיון פעמיים בניסוחים שונים - כל פסקה חייבת לקדם את הרעיון, לא לחזור עליו. (2) אם בשיעור יש משל, סיפור או דוגמה מוחשית - פתח אותו במלואו ובחיות, זה הלב של הוורט, ואל תסתפק באזכור חטוף. עדיף המחשה מוחשית אחת על פני שלושה הסברים מופשטים. (3) סיים בנקודה החדה של הרעיון עצמו, לא במוסר השכל כללי ומטיף כמו תכלית עבודתנו היא. (4) מבנה הפתיחה חייב לכלול שני שלבים נפרדים ומופרדים לגמרי, בסדר הזה: קודם כל להעמיד את הדברים - לספר בגוף שלישי מה קורה בפרשה, איזה פסוק או מקרה עומד במרכז, בלי לרמוז עדיין על שאלה או בעיה. המשפט הראשון של כל השיעור חייב להיות עובדתי טהור לגמרי - אסור שיכיל את המילים מעורר/מעוררת/שאלה/תמיהה/קושיה/תהייה או כל רמז לכך שמתקרבת בעיה. רק אחרי שהעובדות הונחו במלואן (בדרך כלל פסקה שלמה), עוברים לקושיה עצמה כפסקה נפרדת ומובחנת. כשעוברים לקושיה, מותר להשתמש בביטויי מעבר (כאן מתעוררת תמיהה, אלא ש, וכיוצא באלה) - אבל רק שם, לא קודם - ואסור לדחוס את הקושיה למשפט אחד צפוף - צריך לתת לה להתפתח על פני כמה משפטים, בקצב חי ודרמטי, כאילו השואל עצמו נבוך ומופתע מהסתירה, בלי לפנות ישירות לקורא ובלי אינטראקציה מדומה. חשוב מאוד: הישען אך ורק על מה שמופיע בתמלול בפועל - אם שם, מקור, או ציטוט לא ברור מהתמלול או נראה כשגיאת תמלול, אל תנחש ואל תמציא, נסח באופן כללי יותר או השמט. אל תזכיר בטקסט הסופי שמדובר בתמלול, ואל תתרגם לשפה אחרת. אל תוסיף כותרות, אל תשתמש בסימוני Markdown כמו כוכביות."

        # אותם כללים בדיוק כמו vortPromptParasha, רק על מועדי ישראל (ראש השנה,
        # סוכות, חנוכה וכו') במקום פרשת השבוע - ראו הערה ליד $MOADIM למטה
        # למה זה פיצול נפרד ולא אותו פרומפט עם מילה מוחלפת.
        $vortPromptMoed = "זהו תמלול (לא מדויק במאה אחוז - ייתכנו שגיאות הקלדה/הגייה קלות, התעלם מהן) של שיעור תורה בעברית על מועד ממועדי ישראל (חג, צום, או יום מיוחד בלוח השנה היהודי). כתוב את תוכן השיעור כדבר תורה למועד - בסיפור זורם, חי ועסיסי, עם שפה עשירה, חמה ומושכת, לא כרשימת נקודות יבשה ולא במבנה אקדמי. הימנע לגמרי מפנייה ישירה מדומה לקהל שאינו קיים בפועל - אל תפתח בהזמנה לחג או למועד סביב שולחן, ואל תסיים בפניות כמו אהוביי או ברכות לקהל. התמקד רק בתוכן השיעור והסיפור עצמו, בגוף שלישי או בסגנון מספר-סיפור. כלל הפתיחה (הכי חשוב): המשפט הראשון חייב לעגן במפורש את שם המועד ואת הנושא או השאלה שבה עוסק השיעור - למשל בנוסח כמו בלב מועד פלוני עומד, או במרכזו של מועד פלוני. אסור לפתוח בתיאור אווירה ספרותי, בסצנה ציורית או בתיאור רגשות של דמות, שמעכבים את הבנת הנושא. הקורא חייב לדעת כבר מהמשפט הראשון על איזה מועד מדובר ומה הנושא. בנוסף, שמור על לשון בהירה ולא מליצית מדי - עדיף משפט חד וברור על פני משפט מקושט. ארבעה כללי כתיבה נוספים: (1) אל תחזור על אותו רעיון פעמיים בניסוחים שונים - כל פסקה חייבת לקדם את הרעיון, לא לחזור עליו. (2) אם בשיעור יש משל, סיפור או דוגמה מוחשית - פתח אותו במלואו ובחיות, זה הלב של דבר התורה, ואל תסתפק באזכור חטוף. עדיף המחשה מוחשית אחת על פני שלושה הסברים מופשטים. (3) סיים בנקודה החדה של הרעיון עצמו, לא במוסר השכל כללי ומטיף כמו תכלית עבודתנו היא. (4) מבנה הפתיחה חייב לכלול שני שלבים נפרדים ומופרדים לגמרי, בסדר הזה: קודם כל להעמיד את הדברים - לספר בגוף שלישי מהו עניינו של המועד, איזה הלכה, פסוק או עניין עומד במרכזו, בלי לרמוז עדיין על שאלה או בעיה. המשפט הראשון של כל השיעור חייב להיות עובדתי טהור לגמרי - אסור שיכיל את המילים מעורר/מעוררת/שאלה/תמיהה/קושיה/תהייה או כל רמז לכך שמתקרבת בעיה. רק אחרי שהעובדות הונחו במלואן (בדרך כלל פסקה שלמה), עוברים לקושיה עצמה כפסקה נפרדת ומובחנת. כשעוברים לקושיה, מותר להשתמש בביטויי מעבר (כאן מתעוררת תמיהה, אלא ש, וכיוצא באלה) - אבל רק שם, לא קודם - ואסור לדחוס את הקושיה למשפט אחד צפוף - צריך לתת לה להתפתח על פני כמה משפטים, בקצב חי ודרמטי, כאילו השואל עצמו נבוך ומופתע מהסתירה, בלי לפנות ישירות לקורא ובלי אינטראקציה מדומה. חשוב מאוד: הישען אך ורק על מה שמופיע בתמלול בפועל - אם שם, מקור, או ציטוט לא ברור מהתמלול או נראה כשגיאת תמלול, אל תנחש ואל תמציא, נסח באופן כללי יותר או השמט. אל תזכיר בטקסט הסופי שמדובר בתמלול, ואל תתרגם לשפה אחרת. אל תוסיף כותרות, אל תשתמש בסימוני Markdown כמו כוכביות."

        # פרומפט לשיעורי "עיון" (דגל _עיון בשם הקובץ - ראו CLAUDE.md) - סגנון
        # שונה לגמרי מוורט: לא סיפור זורם עם משל בלב, אלא חיבור תורני-עיוני
        # כתוב. משמש בלי קשר למועד/פרשה (בפועל כרגע רק מועדים, לפי הכלל
        # ב-CLAUDE.md ש"בפרשות זה תמיד וורטים").
        # הגרסה הראשונה (ספטמבר 2026) כתבה "הסבר בשפה פשוטה" למאזין - נכון
        # מבחינת תוכן אבל לא בסגנון. המשתמש העלה קובץ Word עם חיבור הלכתי
        # אמיתי שאביו (הרב) כתב בעצמו על סוגיה דומה (ד' תעניות), כדוגמה
        # לסגנון הרצוי - צפוף, מצטט לשון מקורות במירכאות, מעברים אנליטיים
        # קצרים (והנה/ונראה לבאר/אשר על כן/ודו"ק), בלי משפטי מבוא מיותרים.
        # הפרומפט למטה נבנה ישירות לפי הדוגמה הזו.
        $vortPromptIyun = "זהו תמלול (לא מדויק במאה אחוז - ייתכנו שגיאות הקלדה/הגייה קלות, התעלם מהן) של שיעור עיון הלכתי בעברית, העוסק בסוגיא או בשאלה הלכתית מסוימת. כתוב את תוכן השיעור כחיבור תורני-עיוני קצר וכתוב, ממש בסגנון קטע מתוך ספר הלכה או חידושי תורה - לא כהסבר בשפה פשוטה למאזין, ולא כוורט או כסיפור. זהו הבדל מהותי הן בתוכן והן בסגנון הכתיבה עצמה. סגנון הכתיבה הנדרש: משפטים תמציתיים וממוקדים, בלי משפטי פתיחה כלליים כמו 'הדיון ההלכתי שלפנינו עוסק ב...' - יש לפתוח ישר במקור המרכזי או בניסוח השאלה ההלכתית עצמה. יש לצטט את לשון המקורות (גמרא, שולחן ערוך, ראשונים ואחרונים) כפי שהם מנוסחים בפועל בתמלול, בתוך מירכאות, ולא רק לתמצת אותם במילים חופשיות. אם מוזכר בתמלול מיקום מדויק (כגון סימן וסעיף, דף בגמרא) ונשמע ברור, יש לציין אותו במדויק בפורמט המקובל (למשל סי' תק״נ ס״א, דף י״ח ע״ב); אם המיקום אינו ברור מהתמלול, אין לנחש ואין להמציא - יש להשמיט את הציון המדויק ולהזכיר את המקור בלי מספר. יש להשתמש במעברים אנליטיים תורניים קצרים כגון 'והנה', 'ונראה לבאר', 'ומעתה נראה', 'ולפי זה', 'אשר על כן', 'ואולם', ואפשר לסיים קטע מסקנה ב'ודו״ק' - במקום מעברים סיפוריים או הסברים מאריכים. אין לפנות לקורא, ואין משלים, סצנות או תיאורים ציוריים אלא אם הם עצמם חלק מהסברה ההלכתית שהובאה בפועל בשיעור. מבנה: (1) פתיחה ישירה במקור המרכזי או בניסוח השאלה ההלכתית עצמה, בלי הקדמות. (2) פיתוח הדיון לפי סדר המקורות והשיטות כפי שהובאו בתמלול (פסוקים, גמרא, ראשונים, אחרונים), עם ציטוט לשונם ככל האפשר, כדיון מתפתח ולא כרשימה יבשה. (3) אם יש מחלוקת, קושי או מתח בין מקורות/שיטות כפי שהובא בשיעור - הצגתו במפורש, כולל עיקרי הטיעונים לכל צד. (4) מסקנה הלכתית תמציתית כפי שהובאה בפועל בשיעור, בלי מוסר השכל כללי. חשוב מאוד: הישען אך ורק על מה שמופיע בתמלול בפועל - אם שם, מקור, ציטוט, מספר סימן/סעיף/דף, או שיטה לא ברורים מהתמלול או נראים כשגיאת תמלול, אל תנחש ואל תמציא, נסח באופן כללי יותר או השמט לגמרי. אל תזכיר בטקסט הסופי שמדובר בתמלול, ואל תתרגם לשפה אחרת. אל תוסיף כותרות, אל תשתמש בסימוני Markdown כמו כוכביות."

        foreach ($relPath in $needSummary) {
            $audioFullPath = Join-Path $root $relPath
            $pdfFullPath = [System.IO.Path]::ChangeExtension($audioFullPath, ".pdf")
            try {
                $leafName = Split-Path $relPath -Leaf
                Write-Host ("      -> " + $leafName)

                $transcript = Invoke-NotebookLmWithRetry {
                    # אם המקור כבר קיים במחברת (למשל מהרצה קודמת שנכשלה בשלב
                    # מאוחר יותר) - משתמשים בו מחדש, לא מעלים כפילות (יש מכסה
                    # של 50 מקורות למחברת).
                    Write-Status "בודק אם $leafName כבר הועלה ל-NotebookLM..."
                    $listJson = & $nlmExe source list -n $notebookId --json | Out-String
                    if ($LASTEXITCODE -ne 0) { throw "source list נכשל: $listJson" }
                    $listObj = $listJson | ConvertFrom-Json
                    $existing = $listObj.sources | Where-Object { $_.title -eq $leafName } | Select-Object -First 1

                    if ($existing) {
                        $sourceId = $existing.id
                    } else {
                        Write-Status "מעלה כמקור ל-NotebookLM: $leafName"
                        $addJson = & $nlmExe source add "$audioFullPath" -n $notebookId --type file --title $leafName --json | Out-String
                        if ($LASTEXITCODE -ne 0) { throw "source add נכשל: $addJson" }
                        $addObj = $addJson | ConvertFrom-Json
                        $sourceId = $addObj.source.id
                        if (-not $sourceId) { throw "לא התקבל source id מ-NotebookLM" }
                    }

                    Write-Status "ממתין שהמקור יהיה מוכן: $leafName"
                    $waited = 0
                    $ready = $false
                    while ($waited -lt 150) {
                        $listJson2 = & $nlmExe source list -n $notebookId --json | Out-String
                        $listObj2 = $listJson2 | ConvertFrom-Json
                        $src = $listObj2.sources | Where-Object { $_.id -eq $sourceId }
                        if ($src.status -eq 'ready') { $ready = $true; break }
                        if ($src.status -eq 'error') { throw "המקור נכשל בעיבוד ב-NotebookLM" }
                        Start-Sleep -Seconds 5
                        $waited += 5
                    }
                    if (-not $ready) { throw "המקור לא הפך ל-ready תוך זמן סביר" }

                    Write-Status "מוציא תמלול: $leafName"
                    $tmpTranscriptPath = [System.IO.Path]::GetTempFileName()
                    & $nlmExe source fulltext $sourceId -n $notebookId --format text -o $tmpTranscriptPath --force | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "source fulltext נכשל" }
                    $text = [System.IO.File]::ReadAllText($tmpTranscriptPath, [System.Text.Encoding]::UTF8)
                    Remove-Item $tmpTranscriptPath -ErrorAction SilentlyContinue
                    if (-not $text) { throw "לא התקבל תמלול מ-NotebookLM" }
                    return $text
                }

                Write-Status "כותב את הוורט על: $leafName"
                # קודם בודקים את דגל "עיון" בשם הקובץ (תמיד אחרון, ראו CLAUDE.md) -
                # זה קובע סגנון (עיון הלכתי מול וורט), בלי קשר למועד/פרשה. רק אם
                # אין דגל עיון, ממשיכים לזיהוי הרגיל לפי תיקיית האב ("מועדים/...")
                # ולא לפי שם הקובץ - שמות קבצי מועדים אינם מתחילים ב"מועד_" (שם
                # הקובץ הוא רק <שם>_<שנה>, התיקייה כבר אומרת שזה מועד).
                $isIyunFile = $leafName -match '_עיון\.(m4a|mp3)$'
                $vortPrompt = if ($isIyunFile) { $vortPromptIyun }
                    elseif ($relPath -like 'מועדים/*') { $vortPromptMoed }
                    else { $vortPromptParasha }
                $fullPrompt = "$vortPrompt`n`n--- תמלול השיעור ---`n$transcript"
                $finalText = Invoke-GeminiTextWithFallback -prompt $fullPrompt

                # בניית PDF דרך Edge headless - בלי להתקין שום דבר נוסף
                $titleName = [System.IO.Path]::GetFileNameWithoutExtension($relPath) -replace '_', ' '
                $escaped = [System.Web.HttpUtility]::HtmlEncode($finalText) -replace "`r`n|`n", "</p><p>"
                # NotebookLM כותב הדגשות בפורמט Markdown (**טקסט**) - ממירים
                # ל-HTML אחרי ה-encode, כדי שהכוכביות לא יוצגו כטקסט גולמי.
                $escaped = $escaped -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
                $html = @"
<!DOCTYPE html><html lang="he" dir="rtl"><head><meta charset="UTF-8"><style>
body { font-family: 'David', 'Segoe UI', sans-serif; direction: rtl; padding: 40px 50px; line-height: 1.9; font-size: 16px; color: #241F16; }
h1 { font-size: 26px; border-bottom: 2px solid #1f4a33; padding-bottom: 10px; color: #1f4a33; }
p { margin: 0 0 14px; text-align: justify; }
</style></head><body><h1>$titleName</h1><p>$escaped</p></body></html>
"@
                $htmlTmpPath = [System.IO.Path]::ChangeExtension($audioFullPath, ".tmp.html")
                [System.IO.File]::WriteAllText($htmlTmpPath, $html, (New-Object System.Text.UTF8Encoding($false)))
                $edgeExe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
                if (-not (Test-Path $edgeExe)) { $edgeExe = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
                # בלי 2>&1: ב-Windows PowerShell, הפניית stderr של תוכנה חיצונית הופכת
                # אותו לשגיאה עוצרת (גם אם זו רק הודעת סטטוס תקינה של Edge, לא כשל אמיתי).
                & $edgeExe --headless --disable-gpu --print-to-pdf="$pdfFullPath" --no-pdf-header-footer "file:///$($htmlTmpPath -replace '\\','/')" | Out-Null
                Start-Sleep -Seconds 2
                Remove-Item $htmlTmpPath -ErrorAction SilentlyContinue
                if (Test-Path $pdfFullPath) {
                    Write-Host "         סיכום נוצר בהצלחה." -ForegroundColor Green
                    Write-Status "הסיכום על $leafName מוכן." -Kind done
                } else {
                    Write-Host "         !! יצירת ה-PDF נכשלה, ממשיך בלי סיכום לשיעור זה." -ForegroundColor Red
                    Write-Status "יצירת ה-PDF ל-$leafName נכשלה, ממשיך הלאה." -Kind error
                }
            } catch {
                Write-Host "         !! יצירת הסיכום נכשלה: $($_.Exception.Message) - ממשיך בלי סיכום לשיעור זה." -ForegroundColor Red
                Write-Status "הסיכום על $leafName נכשל, ממשיך הלאה." -Kind error
            }
        }
    } else {
        Write-Host "      הקמת NotebookLM ו/או Gemini טרם הושלמה - מדלג על סיכומים." -ForegroundColor Yellow
        Write-Status "הקמת NotebookLM ו/או Gemini טרם הושלמה - מדלג על סיכומים." -Kind error
    }
    Write-Host ""
}

# ---- שלב 2: העלאה ל-R2 ----
Write-Host "[2/5] מעלה שיעורים ל-R2..." -ForegroundColor Yellow
Write-Status "[2/5] מעלה שיעורים לענן..."
foreach ($m in $chumashim) {
    Write-Host ("      -> " + $m.Name)
    & "$root\rclone.exe" copy "$($m.FullName)" "r2:shiurim-parasha/$($m.Name)" --transfers 8 --checkers 8
    if ($LASTEXITCODE -ne 0) { Write-Host "      !! שגיאה בהעלאת $($m.Name)" -ForegroundColor Red }
}
Write-Host "      העלאה ל-R2 הושלמה." -ForegroundColor Green
Write-Status "ההעלאה לענן הושלמה." -Kind done
Write-Host ""

# ---- שלב 3: יצירת list.json ----
Write-Host "[3/5] מייצר list.json..." -ForegroundColor Yellow
Write-Status "[3/5] מעדכן את רשימת השיעורים באתר..."

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

# ---- שלב 4: דחיפה ל-GitHub ----
Write-Host "[4/5] דוחף ל-GitHub..." -ForegroundColor Yellow
Write-Status "[4/5] מפרסם את העדכון באתר..."
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

# ---- שלב 5: מייל לרשימת תפוצה על פרשות חדשות (נוסף אוגוסט 2026) ----
# רץ רק אם יש קבצי הגדרה - אם אין, פשוט מדלגים בשקט.
# עם -NoEmail (למשל בהעלאת גיבוי/backlog של שיעורים ישנים) - מדלגים
# על השלב הזה לגמרי, בלי לגעת בשאר התהליך (AI, R2, list.json, git).
if ($NoEmail) {
    Write-Host "[5/5] דילוג על שלב המייל (הורץ עם -NoEmail)." -ForegroundColor Yellow
    Write-Status "דילוג על שליחת מייל (הורץ בלי מייל)." -Kind done
    Write-Host ""
} else {
Write-Host "[5/5] בודק אם צריך לשלוח מייל לרשימת תפוצה..." -ForegroundColor Yellow
Write-Status "[5/5] בודק אם צריך לשלוח מייל..."

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
