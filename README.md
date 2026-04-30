# Drift

A Flutter app that sends you a short bedtime prompt each evening to help you reflect on your night-time habits. No screen time tracking, no blocking — just a gentle nudge to wind down.

## Features

- **Nightly prompts** — story, wind-down, or guided visualisation, tailored to your goals
- **Scheduled notifications** — set your own check-in time with a backup reminder if you miss it
- **Journal** — write freely or link entries to a specific prompt
- **Library** — every prompt you complete gets saved so you can revisit it
- **Pause** — take a break for a night, a few days, or the weekend

## Project structure

### `models/`
- **prompt.dart** — the `Prompt` data class used when reading and writing prompts to storage. Handles JSON serialisation and deserialisation.

### `screens/`
- **app_shell.dart** — holds the bottom navigation bar and switches between the four main screens. Also owns the text size state so it persists across tab switches.
- **journal_screen.dart** — shows the user's journal entries in a scrollable list, sorted newest first. Also contains the editor screen used for writing new entries or editing existing ones. Entries can be linked to a specific prompt.
- **library_screen.dart** — displays every prompt the user has completed, filterable by type (Story, Wind-down, Visualisation). Tapping a prompt opens a detail screen that shows the full text and any journal entry the user wrote for it.
- **onboarding_screen.dart** — the four-page first-launch flow. Walks the user through picking their goals, setting a notification time, and reviewing their choices before entering the app.
- **settings_screen.dart** — lets the user change their prompt time, pause prompts for a set period, update their goals, and adjust the app-wide text size.
- **tonight_screen.dart** — the main screen of the app. Moves through three states: waiting (before the prompt time), active (prompt is showing, with audio controls and snooze options), and done (after the user marks themselves finished for the night).

### `services/`
- **notification_service.dart** — handles all interaction with the OS notification system. Schedules the daily repeating prompt, a one-shot backup reminder, post-pause notifications, and snooze reminders. Also cancels notifications when the user marks themselves done.
- **prompt_service.dart** — loads and parses the full prompt list from `assets/prompts.json` at runtime.
- **time_rules.dart** — contains shared logic for working out when "tonight" resets (6am) and clamping snooze durations so reminders never fire in the early hours of the morning.

### `storage/`
- **app_prefs.dart** — Wraps SharedPreferences with typed getters and setters for the prompt time, pause schedule, done-for-tonight flag, goals, text size, and various per-night guards.
- **journal_store.dart** — stores the user's journal entries as a JSON string in SharedPreferences. Handles saving, editing, deleting, and fetching entries by prompt ID.
- **prompt_history_store.dart** — keeps a running list of every prompt the user has completed, used to populate the Library screen.
- **prompt_store.dart** — general prompt storage helpers shared across the app.
- **tonight_prompt_store.dart** — saves the prompt chosen for tonight so it stays consistent if the user closes and reopens the app before midnight.

### Root
- **constants.dart** — app-wide constants including the night reset hour (6am), backup reminder offset, and maximum snooze duration.
- **main.dart** — app entry point. Initialises notifications, checks whether onboarding has been completed, loads the saved text size, and builds the root `MaterialApp` with the full dark theme.
