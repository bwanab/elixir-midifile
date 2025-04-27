defmodule Midifile.Util do
  @moduledoc """
  Utility functions for transforming MIDI files.
  """

  @doc """
  Identifies instruments used in a MIDI file based on a sound mapping.
  
  ## Parameters
    * `map_file_path` - Path to the CSV file with sound mappings (Key#,Note,Sound Name)
    * `midi_file_path` - Path to the MIDI file to analyze
    
  ## Returns
    * A list of tuples in the format {key_number, note, sound_name} sorted by key_number
  """
  def identify_instruments(map_file_path, midi_file_path) do
    # Read the MIDI file
    sequence = Midifile.read(midi_file_path)
    
    # Collect all unique note numbers from the sequence
    unique_notes = 
      sequence.tracks
      |> Enum.flat_map(fn track -> 
        track.events
        |> Enum.filter(&Midifile.Event.note?/1)
        |> Enum.map(&Midifile.Event.note/1)
      end)
      |> Enum.uniq()
      |> Enum.sort()
    
    # Read the mapping file
    mappings = read_instrument_mappings(map_file_path)
    
    # Match notes to mappings and return results
    unique_notes
    |> Enum.map(fn note ->
      Enum.find(mappings, {note, "Note #{note}", "Unknown"}, fn {key_number, _, _} -> 
        key_number == note
      end)
    end)
    |> Enum.sort_by(fn {key_number, _, _} -> key_number end)
  end
  
  @doc """
  Reads and parses a CSV file containing instrument sound mappings.
  
  ## Parameters
    * `map_file_path` - Path to the CSV file with instrument mappings
    
  ## Returns
    * A list of tuples in the format {key_number, note, sound_name}
  """
  def read_instrument_mappings(map_file_path) do
    map_file_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.drop(1)  # Skip the header row
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      [key_str, note, sound_name] = 
        line
        |> String.split(",")
        |> Enum.map(&String.trim/1)
      
      {
        String.to_integer(key_str),
        note,
        sound_name
      }
    end)
  end

  @doc """
  Maps drum notes to different values based on a CSV mapping file.
  
  The CSV file should have a header row and 3 columns: Item, From, To.
  - Item: Description of what is being mapped (e.g., "Snare")
  - From: MIDI note value to map from (e.g., 40)
  - To: MIDI note value to map to (e.g., 38)
  
  ## Parameters
    * `map_file_path` - Path to the CSV file with drum mappings
    * `input_path` - Path to the input MIDI file
    * `output_path` - (Optional) Path to the output MIDI file. If not provided,
      defaults to the input filename with "_trans" appended before the extension.
      
  ## Returns
    * The path to the output file
  """
  def map_drums(map_file_path, input_path, output_path \\ nil) do
    # Set default output path if none provided
    output_file =
      if output_path do
        output_path
      else
        # Extract base name without extension and add "_trans" suffix
        base = Path.basename(input_path, ".mid")
        dir = Path.dirname(input_path)
        Path.join(dir, "#{base}_trans.mid")
      end

    # Read the input MIDI file - our Reader now handles format 0 files
    sequence = Midifile.read(input_path)
    
    # Read and parse the mapping CSV file
    mappings = read_mappings(map_file_path)
    
    # Process all tracks in the sequence
    updated_tracks =
      Enum.map(0..(length(sequence.tracks) - 1), fn track_idx ->
        # Apply each mapping in the CSV file to the track
        processed_sequence =
          Enum.reduce(mappings, sequence, fn {_item, from_note, to_note}, seq ->
            map_drum_note(seq, track_idx, from_note, to_note)
          end)

        # Get the processed track
        Enum.at(processed_sequence.tracks, track_idx)
      end)

    # Create a new sequence with all processed tracks
    updated_sequence = %{sequence | tracks: updated_tracks}

    # Write the processed sequence to the output file
    Midifile.write(updated_sequence, output_file)

    # Return the output file path
    output_file
  end
  
  @doc """
  Reads and parses a CSV file containing drum mappings.
  
  ## Parameters
    * `map_file_path` - Path to the CSV file with drum mappings
    
  ## Returns
    * A list of tuples in the format {item, from_note, to_note}
  """
  def read_mappings(map_file_path) do
    map_file_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.drop(1)  # Skip the header row
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      [item, from_str, to_str] = 
        line
        |> String.split(",")
        |> Enum.map(&String.trim/1)
      
      {
        item,
        String.to_integer(from_str),
        String.to_integer(to_str)
      }
    end)
  end
  
  @doc """
  Maps a specific drum note to a new value in a specific track.
  
  ## Parameters
    * `sequence` - A `Midifile.Sequence` struct
    * `track_number` - Zero-based index of the track to process
    * `from_note` - The note number to change from
    * `to_note` - The note number to change to
    
  ## Returns
    * A new sequence with the processed track
  """
  def map_drum_note(sequence, track_number, from_note, to_note) do
    Midifile.Filter.process_notes(
      sequence,
      track_number,
      fn note -> note == from_note end,
      {:pitch, to_note - from_note}
    )
  end
end