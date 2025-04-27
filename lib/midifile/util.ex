defmodule Midifile.Util do
  @moduledoc """
  Utility functions for transforming MIDI files.
  """

  @doc """
  Maps drum notes to different values.
  
  Currently maps:
  - Snare (40) -> 38
  - Bass drum (35) -> 36
  
  ## Parameters
    * `input_path` - Path to the input MIDI file
    * `output_path` - (Optional) Path to the output MIDI file. If not provided,
      defaults to the input filename with "_trans" appended before the extension.
      
  ## Returns
    * The path to the output file
  """
  def map_drums(input_path, output_path \\ nil) do
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
    
    # Process all tracks in the sequence
    updated_tracks =
      Enum.map(0..(length(sequence.tracks) - 1), fn track_idx ->
        # Process each track with note transformations
        processed_sequence =
          sequence
          |> map_drum_note(track_idx, 40, 38) # Snare 40 -> 38
          |> map_drum_note(track_idx, 35, 36) # Bass drum 35 -> 36

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