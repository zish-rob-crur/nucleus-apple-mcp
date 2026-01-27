set quiet := true

sidecar_dir := "src/nucleus_apple_mcp/sidecar/swift"
sidecar_product := "nucleus-apple-sidecar"

default:
  @just --list

# --- Swift sidecar (SwiftPM) ---

# Build the Swift sidecar (profile: debug|release)
sidecar-build profile="debug":
  cd {{sidecar_dir}} && swift build -c {{profile}}

# Run the sidecar CLI (ArgumentParser) in debug mode.
# NOTE: `args` is a single string so you can include quotes safely:
#   just sidecar
#   just sidecar --help
#   just sidecar "echo --payload '{\"x\":2}'"
sidecar args="ping":
  cd {{sidecar_dir}} && sh -lc {{quote("swift run -c debug " + sidecar_product + " " + args)}}

# Same as `sidecar`, but uses release configuration.
sidecar-release args="ping":
  cd {{sidecar_dir}} && sh -lc {{quote("swift run -c release " + sidecar_product + " " + args)}}

# Run the sidecar CLI (ArgumentParser) in debug mode with pass-through args.
# NOTE: When passing raw JSON as an argument, prefer `just sidecar "..."` or escape quotes like `{\"x\":2}`.
sidecar-args *args:
  cd {{sidecar_dir}} && swift run -c debug {{sidecar_product}} {{args}}

# Same as `sidecar-args`, but uses release configuration.
sidecar-args-release *args:
  cd {{sidecar_dir}} && swift run -c release {{sidecar_product}} {{args}}

# Open an interactive shell in the Swift sidecar directory.
sidecar-shell:
  cd {{sidecar_dir}} && exec ${SHELL:-zsh}

# Convenience: ping (debug)
sidecar-run:
  cd {{sidecar_dir}} && swift run -c debug {{sidecar_product}} ping

# Convenience: ping (release)
sidecar-run-release:
  cd {{sidecar_dir}} && swift run -c release {{sidecar_product}} ping

# Convenience: echo (debug)
sidecar-echo payload_json="null":
  cd {{sidecar_dir}} && swift run -c debug {{sidecar_product}} echo --payload {{quote(payload_json)}}

# Convenience: echo (release)
sidecar-echo-release payload_json="null":
  cd {{sidecar_dir}} && swift run -c release {{sidecar_product}} echo --payload {{quote(payload_json)}}

# Convenience: help (debug)
sidecar-help:
  cd {{sidecar_dir}} && swift run -c debug {{sidecar_product}} --help

# Path to the built binary (requires `just sidecar-build` first)
sidecar-bin profile="debug":
  @echo {{sidecar_dir}}/.build/{{profile}}/{{sidecar_product}}

# Watch Swift sources and rerun a command on change (requires `watchexec`).
# Examples:
#   just sidecar-watch
#   just sidecar-watch "echo --payload '{\"x\":2}'"
sidecar-watch args="ping" profile="debug":
  @command -v watchexec >/dev/null 2>&1 || (echo "watchexec not found. Install it first (e.g. brew install watchexec)." && exit 1)
  cd {{sidecar_dir}} && watchexec -w Sources -r -- {{quote("swift run -c " + profile + " " + sidecar_product + " " + args)}}
