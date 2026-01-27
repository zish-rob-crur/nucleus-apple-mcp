import ArgumentParser

struct CalendarCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendar",
        abstract: "Calendar (EventKit) operations.",
        subcommands: [
            CalendarSources.self,
            CalendarCalendars.self,
            CalendarEvents.self,
            CalendarCreateEvent.self,
            CalendarUpdateEvent.self,
            CalendarDeleteEvent.self
        ]
    )
}
