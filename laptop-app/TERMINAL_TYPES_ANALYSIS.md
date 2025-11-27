# Анализ различий в обработке терминалов

> **Note**: This is a historical document describing the state before terminal type unification. As of the refactoring, terminal types have been simplified:
> - `cursor_agent` was removed (unified with `cursor`)
> - `cursor_cli` was renamed to `cursor`
> - `claude_cli` was renamed to `claude`
> - All terminals now use unified PTY creation and output handling logic

## Типы терминалов (Historical)

1. **`regular`** - обычный терминал (интерактивный shell)
2. **`cursor_agent`** - терминал с запущенным cursor-agent (интерактивный режим) [REMOVED]
3. **`cursor_cli`** - headless терминал (cursor-agent через CLI, JSON output) [RENAMED to `cursor`]
4. **`claude_cli`** - headless терминал (claude через CLI, JSON output) [RENAMED to `claude`]

## Классификация

- **Regular терминалы**: `regular`, `cursor_agent` - интерактивные, прямой ввод/вывод
- **Headless терминалы**: `cursor_cli`, `claude_cli` - через CLI, JSON output, требуют парсинга

## Различия в создании терминала

### Regular терминалы (`regular`, `cursor_agent`)
- Создается PTY с интерактивным shell
- Вывод обрабатывается напрямую через `pty.onData`
- Для `cursor_agent` автоматически запускается `cursor-agent` через 500ms после создания

### Headless терминалы (`cursor_cli`, `claude_cli`)
- Создается PTY с интерактивным shell (ТАК ЖЕ как regular)
- НО: добавляется `headless` объект в сессию с флагами:
  - `isRunning` - блокировка параллельных команд
  - `cliSessionId` - сохранение контекста между командами
  - `completionTimeout` - таймаут для определения завершения команды

## Различия в обработке ввода (команд)

### Regular терминалы
```typescript
executeCommand(sessionId, command) {
  // Просто пишет команду в PTY через writeInput
  this.writeInput(sessionId, command, true);
  // Возвращает пустую строку (вывод идет через WebSocket)
}
```

### Headless терминалы
```typescript
executeCommand(sessionId, command) {
  // Вызывает executeHeadlessCommand
  return this.executeHeadlessCommand(session, command);
}

executeHeadlessCommand(session, command) {
  // 1. Проверяет isRunning (блокирует параллельные команды)
  // 2. Строит команду с флагами:
  //    - cursor_cli: cursor-agent --output-format stream-json --print --resume <session_id> "prompt"
  //    - claude_cli: claude --output-format json-stream --session-id <session_id> "prompt"
  // 3. Пишет команду в PTY
  // 4. Устанавливает таймаут 60 секунд
  // 5. Возвращает "Headless command started"
}
```

**Ключевые различия:**
- Headless: команда оборачивается в CLI вызов с флагами
- Headless: используется `--resume` или `--session-id` для сохранения контекста
- Headless: есть блокировка параллельных команд (`isRunning`)
- Headless: есть таймаут для определения завершения

## Различия в обработке вывода

### Regular терминалы
```typescript
pty.onData((data) => {
  // 1. Сохраняет в outputBuffer
  // 2. Отправляет в globalOutputListeners (RecordingStreamManager)
  // 3. Отправляет напрямую в terminal_display через OutputRouter
  // 4. Отправляет в WebSocket listeners
})
```

### Headless терминалы
```typescript
pty.onData((data) => {
  // 1. Сохраняет в outputBuffer
  // 2. Отправляет в globalOutputListeners (RecordingStreamManager)
  // 3. НЕ отправляет напрямую в terminal_display
  //    (RecordingStreamManager обработает и отправит отфильтрованный вывод)
})
```

### RecordingStreamManager обработка

#### Для regular/cursor_agent:
```typescript
handleTerminalOutput(sessionId, terminalType, data) {
  if (terminalType === 'cursor_agent') {
    // Использует TerminalScreenEmulator для парсинга ANSI
    // Использует TerminalOutputProcessor для извлечения новых строк
    // Использует RecordingOutputProcessor для обработки текста
    // Отправляет в recording_stream
  }
}
```

#### Для headless (cursor_cli/claude_cli):
```typescript
handleHeadlessOutput(sessionId, data, terminalType) {
  // 1. Использует HeadlessOutputProcessor для парсинга JSON
  // 2. Извлекает assistant messages (type: "assistant")
  // 3. Извлекает session_id из JSON
  // 4. Определяет completion через result messages
  // 5. Отправляет отфильтрованный вывод в terminal_display
  // 6. Отправляет assistant messages в recording_stream
  // 7. Обновляет cliSessionId в TerminalManager
}
```

## Итоговая таблица различий

| Аспект | Regular | Headless (cursor_cli/claude_cli) |
|--------|---------|----------------------------------|
| **Создание PTY** | ✅ Интерактивный shell | ✅ Интерактивный shell (ТАК ЖЕ) |
| **Структура сессии** | Нет `headless` объекта | Есть `headless` объект с флагами |
| **Выполнение команды** | Прямая запись в PTY | Обертка в CLI вызов с флагами |
| **Сохранение контекста** | Нет | Да (через `--resume`/`--session-id`) |
| **Блокировка команд** | Нет | Да (`isRunning` флаг) |
| **Таймаут завершения** | Нет | Да (60 секунд) |
| **Обработка вывода** | Прямая отправка в terminal_display | Парсинг JSON → фильтрация → отправка |
| **Формат вывода** | ANSI/текст | JSON stream |
| **Извлечение текста** | TerminalScreenEmulator | HeadlessOutputProcessor |
| **Отправка в TTS** | RecordingOutputProcessor | HeadlessOutputProcessor (только assistant) |

## Проблемы и рекомендации

### Потенциальные проблемы:

1. **Дублирование логики создания PTY**
   - Код создания PTY для regular и headless терминалов почти идентичен
   - Можно вынести в отдельный метод

2. **Разная обработка вывода в pty.onData**
   - Для regular: отправка напрямую в terminal_display
   - Для headless: только в globalOutputListeners
   - Это правильно, но может быть неочевидно

3. **Разная обработка в RecordingStreamManager**
   - Для cursor_agent: сложная обработка через эмулятор экрана
   - Для headless: парсинг JSON
   - Это правильно, но логика разбросана

### Рекомендации:

1. Вынести создание PTY в отдельный метод `createPTY()`
2. Добавить комментарии, объясняющие различия
3. Рассмотреть унификацию обработки вывода (если возможно)
