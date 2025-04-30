defmodule Examples.MidiFromScratch do
  alias Midifile.Track
  alias Midifile.Sequence
  alias Midifile.Writer
  import MusicPrims

  def midifile_from_scratch() do
    track = Track.new("C Major Scale", major_scale(:C, 4), 960)
    sfs = Sequence.new("C Major Scale midi", 110, [track], 960)
    Writer.write(sfs, "test/midifile_from_scratch.mid")
  end

end
