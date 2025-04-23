# elixir-midifile reference

## Commands
```bash
mix compile                    # Compile the project
mix test                       # Run all tests
mix test test/event_test.exs   # Run a specific test file
mix test test/event_test.exs:45  # Run a specific test at line 45
mix format                     # Format code with Elixir's built-in formatter
```

## Git Configuration
Always push changes to the bwanab fork, NOT to the original repo:
```bash
git push fork <branch-name>    # Correct: Push to bwanab's fork
```

## Code Style
- Modules: `PascalCase` (e.g., `Midifile.Sequence`)
- Functions/Variables: `snake_case` (e.g., `read_track`, `delta_time`) 
- Module constants: `@snake_case` (e.g., `@status_meta_event`)
- Use pattern matching for control flow
- Prefer small, focused functions with clear responsibility
- Use pipeline operator `|>` for data transformations
- No explicit `try/catch/rescue` - pattern matching preferred

## Structure
- `Midifile` - Main API for reading/writing MIDI files
- `Midifile.Sequence` - MIDI sequence with tracks
- `Midifile.Track` - MIDI track with events
- `Midifile.Event` - MIDI event representation
- `Midifile.Reader`/`Writer` - File I/O logic
- `Midifile.Varlen` - Variable-length value handling