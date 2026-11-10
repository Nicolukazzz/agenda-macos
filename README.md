# Agenda

A native macOS planner for university life: an Outlook-style calendar, quick-add tasks per course, and Markdown notes that live in your own class folders. Built with SwiftUI, SwiftData and Liquid Glass.

Agenda is **fully offline**: no accounts, no sync, no network code. Everything stays on your Mac.

## Features

- **Calendar** — month view for deadlines and your own events; week view with your class timetable. Drag to create, move and resize; repeating classes with "only this event / all events" edits and semester breaks.
- **Tasks** — one-line quick add in English or Spanish: `Lab report #os friday 6pm !` or `Taller #so el otro miércoles`. Grouped into Overdue, Today, Tomorrow, This Week and Later; subtasks, priorities, and work blocks reserved in the calendar.
- **Today** — today's classes, your own schedule, and what's due.
- **Courses from folders** — reads `<classes root>/<YYYY-N>/<Course>/`. Each course gets a `#tag`, a color, a schedule, tasks, notes and a file browser.
- **Notes** — Markdown files in `<Course>/Notas/`, with an edit / split / preview editor, autosave, live reload when another app edits a file, and conflict handling. Files outside `Notas/` open read-only.
- **Files** — the course folder with Finder icons and Quick Look. Never moves, renames or deletes anything.
- **Money** — log what you spend or earn in one line: `Peluquería 25k #belleza`, `Claude 20 usd ayer`, `+2m sueldo`. Pesos and dollars (each entry keeps the rate of its day), totals and balance per month, where it went by category, day by day, and the pace against last month. Subscriptions and salaries log themselves on their day.
- **Widgets** — desktop widgets with the month's spending and one-click buttons for what you log most.
- **Backups** — a daily JSON backup (last 14 kept), export/import, and guided restore if the database can't be opened.

## Requirements

- macOS 26 or later
- Xcode 26 or later to build

## Build

```sh
cd AgendaCore && swift test     # logic tests
cd .. && scripts/install-local.sh   # Release build, installs /Applications/Agenda.app
```

The app is ad-hoc signed for personal use. To distribute it, set your own team and bundle identifier.

## Project layout

```
AgendaCore/           Pure logic + tests (parser, recurrence, layout, naming, backups)
Planificador/
  App/                App entry, state, menu commands
  Model/              SwiftData models
  Services/           Folder access, notes, file watching, backups, schedule import
  Views/Design/       Design tokens + component library (+ Gallery preview)
  Views/…             Screens, composed only from design components
scripts/              Install and icon scripts
```

## Libraries

One per job, all MIT, pinned in `Package.resolved`:

- [MijickCalendarView](https://github.com/Mijick/CalendarView) — the date picker calendar.
- [Pow](https://github.com/EmergeTools/Pow) — rewards and change effects (sparkles on completing, shine on new totals).
- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) — note previews.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — the global "log expense" hotkey.

## License

[MIT](LICENSE)
