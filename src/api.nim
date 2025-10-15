import httpclient, json, tables, strutils, strformat, times, uri, options

type
  ApiError* = object of CatchableError

  Group* = object
    name*: string
    corpus*: string

  Lesson* = object
    name*: string
    cabinet*: string
    teacher*: string
    distance*: bool

  ScheduleDay* = object
    date*: string
    group*: string
    starts*: string
    ends*: string
    lessons*: seq[Lesson]

  ScheduleClient* = ref object
    baseUrl*: string
    client*: HttpClient
    timeout*: int

proc newScheduleClient*(
    baseUrl: string = "https://api.thisishyum.ru/schedule_api", timeout: int = 10000
): ScheduleClient =
  new(result)
  result.baseUrl = baseUrl
  result.timeout = timeout
  result.client = newHttpClient(timeout = timeout)

proc close*(client: ScheduleClient) =
  client.client.close()

proc makeRequest(client: ScheduleClient, url: string): JsonNode =
  let response = client.client.get(url)
  if response.code != Http200:
    raise newException(ApiError, &"HTTP {response.code}: {response.status}")
  return parseJson(response.body)

proc getAllGroups*(client: ScheduleClient): seq[Group] =
  let url = client.baseUrl & "/groups/"
  let data = client.makeRequest(url)

  for item in data:
    result.add(Group(name: item{"name"}.getStr(""), corpus: item{"Corpus"}.getStr("")))

proc getGroupsByCorpus*(client: ScheduleClient, corpus: string): seq[Group] =
  let url = client.baseUrl & "/groups/" & encodeUrl(corpus)
  let data = client.makeRequest(url)

  for item in data:
    result.add(Group(name: item{"name"}.getStr(""), corpus: item{"Corpus"}.getStr("")))

proc getSchedule*(client: ScheduleClient, group: string): seq[ScheduleDay] =
  let url = client.baseUrl & "/schedule/" & encodeUrl(group)
  let data = client.makeRequest(url)

  for dayData in data:
    var day = ScheduleDay(
      date: dayData{"date"}.getStr(""),
      group: dayData{"group"}.getStr(""),
      starts: dayData{"starts"}.getStr(""),
      ends: dayData{"ends"}.getStr(""),
      lessons: @[],
    )

    for lessonData in dayData{"lessons"}:
      day.lessons.add(
        Lesson(
          name: lessonData{"name"}.getStr(""),
          cabinet: lessonData{"cabinet"}.getStr(""),
          teacher: lessonData{"teacher"}.getStr(""),
          distance: lessonData{"distance"}.getBool(false),
        )
      )

    result.add(day)



proc getTodaySchedule*(client: ScheduleClient, group: string): Option[ScheduleDay] =
  let url = client.baseUrl & "/schedule/" & encodeUrl(group) & "/today"

  try:
    let response = client.client.get(url)

    if response.code == Http404:
      return none(ScheduleDay)

    if response.code != Http200:
      raise newException(ApiError, &"HTTP {response.code}: {response.status}")

    let data = parseJson(response.body)

    if data.kind == JObject:
      var day = ScheduleDay(
        date: data{"date"}.getStr(""),
        group: data{"group"}.getStr(""),
        starts: data{"starts"}.getStr(""),
        ends: data{"ends"}.getStr(""),
        lessons: @[]
      )

      let lessonsData = data{"lessons"}
      if lessonsData.kind == JArray:
        for lessonData in lessonsData:
          day.lessons.add(Lesson(
            name: lessonData{"name"}.getStr(""),
            cabinet: lessonData{"cabinet"}.getStr(""),
            teacher: lessonData{"teacher"}.getStr(""),
            distance: lessonData{"distance"}.getBool(false)
          ))

      return some(day)

    elif data.kind == JArray and data.len > 0:
      let dayData = data[0]
      var day = ScheduleDay(
        date: dayData{"date"}.getStr(""),
        group: dayData{"group"}.getStr(""),
        starts: dayData{"starts"}.getStr(""),
        ends: dayData{"ends"}.getStr(""),
        lessons: @[]
      )

      for lessonData in dayData{"lessons"}:
        day.lessons.add(Lesson(
          name: lessonData{"name"}.getStr(""),
          cabinet: lessonData{"cabinet"}.getStr(""),
          teacher: lessonData{"teacher"}.getStr(""),
          distance: lessonData{"distance"}.getBool(false)
        ))

      return some(day)

    return none(ScheduleDay)

  except Exception as e:
    raise newException(ApiError, &"Ошибка при получении расписания на сегодня: {e.msg}")

proc findGroups*(client: ScheduleClient, pattern: string): seq[Group] =
  let allGroups = client.getAllGroups()
  let patternLower = pattern.toLowerAscii()

  for group in allGroups:
    if patternLower in group.name.toLowerAscii():
      result.add(group)

proc getScheduleForDate*(
    client: ScheduleClient, group: string, date: string
): Option[ScheduleDay] =
  let schedule = client.getSchedule(group)
  for day in schedule:
    if day.date.startsWith(date):
      return some(day)
  return none(ScheduleDay)

proc getCurrentWeekSchedule*(client: ScheduleClient, group: string): seq[ScheduleDay] =
  let schedule = client.getSchedule(group)
  let today = now()
  let weekStart = today - initTimeInterval(days = today.weekday.ord)
  let weekEnd = weekStart + initTimeInterval(days = 6)

  for day in schedule:
    try:
      let dayDate = parse(day.date, "yyyy-MM-dd'T'HH:mm:ss'Z'")
      if dayDate >= weekStart and dayDate <= weekEnd:
        result.add(day)
    except:
      discard

proc `$`*(group: Group): string =
  &"{group.name} ({group.corpus})"

proc `$`*(lesson: Lesson): string =
  let distMarker = if lesson.distance: " [DIST]" else: ""
  &"{lesson.name} - {lesson.teacher} ({lesson.cabinet}){distMarker}"

proc `$`*(day: ScheduleDay): string =
  let dateStr =
    try:
      let parsedDate = parse(day.date, "yyyy-MM-dd'T'HH:mm:ss'Z'")
      format(parsedDate, "dd.MM.yyyy")
    except:
      day.date

  result = &"=== {dateStr} ({day.starts} - {day.ends}) ===\n"
  for i, lesson in day.lessons:
    result &= &"  {i+1}. {lesson}\n"

export httpclient, json, tables, strutils, strformat, times, options
