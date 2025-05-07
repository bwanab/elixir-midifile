# Midifile

Midifile is an Elixir library for reading, writing, and manipulating standard MIDI files.

## Features

- Read and write MIDI files (format 0 and 1)
- Manipulate MIDI events (notes, controllers, etc.)
- Filter events by type or custom criteria
- Process notes with pitch shifting
- Map drum notes between different standards (via CSV mapping files)
- Preserve timing information when filtering events
- Convert MIDI tracks to musical sonorities (notes, chords, rests)
- Create MIDI tracks from musical sonorities
- Support for both metrical time and SMPTE time formats
- Modern note representation using the Note struct type

## Installation

Note that in the current incarnation in order to use this functionality, you'll need 
to clone into an adjacent folder the repository https://github.com/bwanab/music_prims as
it is referenced by mix.exs and is used throughout.

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

You can create a new sequence with specific settings:

```elixir
# Create a new sequence with custom settings
sequence = Midifile.Sequence.new(
  "My Sequence",  # Name
  120,            # BPM
  tracks,         # List of tracks
  960             # Ticks per quarter note (ppqn)
)

# Get or set sequence properties
name = Midifile.Sequence.name(sequence)
bpm = Midifile.Sequence.bpm(sequence)
sequence = Midifile.Sequence.set_bpm(sequence, 140)

# Get time division information
ppqn = Midifile.Sequence.ppqn(sequence)  # For metrical time sequences
```

Midifile now supports both metrical time (ticks per quarter note) and SMPTE time formats:

```elixir
# Create a sequence with metrical time (most common)
metrical_sequence = Midifile.Sequence.with_metrical_time(sequence, 960)

# Create a sequence with SMPTE time format (for sync with video/audio)
smpte_sequence = Midifile.Sequence.with_smpte_time(sequence, 30, 80)  # 30 fps, 80 ticks per frame

# Check time format
is_metrical = Midifile.Sequence.metrical_time?(sequence)
is_smpte = Midifile.Sequence.smpte_format?(sequence)

# Get SMPTE-specific information
fps = Midifile.Sequence.smpte_frames_per_second(smpte_sequence)
tpf = Midifile.Sequence.smpte_ticks_per_frame(smpte_sequence)
```

### Midifile.Track

A track contains an array of events. When you modify the events array, make sure to call `recalc_times/1` so each event gets its `time_from_start` recalculated.

You can create a track directly from sonorities:

```elixir
# Create a track from musical sonorities (notes, chords, rests)
track = Midifile.Track.new(
  "Piano Track",       # Track name
  sonorities,          # List of Note, Chord, and Rest objects
  960                  # Ticks per quarter note
)

# Get track properties
instrument = Midifile.Track.instrument(track)

# Quantize the track's events to a specific grid
quantized_track = Midifile.Track.quantize(track, 240)  # Quantize to 16th notes (at 960 ppqn)
```

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

### Midifile.MapEvents

The MapEvents module converts MIDI tracks to musical sonorities (Note, Chord, Rest):

```elixir
# Convert a track to a sequence of sonorities
sonorities = Midifile.MapEvents.track_to_sonorities(track, %{
  chord_tolerance: 10,  # Group notes within 10 ticks as chords
  ticks_per_quarter_note: sequence.ticks_per_quarter_note
})

# The returned sonorities can be notes, chords, or rests
Enum.each(sonorities, fn sonority ->
  case Sonority.type(sonority) do
    :note -> IO.puts("Note: #{Note.to_string(sonority)}, duration: #{Sonority.duration(sonority)}")
    :chord -> IO.puts("Chord: #{length(sonority.notes)} notes, duration: #{Sonority.duration(sonority)}")
    :rest -> IO.puts("Rest: duration: #{Sonority.duration(sonority)}")
  end
end)
```

### Midifile.Defaults

The Defaults module provides standard MIDI settings:

```elixir
# Default values
bpm = Midifile.Defaults.default_bpm()  # 120 BPM
ppqn = Midifile.Defaults.default_ppqn()  # 960 pulses per quarter note
time_sig = Midifile.Defaults.default_time_signature()  # [4, 4] (4/4 time)
```

### Note Representation

Notes are represented using the `Note` struct, which provides a modern and type-safe way to work with musical notes:

```elixir
# Create a new note
note = Note.new({:C, 4}, duration: 1, velocity: 100)

# Notes can be converted to strings in Guido Music Notation format
IO.puts(Note.to_string(note))  # Outputs: "C4*1/4"

# Notes can be converted to MIDI note numbers
midi_number = Note.note_to_midi(note)

# MIDI note numbers can be converted back to notes
note = Note.midi_to_note(60, 1, 100)  # Creates middle C (C4)
```

The `Note` struct provides several benefits:
- Type safety through `Note.t()` type specification
- Consistent note representation across the codebase
- Built-in support for duration and velocity
- Standardized string representation
- Easy conversion between MIDI note numbers and musical notes

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

### Converting MIDI to Sonorities and Back

This example shows how to convert MIDI data to musical sonorities and then back to MIDI:

```elixir
# Read a MIDI file
sequence = Midifile.read("input.mid")
track = Enum.at(sequence.tracks, 0)

# Convert track to sonorities
sonorities = Midifile.MapEvents.track_to_sonorities(track, %{
  chord_tolerance: 10,  # Group notes within 10 ticks as chords
  ticks_per_quarter_note: sequence.ticks_per_quarter_note
})

# Analyze the musical content
Enum.each(sonorities, fn sonority ->
  case Sonority.type(sonority) do
    :note -> 
      IO.puts("Note: #{Note.to_string(sonority)}, duration: #{Sonority.duration(sonority)}")
    :chord -> 
      note_names = Enum.map(sonority.notes, &Note.to_string(&1)) |> Enum.join(", ")
      IO.puts("Chord: [#{note_names}], duration: #{Sonority.duration(sonority)}")
    :rest -> 
      IO.puts("Rest: duration: #{Sonority.duration(sonority)}")
  end
end)

# Modify sonorities (e.g., add notes, change durations)
modified_sonorities = sonorities ++ [
  Note.new({:C, 5}, duration: 1.0, velocity: 100),
  Rest.new(0.5),
  Chord.new([
    Note.new({:C, 5}, velocity: 90),
    Note.new({:E, 5}, velocity: 90),
    Note.new({:G, 5}, velocity: 90)
  ], 1.0)
]

# Create a new track from the modified sonorities
new_track = Midifile.Track.new(
  "Modified Track", 
  modified_sonorities, 
  sequence.ticks_per_quarter_note
)

# Create a new sequence with the new track
new_sequence = Midifile.Sequence.new(
  "Modified Sequence",
  Midifile.Sequence.bpm(sequence),
  [new_track],
  sequence.ticks_per_quarter_note
)

# Write the new sequence to a MIDI file
Midifile.write(new_sequence, "output.mid")
```

## Resources

A description of the MIDI file format can be found at:
https://www.music.mcgill.ca/~ich/classes/mumt306/StandardMIDIfileformat.html

## License

Distributed under the Apache License v2.0.