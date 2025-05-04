defmodule Midifile do
  @moduledoc """
  Main interface for reading, writing, and manipulating MIDI files.
  
  This module provides the primary API for working with MIDI files in Elixir.
  It offers functions for reading MIDI files into Elixir data structures and
  writing those structures back to standard MIDI files.
  
  ## Key Features
  
  * Read and write MIDI files (format 0 and 1)
  * Manipulate MIDI events (notes, controllers, etc.)
  * Filter events by type or custom criteria
  * Process notes with pitch shifting
  * Map drum notes between different standards
  * Convert MIDI tracks to musical sonorities (notes, chords, rests)
  * Create MIDI tracks from musical sonorities
  * Support for both metrical time and SMPTE time formats
  
  ## Example
  
      # Read a MIDI file
      sequence = Midifile.read("input.mid")
      
      # Process the sequence
      processed = Midifile.Filter.process_notes(sequence, 0, fn note -> true end, {:pitch, 12})
      
      # Write the modified sequence to a new file
      Midifile.write(processed, "output.mid")
  """

  @doc """
  Reads a MIDI file from the specified path.
  
  Parses a standard MIDI file and converts it into a `Midifile.Sequence` struct
  that can be manipulated using the library's functions.
  
  ## Parameters
  
    * `path` - String path to the MIDI file to read
  
  ## Returns
  
    * `%Midifile.Sequence{}` - A sequence struct containing all the MIDI file data
  
  ## Examples
  
      iex> sequence = Midifile.read("my_song.mid")
      iex> sequence.format
      1
      iex> length(sequence.tracks)
      4
  
  ## Errors
  
  Will raise an error if the file cannot be read or is not a valid MIDI file.
  """
  def read(path) do
    Midifile.Reader.read(path)
  end

  @doc """
  Writes a MIDI sequence to a file at the specified path.
  
  Converts a `Midifile.Sequence` struct into a standard MIDI file
  and writes it to the given path.
  
  ## Parameters
  
    * `sequence` - The `%Midifile.Sequence{}` struct to write
    * `path` - String path where the MIDI file should be written
  
  ## Returns
  
    * `:ok` - If the write operation was successful
  
  ## Examples
  
      iex> sequence = Midifile.read("original.mid")
      iex> Midifile.write(sequence, "copy.mid")
      :ok
  
  ## Errors
  
  Will raise an error if the file cannot be written or if the sequence is invalid.
  """
  def write(sequence, path) do
    Midifile.Writer.write(sequence, path)
  end
end
