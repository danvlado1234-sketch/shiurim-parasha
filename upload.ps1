# ============================================================
#  העלאת שיעורי פרשת שבוע - סקריפט אוטומטי מלא
#  1. מעלה ל-R2   2. מייצר list.json
#  3. דוחף ל-GitHub   4. שולח מייל לרשימת תפוצה
#  שימוש: powershell -ExecutionPolicy Bypass -File .\upload.ps1
#  עם -NoEmail: אותו דבר, בלי שלב המייל ובלי רישום ב"חדש השבוע" באתר
#  (להשלמת שיעורים משנים קודמות - "העלה בלי מייל.bat")
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

# ---- משיכת עדכונים מ-GitHub (נוסף ספטמבר 2026) ----
# בעיה שהתעוררה בפועל: אחרי שינוי שנעשה ישירות ב-GitHub (עריכה באתר או
# מיזוג PR), הדחיפה בשלב 3 נדחתה ("rejected - fetch first") והאתר לא
# התעדכן, עד שהריצו git pull ידנית. עכשיו מושכים בתחילת כל הרצה, לפני
# שנוגעים בכלום. קבצי שמע/PDF חסומים ב-.gitignore, אז זה לא נוגע בהם.
# אם המשיכה נכשלת (אין אינטרנט, התנגשות) - מבטלים מיזוג חלקי ומדווחים,
# וממשיכים: ההעלאה לענן לא תלויה בזה.
Write-Host "[0/4] מושך עדכונים מ-GitHub..." -ForegroundColor Yellow
Write-Status "מושך עדכונים מ-GitHub..."
git pull origin main --no-rebase --no-edit
if ($LASTEXITCODE -eq 0) {
    Write-Host "      מעודכן." -ForegroundColor Green
} else {
    # רק אם באמת נשאר מיזוג חלקי (בלי 2>$null: ב-PowerShell 5 עם Stop, פלט
    # שגיאה מופנה של git עוצר את כל הסקריפט)
    if (Test-Path (Join-Path $root '.git\MERGE_HEAD')) { git merge --abort }
    Write-Host "      !! המשיכה מ-GitHub נכשלה - ממשיך בכל זאת (ייתכן שהפרסום באתר ייכשל)" -ForegroundColor Red
    Write-Status "המשיכה מ-GitHub נכשלה - ממשיך בכל זאת." -Kind error
}
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
# גם סיכומי PDF: השם שלהם חייב להיות זהה לשם השמע, אחרת כפתור "סיכום" לא יופיע
$spacedFiles = Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.Extension -match '^\.(m4a|mp3|pdf)$' -and $_.Name -match ' ' -and $_.FullName -notmatch '\\\.git\\' }
# גרשיים/גרש בשם (למשל השנה הוקלדה תשפ"ז במקום תשפז) - האתר לא מזהה אותם.
# חוץ מנושא שיעור העיון (מה שאחרי "_עיון_"), שם הם חלק מהכותרת: לקיחת_ד'_מינים
$quoteChars = '["''\u05F3\u05F4]'
function Get-CleanBase([string]$b) {
    $b = $b -replace ' ', '_'
    $i = $b.IndexOf('_עיון_')
    if ($i -ge 0) { return ($b.Substring(0, $i) -replace $quoteChars, '') + $b.Substring($i) }
    return $b -replace $quoteChars, ''
}
$quotedFiles = Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.Extension -match '^\.(m4a|mp3|pdf)$' -and (Get-CleanBase $_.BaseName) -cne ($_.BaseName -replace ' ', '_') -and $_.FullName -notmatch '\\\.git\\' }

if ($mp4Files -or $spacedFiles -or $quotedFiles) {
    Write-Host "[0/4] מתקן שמות קבצים (וואטסאפ / רווחים / גרשיים)..." -ForegroundColor Yellow
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

    # m4a/mp3/pdf עם רווחים ו/או גרשיים בשם (קובץ שהגיע במייל או הוקלד ידנית) -
    # מחליפים רווחים בקו תחתון ומוחקים גרשיים. אחרי תיקון ה-mp4, כי שמו כבר השתנה.
    $toClean = @(Get-ChildItem -Path $root -Recurse -File |
        Where-Object { $_.Extension -match '^\.(m4a|mp3|pdf)$' -and (Get-CleanBase $_.BaseName) -cne $_.BaseName -and $_.FullName -notmatch '\\\.git\\' })
    foreach ($f in $toClean) {
        $newName = (Get-CleanBase $f.BaseName) + $f.Extension
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

# ---- בדיקת שמות קבצים (נוסף ספטמבר 2026) ----
# בעיה: קובץ ששמו לא תקין עולה לענן ונכנס לרשימה, אבל האתר מתעלם ממנו -
# והשיעור פשוט לא מופיע, בלי שום הודעה. כאן בודקים מראש, באותו פענוח בדיוק
# כמו parseFilename ב-index.html, ומזהירים (בחלון ובדף הסטטוס). לא עוצרים
# את ההעלאה ולא משנים שמות לבד - רק מתריעים, עם הצעה לשם הנכון.
# רשימת השמות חייבת להיות זהה ל-CHUMASHIM ב-index.html.
$VALID_NAMES = @(
    'בראשית','נח','לך לך','וירא','חיי שרה','תולדות','ויצא','וישלח','וישב','מקץ','ויגש','ויחי',
    'שמות','וארא','בא','בשלח','יתרו','משפטים','תרומה','תצוה','כי תשא','ויקהל','פקודי',
    'ויקרא','צו','שמיני','תזריע','מצורע','אחרי מות','קדושים','אמור','בהר','בחוקותי',
    'במדבר','נשא','בהעלותך','שלח','קרח','חוקת','בלק','פינחס','מטות','מסעי',
    'דברים','ואתחנן','עקב','ראה','שופטים','כי תצא','כי תבוא','נצבים','וילך','האזינו','וזאת הברכה',
    'ראש השנה','יום כיפור','סוכות','שמחת תורה','חנוכה','עשרה בטבת','טו בשבט','תענית אסתר','פורים','פסח','לג בעומר','שבועות','שבעה עשר בתמוז','תשעה באב',
    'ויקהל פקודי','תזריע מצורע','אחרי מות קדושים','בהר בחוקותי','מטות מסעי','נצבים וילך'
)
$GEM = @{ 'א'=1;'ב'=2;'ג'=3;'ד'=4;'ה'=5;'ו'=6;'ז'=7;'ח'=8;'ט'=9;'י'=10;'כ'=20;'ל'=30;'מ'=40;'נ'=50;'ס'=60;'ע'=70;'פ'=80;'צ'=90;'ק'=100;'ר'=200;'ש'=300;'ת'=400;'ך'=20;'ם'=40;'ן'=50;'ף'=80;'ץ'=90 }
function Get-YearValue([string]$y) {
    $sum = 0
    foreach ($ch in $y.ToCharArray()) { $k = [string]$ch; if (-not $GEM.ContainsKey($k)) { return 0 }; $sum += $GEM[$k] }
    return $sum
}
# מרחק עריכה (כמה אותיות שונות) - להצעת "האם התכוונת ל..."
function Get-EditDistance([string]$a, [string]$b) {
    # טבלה חד-ממדית ($d[i * w + j]) - PowerShell 5 של Windows לא מצליח לפענח
    # אינדקס דו-ממדי ($d[$i, $j]) בתוך קריאה ל-[Math]::Min
    $w = $b.Length + 1
    $d = New-Object 'int[]' (($a.Length + 1) * $w)
    for ($i = 0; $i -le $a.Length; $i++) { $d[$i * $w] = $i }
    for ($j = 0; $j -le $b.Length; $j++) { $d[$j] = $j }
    for ($i = 1; $i -le $a.Length; $i++) {
        for ($j = 1; $j -le $b.Length; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $del = $d[($i - 1) * $w + $j] + 1
            $ins = $d[$i * $w + $j - 1] + 1
            $sub = $d[($i - 1) * $w + $j - 1] + $cost
            $d[$i * $w + $j] = [Math]::Min([Math]::Min($del, $ins), $sub)
        }
    }
    return $d[$a.Length * $w + $b.Length]
}
# מפענח שם קובץ כמו האתר. מחזיר @{ ok; name; year; key; why }
function Test-ShiurName([string]$fileName) {
    $base = $fileName -replace '\.(mp3|m4a)$', ''
    $tokens = @($base -split '_' | Where-Object { $_ })
    if ($tokens.Count -gt 0 -and ($tokens[0] -eq 'פרשת' -or $tokens[0] -eq 'מועד')) { $tokens = @($tokens | Select-Object -Skip 1) }
    $iyun = $false; $shabbat = ''
    # "עיון" ואחריו (לא חובה) נושא השיעור: סוכות_תשפז_עיון_לקיחת_ד'_מינים
    $iI = [array]::IndexOf($tokens, 'עיון')
    if ($iI -ge 0) {
        $iyun = if ($iI + 1 -lt $tokens.Count) { $tokens[($iI + 1)..($tokens.Count - 1)] -join ' ' } else { 'כן' }
        $tokens = @($tokens | Select-Object -First $iI)
    }
    if ($tokens.Count -ge 2 -and $tokens[-2] -eq 'שבת') { $shabbat = $tokens[-1]; $tokens = @($tokens | Select-Object -First ($tokens.Count - 2)) }
    $iL = [array]::IndexOf($tokens, 'שיעור'); $iP = [array]::IndexOf($tokens, 'חלק')
    $lesson = ''; $part = ''
    if ($iL -ge 0) { $end = if ($iP -gt $iL) { $iP } else { $tokens.Count }; if ($end - 1 -ge $iL + 1) { $lesson = ($tokens[($iL + 1)..($end - 1)] -join ' ') } }
    if ($iP -ge 0) { $end = if ($iL -gt $iP) { $iL } else { $tokens.Count }; if ($end - 1 -ge $iP + 1) { $part = ($tokens[($iP + 1)..($end - 1)] -join ' ') } }
    $marks = @(@($iL, $iP) | Where-Object { $_ -ge 0 })
    if ($marks.Count) { $cut = ($marks | Measure-Object -Minimum).Minimum; $tokens = @($tokens | Select-Object -First $cut) }
    if ($tokens.Count -lt 2) { return @{ ok = $false; why = 'חסרה שנה או שם פרשה (צריך למשל: פרשת_נח_תשפז)' } }
    $year = $tokens[-1]
    $name = ($tokens | Select-Object -First ($tokens.Count - 1)) -join ' '
    if ((Get-YearValue $year) -eq 0) { return @{ ok = $false; why = "השנה '$year' לא מזוהה (צריך אותיות בלבד, למשל תשפז)" } }
    if ($VALID_NAMES -notcontains $name) {
        $best = $null; $bestD = 99
        foreach ($v in $VALID_NAMES) { $dist = Get-EditDistance $name $v; if ($dist -lt $bestD) { $bestD = $dist; $best = $v } }
        $hint = if ($bestD -le 2) { " - האם התכוונת ל'$best'?" } else { '' }
        return @{ ok = $false; why = "שם הפרשה/המועד '$name' לא מזוהה$hint" }
    }
    return @{ ok = $true; name = $name; year = $year; key = "$name|$year|$lesson|$part|$shabbat|$iyun" }
}

$nameProblems = New-Object System.Collections.Generic.List[string]
$seenKeys = @{}
foreach ($m in $chumashim) {
    $all = @(Get-ChildItem -Path $m.FullName -Recurse -File | Where-Object { $_.Extension -match '^\.(m4a|mp3|pdf)$' })
    foreach ($f in ($all | Where-Object { $_.Extension -match '^\.(m4a|mp3)$' })) {
        $rel = $f.FullName.Substring($root.Length + 1) -replace '\\', '/'
        $r = Test-ShiurName $f.Name
        if (-not $r.ok) { $nameProblems.Add("$rel לא יופיע באתר: $($r.why)"); continue }
        # אותו שיעור פעמיים (למשל שני קבצים לאותה פרשה ושנה בלי שיעור_א/שיעור_ב)
        if ($seenKeys.ContainsKey($r.key)) { $nameProblems.Add("$rel ו-$($seenKeys[$r.key]) יופיעו באתר באותה כותרת - להבדיל ביניהם עם _שיעור_א / _שיעור_ב") }
        else { $seenKeys[$r.key] = $rel }
    }
    # סיכום בלי שיעור: ל-PDF חייב להיות קובץ שמע באותו שם בדיוק, באותה תיקייה
    foreach ($f in ($all | Where-Object { $_.Extension -eq '.pdf' })) {
        $hasAudio = (Test-Path (Join-Path $f.DirectoryName ($f.BaseName + '.m4a'))) -or (Test-Path (Join-Path $f.DirectoryName ($f.BaseName + '.mp3')))
        if (-not $hasAudio) {
            $rel = $f.FullName.Substring($root.Length + 1) -replace '\\', '/'
            $nameProblems.Add("$rel - אין קובץ שמע באותו שם, כפתור 'סיכום' לא יופיע")
        }
    }
}
if ($nameProblems.Count -gt 0) {
    Write-Host "!! בעיות בשמות קבצים ($($nameProblems.Count)):" -ForegroundColor Red
    foreach ($msg in $nameProblems) {
        Write-Host "   - $msg" -ForegroundColor Red
        Write-Status "בדיקת שמות: $msg" -Kind error
    }
    Write-Host "   ההעלאה ממשיכה; אחרי תיקון השם - להריץ שוב." -ForegroundColor Red
    Write-Host ""
}

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

# גרסה לכל PDF (תחילת MD5 של התוכן) - האתר מוסיף אותה לקישור (?v=), כדי
# שסיכום שהוחלף ייפתח מחדש ולא מהמטמון של הדפדפן/הטלפון בכתובת הישנה.
$pdfVersions = [ordered]@{}
foreach ($f in ($files | Where-Object { $_ -match '\.pdf$' })) {
    $pdfVersions[$f] = (Get-FileHash -Algorithm MD5 -Path (Join-Path $root $f)).Hash.Substring(0, 8).ToLower()
}
$versionsJson = if ($pdfVersions.Count) { $pdfVersions | ConvertTo-Json -Depth 2 } else { '{}' }
[System.IO.File]::WriteAllText((Join-Path $root 'pdf-versions.json'), $versionsJson, (New-Object System.Text.UTF8Encoding($false)))

# תאריך העלאה לכל שיעור חדש (uploads.json) - ממנו האתר בונה את "חדש השבוע".
# בהעלאת השלמות (-NoEmail) לא רושמים, כדי ששיעורים ישנים לא יופיעו שם כחדשים.
# קוראים עם UTF-8 מפורש (ראו ההערה על list.json למעלה).
$uploadsPath = Join-Path $root 'uploads.json'
$uploads = [ordered]@{}
if (Test-Path $uploadsPath) {
    try {
        $rawUploads = [System.IO.File]::ReadAllText($uploadsPath, [System.Text.Encoding]::UTF8)
        foreach ($um in [regex]::Matches($rawUploads, '"((?:[^"\\]|\\.)*)"\s*:\s*"(\d{4}-\d{2}-\d{2})"')) {
            $uploads[$um.Groups[1].Value] = $um.Groups[2].Value
        }
    } catch { $uploads = [ordered]@{} }
}
if (-not $NoEmail -and $newAudioPaths.Count -gt 0) {
    $today = Get-Date -Format "yyyy-MM-dd"
    foreach ($f in $newAudioPaths) { $uploads[$f] = $today }
}
$uploadsJson = if ($uploads.Count) { $uploads | ConvertTo-Json -Depth 2 } else { '{}' }
[System.IO.File]::WriteAllText($uploadsPath, $uploadsJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("      list.json נוצר עם " + $files.Count + " קבצים.") -ForegroundColor Green
Write-Status "רשימת השיעורים עודכנה." -Kind done
Write-Host ""

# ---- שלב 3: דחיפה ל-GitHub ----
Write-Host "[3/4] דוחף ל-GitHub..." -ForegroundColor Yellow
Write-Status "[3/4] מפרסם את העדכון באתר..."
git add list.json pdf-versions.json uploads.json index.html 2>$null
$changes = git status --porcelain list.json pdf-versions.json uploads.json index.html
if ($changes) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    git commit -m "עדכון שיעורים $stamp" | Out-Null
    git push origin HEAD:main
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      נדחף ל-GitHub בהצלחה!" -ForegroundColor Green
        Write-Status "האתר עודכן בהצלחה." -Kind done
    } else {
        Write-Host "      !! שגיאה בדחיפה ל-GitHub. לתיקון להריץ כאן:" -ForegroundColor Red
        Write-Host "         git pull origin main --no-rebase --no-edit" -ForegroundColor Red
        Write-Host "         git push origin HEAD:main" -ForegroundColor Red
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
    # "עיון" (עיוני/הלכתי) ואחריו אולי נושא השיעור - תמיד בסוף השם. מוסרים מ"עיון"
    # והלאה לפני חיתוך שיעור/חלק, אחרת זה נחשב בטעות לשנה. זהה ל-index.html.
    $iI = [array]::IndexOf($tokens, 'עיון')
    if ($iI -ge 1) { $tokens = $tokens[0..($iI - 1)] }
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
