# Незавершенные задачи рефакторинга

**Дата обновления:** 2025-11-27  
**Статус:** Phase 7 (Final Testing & Verification) - PLANNED

---

## 📋 Phase 7: Final Testing & Verification (PLANNED)

### Основные цели
- Комплексное тестирование всего рефакторенного кода
- Проверка отсутствия регрессий
- Бенчмаркинг производительности
- Готовность к продакшену

### Оценка времени: 4-6 часов

---

## 🧪 Задачи тестирования

### 1. Unit Tests (Модульные тесты)

#### TTSService Tests
- [ ] `testShouldGenerateTTS_EmptyText_ReturnsFalse()`
- [ ] `testShouldGenerateTTS_SameText_ReturnsFalse()`
- [ ] `testShouldGenerateTTS_AlreadyPlaying_ReturnsFalse()`
- [ ] `testShouldGenerateTTS_ValidNewText_ReturnsTrue()`
- [ ] `testSynthesizeAndPlay_Success()`
- [ ] `testReplay_WithExistingAudio_Plays()`

#### AgentViewModel Tests
- [ ] `testStartRecording_SetsIsRecordingTrue()`
- [ ] `testExecuteCommand_EmptyCommand_DoesNothing()`
- [ ] `testResetState_ClearsAllFields()`
- [ ] `testGetCurrentState_Recording_ReturnsRecordingState()`

#### TerminalAgentViewModel Tests
- [ ] `testSaveState_PersistsToUserDefaults()`
- [ ] `testLoadState_RestoresFromUserDefaults()`
- [ ] `testClearState_RemovesPersistedData()`
- [ ] `testMultipleTerminals_IsolatedState()`

#### SessionStateManager Tests
- [ ] `testSetActiveSession_SetsActiveSessionId()`
- [ ] `testToggleViewMode_TogglesCorrectly()`
- [ ] `testSetViewMode_PersistsToUserDefaults()`
- [ ] `testGetViewMode_ReturnsCorrectMode()`
- [ ] `testSupportsAgentMode_ReturnsCorrectValue()`

**Примечание:** TerminalOutputProcessor тесты не нужны, так как класс был удален (сервер обрабатывает фильтрацию)

---

### 2. Integration Tests (Интеграционные тесты)

#### Recording Flow (Глобальный агент)
- [ ] Start recording → stop → transcribe → execute → TTS → playback
- [ ] Replay button works with cached audio
- [ ] State persists across app restarts
- [ ] Multiple commands in sequence work correctly

#### Terminal Agent Flow (Терминальный агент)
- [ ] Terminal 1: Record → execute → TTS → state saved
- [ ] Terminal 2: Record → execute → TTS → state saved
- [ ] Switch between terminals → states isolated
- [ ] Close terminal → state cleared
- [ ] Reopen terminal → state restored

#### View Mode Switching (Переключение режимов)
- [ ] PTY → Agent mode transition smooth
- [ ] Agent → PTY mode transition smooth
- [ ] Mode persists per terminal
- [ ] Mode indicator updates correctly
- [ ] SessionStateManager updates correctly

---

### 3. Functional Tests (Функциональные тесты)

#### Voice Recording
- [ ] Recording starts/stops correctly
- [ ] Audio file created
- [ ] Transcription triggered
- [ ] Screen stays on during recording (IdleTimerManager)

#### TTS Playback
- [ ] TTS generates correctly
- [ ] Audio plays without duplicates
- [ ] Replay button works
- [ ] Screen stays on during playback (IdleTimerManager)
- [ ] Background playback works (requires Info.plist configuration)

#### Navigation
- [ ] Tab switching preserves state
- [ ] Detail view navigation works
- [ ] Back button returns correctly
- [ ] State saved on navigation

#### Persistence
- [ ] Global agent state persists
- [ ] Terminal states persist (multiple terminals)
- [ ] Mode preferences persist (SessionStateManager)
- [ ] TTS audio cached correctly

---

### 4. Performance Tests (Тесты производительности)

**Метрики для проверки:**
- [ ] TTS latency < 2 seconds (95th percentile)
- [ ] Transcription latency < 2 seconds (95th percentile)
- [ ] View rendering smooth (60 fps)
- [ ] Memory usage stable (no leaks)
- [ ] WebSocket reconnection < 1 second

---

### 5. Regression Tests (Регрессионные тесты)

**Функции, которые должны работать без изменений:**
- [ ] QR code scanning works
- [ ] Terminal creation works
- [ ] PTY terminal works
- [ ] WebSocket streaming works
- [ ] Connection health monitoring works
- [ ] Settings persistence works

---

## 🔧 Build Verification (Проверка сборки)

### Compilation
- [x] ✅ BUILD SUCCEEDED (0 errors, 0 warnings) - **COMPLETED**

### Static Analysis
- [ ] SwiftLint passes (0 violations)
- [ ] Code coverage >70%

```bash
swiftlint lint --strict
# Expected: 0 violations

xcodebuild test -scheme EchoShell \
                -enableCodeCoverage YES
# Expected: >70% coverage
```

---

## 📱 Production Readiness Checklist

### Testing
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] No memory leaks detected (Instruments)
- [ ] No crashes in testing (TestFlight)

### Code Quality
- [x] Build succeeds with 0 warnings - **COMPLETED**
- [ ] SwiftLint passes
- [ ] Code coverage >70%

### Documentation
- [ ] Documentation updated
- [ ] CHANGELOG.md updated

---

## ⚠️ Дополнительные задачи (опционально)

### Phase 6: Background Audio Configuration

**Статус:** Частично выполнено

#### Что сделано:
- ✅ IdleTimerManager создан и интегрирован
- ✅ Lifecycle handling добавлен в EchoShellApp
- ✅ AudioPlayer имеет базовую конфигурацию audio session

#### Что осталось:
- [ ] Проверить/добавить `UIBackgroundModes` в Info.plist (через Xcode project settings)
  ```xml
  <key>UIBackgroundModes</key>
  <array>
      <string>audio</string>
  </array>
  ```
- [ ] Убедиться, что AudioPlayer правильно настраивает audio session для фонового воспроизведения
- [ ] Протестировать фоновое воспроизведение TTS

**Примечание:** AudioPlayer уже имеет конфигурацию `.playAndRecord`, но может потребоваться явная настройка для фонового режима.

---

## 📊 Прогресс рефакторинга

| Фаза | Статус | Прогресс |
|------|--------|----------|
| Phase 1: TTSService | ✅ COMPLETED | 100% |
| Phase 2: ViewModels | ✅ COMPLETED | 100% |
| Phase 3: Output Filtering | ✅ COMPLETED | 100% |
| Phase 4: Combine Events | ✅ COMPLETED | 100% |
| Phase 5: Single Source | ✅ COMPLETED | 100% |
| Phase 6: Lifecycle | ✅ COMPLETED | 95% (background audio config optional) |
| Phase 7: Testing | 📋 PLANNED | 0% |

**Общий прогресс:** 6 из 7 фаз завершено (86%)

---

## 🎯 Приоритеты

### Высокий приоритет
1. **Unit Tests** - Критично для поддержания качества кода
2. **Integration Tests** - Проверка основных сценариев использования
3. **Regression Tests** - Убедиться, что ничего не сломалось

### Средний приоритет
4. **Performance Tests** - Проверка метрик производительности
5. **Code Coverage** - Достижение >70% покрытия

### Низкий приоритет
6. **Background Audio Config** - Опционально, если фоновое воспроизведение не критично
7. **Documentation** - Обновление документации

---

## 📝 Заметки

- Все основные рефакторинги завершены
- Код компилируется без ошибок и предупреждений
- Архитектура улучшена и следует best practices
- Phase 7 фокусируется на тестировании и валидации
- Background audio configuration может быть добавлена позже, если потребуется

---

**Следующие шаги:**
1. Начать с Unit Tests для основных сервисов (TTSService, ViewModels, SessionStateManager)
2. Добавить Integration Tests для критических сценариев
3. Провести Performance Tests
4. Завершить Production Readiness Checklist
