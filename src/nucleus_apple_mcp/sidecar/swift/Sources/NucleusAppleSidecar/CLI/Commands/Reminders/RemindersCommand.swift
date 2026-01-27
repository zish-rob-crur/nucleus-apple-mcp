import ArgumentParser

struct RemindersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Reminders (EventKit) operations.",
        subcommands: [
            RemindersSources.self,
            RemindersLists.self,
            RemindersReminders.self,
            RemindersCreateReminder.self,
            RemindersUpdateReminder.self,
            RemindersDeleteReminder.self
        ]
    )
}
