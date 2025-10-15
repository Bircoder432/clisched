import api, terminal, strutils, strformat, times, options, algorithm
import cligen

const
  AppVersion = "1.0.0"
  AppName = "clisched"

const
  ColorHeader = fgCyan
  ColorSuccess = fgGreen
  ColorError = fgRed
  ColorWarning = fgYellow
  ColorMuted = fgWhite
  ColorAccent = fgMagenta
  ColorLesson = fgYellow
  ColorTeacher = fgGreen
  ColorCabinet = fgBlue

proc printHeader(msg: string) =
  stdout.setForegroundColor(ColorHeader)
  stdout.write "╔═ "
  stdout.resetAttributes()
  stdout.write msg
  echo ""

proc printSection(msg: string) =
  stdout.setForegroundColor(ColorHeader)
  stdout.write "╟─ "
  stdout.resetAttributes()
  stdout.write msg
  echo ""

proc printItem(msg: string) =
  stdout.setForegroundColor(ColorHeader)
  stdout.write "║  "
  stdout.resetAttributes()
  echo msg

proc printSuccess(msg: string) =
  stdout.setForegroundColor(ColorSuccess)
  echo "✓ " & msg
  stdout.resetAttributes()

proc printError(msg: string) =
  stderr.setForegroundColor(ColorError)
  stderr.writeLine "✗ " & msg
  stdout.resetAttributes()

proc printWarning(msg: string) =
  stdout.setForegroundColor(ColorWarning)
  echo "⚠ " & msg
  stdout.resetAttributes()

proc formatDate(dateStr: string): string =
  try:
    let parsedDate = parse(dateStr, "yyyy-MM-dd'T'HH:mm:ss'Z'")
    let today = now()
    let dateOnly = format(parsedDate, "dd.MM.yyyy")
    let dayName =
      case parsedDate.weekday
      of dMon: "Пн"
      of dTue: "Вт"
      of dWed: "Ср"
      of dThu: "Чт"
      of dFri: "Пт"
      of dSat: "Сб"
      of dSun: "Вс"

    if format(today, "yyyy-MM-dd") == format(parsedDate, "yyyy-MM-dd"):
      return &"{dateOnly} ({dayName}) 🎯"
    else:
      return &"{dateOnly} ({dayName})"
  except:
    return dateStr

proc formatLesson(lesson: Lesson, index: int): string =
  let numStr = &"{index + 1:2}"

  var result = ""
  result &= "  "
  stdout.setForegroundColor(ColorAccent)
  result &= &"{numStr}. "
  stdout.resetAttributes()

  stdout.setForegroundColor(ColorLesson)
  result &= &"{lesson.name:40}"
  stdout.resetAttributes()

  stdout.setForegroundColor(ColorTeacher)
  result &= &" {lesson.teacher:20}"
  stdout.resetAttributes()

  stdout.setForegroundColor(ColorCabinet)
  result &= &" {lesson.cabinet:10}"
  stdout.resetAttributes()


  if lesson.distance:
    stdout.setForegroundColor(ColorWarning)
    result &= " 📍"
    stdout.resetAttributes()

  return result

proc printScheduleDay(day: ScheduleDay, showHeader: bool = true) =
  if showHeader:
    printHeader(&"📅 {formatDate(day.date)} | 🕐 {day.starts} - {day.ends}")

  if day.lessons.len == 0:
    printItem("Нет занятий 🎉")
  else:
    for i, lesson in day.lessons:
      printItem(formatLesson(lesson, i))

proc printGroup(group: Group, index: int = -1): string =
  var result = ""
  if index >= 0:
    stdout.setForegroundColor(ColorAccent)
    result &= &"{index + 1:2}. "
    stdout.resetAttributes()

  stdout.setForegroundColor(ColorLesson)
  result &= &"{group.name:12}"
  stdout.resetAttributes()

  result &= " | "

  stdout.setForegroundColor(ColorCabinet)
  result &= &"🏛 {group.corpus}"
  stdout.resetAttributes()

  return result

proc groups(search: string = "", corpus: string = "", limit: int = 0) =
  let client = newScheduleClient()
  defer:
    client.close()

  try:
    if search != "":
      printHeader(&"🔍 Поиск групп: '{search}'")
      let foundGroups = client.findGroups(search)
      if foundGroups.len == 0:
        printWarning("Группы не найдены")
      else:
        let groupsToShow =
          if limit > 0:
            foundGroups[0 ..< min(limit, foundGroups.len)]
          else:
            foundGroups
        for i, group in groupsToShow:
          printItem(printGroup(group, i))
        printSuccess(&"Найдено: {foundGroups.len} групп")
    elif corpus != "":
      printHeader(&"🏛 Группы в корпусе: '{corpus}'")
      let corpusGroups = client.getGroupsByCorpus(corpus)
      if corpusGroups.len == 0:
        printWarning("Группы не найдены")
      else:
        let groupsToShow =
          if limit > 0:
            corpusGroups[0 ..< min(limit, corpusGroups.len)]
          else:
            corpusGroups
        for i, group in groupsToShow:
          printItem(printGroup(group, i))
        printSuccess(&"Найдено: {corpusGroups.len} групп")
    else:
      printHeader("📋 Все группы")
      let allGroups = client.getAllGroups()
      let groupsToShow =
        if limit > 0:
          allGroups[0 ..< min(limit, allGroups.len)]
        else:
          allGroups
      for i, group in groupsToShow:
        printItem(printGroup(group, i))
      printSuccess(&"Всего: {allGroups.len} групп")
  except ApiError as e:
    printError(e.msg)

proc schedule(
    group: string,
    today: bool = false,
    date: string = "",
    week: bool = false,
    teachers: bool = false,
) =
  if group == "":
    printError("Укажите группу")
    return

  let client = newScheduleClient()
  defer:
    client.close()

  try:
    if today:
      printHeader(&"🎯 Сегодня | Группа: {group}")
      let todaySchedule = client.getTodaySchedule(group)
      if todaySchedule.isSome:
        printScheduleDay(todaySchedule.get(), showHeader = true)
      else:
        printWarning("Расписания на сегодня нет 🎉")
    elif date != "":
      printHeader(&"📅 {date} | Группа: {group}")
      let dateSchedule = client.getScheduleForDate(group, date)
      if dateSchedule.isSome:
        printScheduleDay(dateSchedule.get(), showHeader = false)
      else:
        printWarning(&"Расписание на {date} не найдено")
    elif week:
      printHeader(&"📅 Текущая неделя | Группа: {group}")
      let weekSchedule = client.getCurrentWeekSchedule(group)
      if weekSchedule.len == 0:
        printWarning("Расписания на неделю нет")
      else:
        for day in weekSchedule:
          printScheduleDay(day)
        printSuccess(&"Дней с занятиями: {weekSchedule.len}")
    elif teachers:
      printHeader(&"👨‍🏫 Преподаватели | Группа: {group}")
      let schedule = client.getSchedule(group)
      var teachersSet: seq[string] = @[]

      for day in schedule:
        for lesson in day.lessons:
          if lesson.teacher != "" and lesson.teacher notin teachersSet:
            teachersSet.add(lesson.teacher)

      if teachersSet.len == 0:
        printWarning("Преподаватели не найдены")
      else:
        teachersSet.sort()
        for i, teacher in teachersSet:
          stdout.setForegroundColor(ColorAccent)
          stdout.write &"{i+1:2}. "
          stdout.resetAttributes()
          stdout.setForegroundColor(ColorTeacher)
          echo teacher
          stdout.resetAttributes()
        printSuccess(&"Всего преподавателей: {teachersSet.len}")
    else:
      printHeader(&"📅 Полное расписание | Группа: {group}")
      let fullSchedule = client.getSchedule(group)
      if fullSchedule.len == 0:
        printWarning("Расписание не найдено")
      else:
        for day in fullSchedule:
          printScheduleDay(day)
        printSuccess(&"Всего дней в расписании: {fullSchedule.len}")
  except ApiError as e:
    printError(e.msg)

proc version() =
  stdout.setForegroundColor(ColorHeader)
  echo &"""
┌──────────────────────┐
│     🎓 {AppName}      │
│     v{AppVersion}        │
└──────────────────────┘"""
  stdout.resetAttributes()

dispatchMulti(
  [
    groups,
    cmdName = "groups",
    help = {
      "search": "🔍 Поиск групп по шаблону",
      "corpus": "🏛 Фильтр по корпусу",
      "limit": "📏 Ограничить количество вывода",
    },
  ],
  [
    schedule,
    cmdName = "schedule",
    help = {
      "group": "📝 Название группы (обязательно)",
      "today": "🎯 Показать расписание на сегодня",
      "date":
        "📅 Показать расписание на конкретную дату",
      "week":
        "🗓️ Показать расписание на текущую неделю",
      "teachers":
        "👨‍🏫 Показать всех преподавателей группы",
    },
  ],
  [version, cmdName = "version"],
)
