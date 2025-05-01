defmodule Examples.MidiFromScratch do
  alias Midifile.Track
  alias Midifile.Sequence
  alias Midifile.Writer
  import MusicPrims

  # creates a C major scale where each note has a duration of 1 quarter note and writes it to a midifile.
  def midifile_from_scratch() do
    c_major = major_scale(:C, 4)
    write_midi_file(c_major, "c_major_scale")
  end

  def midifile_with_rest() do
    c_major = major_scale(:C, 4)
    {c_major, _td} = add_rest_at_keeping_total_duration(c_major, 0, 0.5)
    write_midi_file(c_major, "c_major_scale_with_rest")
  end

  def write_midi_file(notes, name) do
    track = Track.new(name, notes, 960)
    sfs = Sequence.new(name, 110, [track], 960)
    Writer.write(sfs, "test/#{name}.mid")

  end

  def add_rest_at_keeping_total_duration(ms, pos, duration) do
    note = Enum.at(ms, pos)

    {ms, _td} = change_dur_at(ms, pos, note.duration - duration)
    add_rest_at(ms, pos + 1, duration)
  end
  def add_rest_at(ms, pos, duration) do
    ms = List.insert_at(ms, pos, Note.rest(duration))
    total_dur = Enum.reduce(ms, 0,  &(&1.duration + &2))
    {ms, total_dur}
  end

  def change_dur_at(ms, pos, duration) do
    note = Enum.at(ms, pos)
    ms = List.replace_at(ms, pos, Note.new(note.note, duration: duration, velocity: note.velocity))
    total_dur = Enum.reduce(ms, 0,  &(&1.duration + &2))
    {ms, total_dur}
  end
end
