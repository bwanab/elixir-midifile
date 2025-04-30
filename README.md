# Midifile

Midifile is an Elixir library for reading, writing, and manipulating standard MIDI files.

## Features

- Read and write MIDI files (format 0 and 1)
- Manipulate MIDI events (notes, controllers, etc.)
- Filter events by type or custom criteria
- Process notes with pitch shifting
- Map drum notes between different standards (via CSV mapping files)
- Preserve timing information when filtering events

## Installation

Add `midifile` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:midifile, "~> 0.1.0"}
  ]
end
```

## Testing

```bash
mix test
```

## Overview

### Midifile

The main API provides functions for reading and writing MIDI files:

```elixir
# Read a MIDI file
sequence = Midifile.read("input.mid")

# Write a MIDI file
Midifile.write(sequence, "output.mid")
```

### Midifile.Sequence

A sequence contains a list of tracks and global information like the sequence's format and time division.

The first track in a sequence is special; it holds meta-events like tempo and sequence name. It is stored as a sequence's `conductor_track`.

### Midifile.Track

A track contains an array of events. When you modify the events array, make sure to call `recalc_times/1` so each event gets its `time_from_start` recalculated.

### Midifile.Event

Each event holds both its delta time and its time from the start of the track. Events represent various MIDI messages such as note on and off, controller values, and meta events.

### Midifile.Filter

The Filter module provides functions for filtering and processing MIDI events:

```elixir
# Remove all controller events from track 0
filtered_sequence = Midifile.Filter.remove_events(
  sequence, 
  0, 
  &Midifile.Event.controller?/1
)

# Process notes on track 0 matching a predicate
processed_sequence = Midifile.Filter.process_notes(
  sequence,
  0,
  fn note -> note.note == {:c, 4} end,  # Only process C4 notes
  {:pitch, 12}  # Shift up one octave
)

# Filter out short notes (less than 0.25 duration)
filtered_sequence = Midifile.Filter.process_notes(
  sequence,
  0,
  fn note -> note.duration < 0.25 end,  # Match notes with short duration
  :remove  # Remove these notes
)
```

### Midifile.Util

The Util module provides utility functions for transforming MIDI files:

```elixir
# Map drum notes according to a CSV mapping file
Midifile.Util.map_drums(
  "mapping.csv",
  "input.mid",
  "output.mid"
)
```

The CSV mapping file should have a header row and 3 columns: Item, From, To.

## How To Use

### Reading a MIDI File

```elixir
# Read a MIDI file
sequence = Midifile.read("my_midi_file.mid")
```

### Writing a MIDI File

```elixir
# Write a sequence to a MIDI file
Midifile.write(sequence, "my_output_file.mid")
```

### Editing a MIDI File

Here's an example that reads a MIDI file, transposes notes on a specific channel, and writes the result to a new file:

```elixir
# Read the MIDI file
sequence = Midifile.read("input.mid")

# Process all notes on channel 4 (channels are zero-based)
processed_sequence = Midifile.Filter.process_notes(
  sequence,
  0,  # Process track 0
  fn note, event -> event.channel == 4 end,  # Only affect channel 4
  {:pitch, -12}  # Transpose down one octave
)

# Write the modified sequence to a new file
Midifile.write(processed_sequence, "output.mid")
```

## Resources

A description of the MIDI file format can be found at:
https://www.music.mcgill.ca/~ich/classes/mumt306/StandardMIDIfileformat.html

## License

Distributed under the Apache License v2.0.