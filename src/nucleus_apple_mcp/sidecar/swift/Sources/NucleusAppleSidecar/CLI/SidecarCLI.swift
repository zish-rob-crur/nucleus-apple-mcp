import ArgumentParser

struct SidecarCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nucleus-apple-sidecar",
        abstract: "Nucleus Swift sidecar worker (JSON-in/JSON-out).",
        subcommands: [Ping.self, Echo.self, CalendarCommand.self, RemindersCommand.self],
        defaultSubcommand: Ping.self
    )
}
