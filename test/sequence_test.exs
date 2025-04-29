defmodule SequenceTest do
  use ExUnit.Case
  alias Midifile.Sequence
  alias Midifile.Track
  alias Midifile.Event

  setup do
    e = %Event{symbol: :on, delta_time: 100, bytes: [0x92, 64, 127]}
    t = %Track{events: [e, e, e]}

    ct = %Track{
      events: [
        %Event{symbol: :seq_name, bytes: "Unnamed"},
        %Event{symbol: :tempo, bytes: [trunc(60_000_000 / 82)]}
      ]
    }

    {:ok, %{seq: %Sequence{division: 480, conductor_track: ct, tracks: [t, t, t]}, track: t}}
  end

  test "name", context do
    assert Sequence.name(context[:seq]) == "Unnamed"
  end

  test "bpm", context do
    assert Sequence.bpm(context[:seq]) == 82
  end

  test "ppqn with metrical format", context do
    assert Sequence.ppqn(context[:seq]) == 480
  end

  test "metrical_time? with metrical format", context do
    assert Sequence.metrical_time?(context[:seq]) == true
  end

  test "smpte_format? with metrical format", context do
    assert Sequence.smpte_format?(context[:seq]) == false
  end

  test "metrical_time? with SMPTE format" do
    # Create a sequence with SMPTE division (25 fps, 40 ticks per frame)
    smpte_division = Sequence.create_smpte_division(25, 40)
    division_int = :binary.decode_unsigned(smpte_division)
    seq = %Sequence{division: division_int}
    
    assert Sequence.metrical_time?(seq) == false
  end

  test "smpte_format? with SMPTE format" do
    # Create a sequence with SMPTE division (25 fps, 40 ticks per frame)
    smpte_division = Sequence.create_smpte_division(25, 40)
    division_int = :binary.decode_unsigned(smpte_division)
    seq = %Sequence{division: division_int}
    
    assert Sequence.smpte_format?(seq) == true
  end

  test "ppqn with SMPTE format" do
    # Create a sequence with SMPTE division (25 fps, 40 ticks per frame)
    smpte_division = Sequence.create_smpte_division(25, 40)
    division_int = :binary.decode_unsigned(smpte_division)
    seq = %Sequence{division: division_int}
    
    assert Sequence.ppqn(seq) == nil
  end

  test "smpte_frames_per_second" do
    # Test all valid SMPTE frames per second values
    # Use our division creation function to ensure consistency
    smpte_24 = Sequence.create_smpte_division(24, 4)  # 24 fps, 4 ticks/frame
    smpte_25 = Sequence.create_smpte_division(25, 4)  # 25 fps, 4 ticks/frame
    smpte_29 = Sequence.create_smpte_division(29, 4)  # 29.97 fps, 4 ticks/frame
    smpte_30 = Sequence.create_smpte_division(30, 4)  # 30 fps, 4 ticks/frame
    
    # Convert each binary to integer for use in struct
    smpte_24_int = :binary.decode_unsigned(smpte_24)
    smpte_25_int = :binary.decode_unsigned(smpte_25)
    smpte_29_int = :binary.decode_unsigned(smpte_29)
    smpte_30_int = :binary.decode_unsigned(smpte_30)
    
    assert Sequence.smpte_frames_per_second(%Sequence{division: smpte_24_int}) == 24
    assert Sequence.smpte_frames_per_second(%Sequence{division: smpte_25_int}) == 25
    assert Sequence.smpte_frames_per_second(%Sequence{division: smpte_29_int}) == 29
    assert Sequence.smpte_frames_per_second(%Sequence{division: smpte_30_int}) == 30
    
    # Should return nil for metrical time format
    assert Sequence.smpte_frames_per_second(%Sequence{division: 480}) == nil
  end

  test "smpte_ticks_per_frame" do
    # Test various ticks per frame values
    # Use our division creation function to ensure consistency
    smpte_4 = Sequence.create_smpte_division(25, 4)     # 25 fps, 4 ticks/frame
    smpte_8 = Sequence.create_smpte_division(25, 8)     # 25 fps, 8 ticks/frame
    smpte_10 = Sequence.create_smpte_division(25, 10)   # 25 fps, 10 ticks/frame
    smpte_80 = Sequence.create_smpte_division(25, 80)   # 25 fps, 80 ticks/frame
    smpte_100 = Sequence.create_smpte_division(25, 100) # 25 fps, 100 ticks/frame
    
    # Convert each binary to integer for use in struct
    smpte_4_int = :binary.decode_unsigned(smpte_4)
    smpte_8_int = :binary.decode_unsigned(smpte_8)
    smpte_10_int = :binary.decode_unsigned(smpte_10)
    smpte_80_int = :binary.decode_unsigned(smpte_80)
    smpte_100_int = :binary.decode_unsigned(smpte_100)
    
    assert Sequence.smpte_ticks_per_frame(%Sequence{division: smpte_4_int}) == 4
    assert Sequence.smpte_ticks_per_frame(%Sequence{division: smpte_8_int}) == 8
    assert Sequence.smpte_ticks_per_frame(%Sequence{division: smpte_10_int}) == 10
    assert Sequence.smpte_ticks_per_frame(%Sequence{division: smpte_80_int}) == 80
    assert Sequence.smpte_ticks_per_frame(%Sequence{division: smpte_100_int}) == 100
    
    # Should return nil for metrical time format
    assert Sequence.smpte_ticks_per_frame(%Sequence{division: 480}) == nil
  end

  test "create_metrical_division" do
    # Test creating metrical division values
    assert Sequence.create_metrical_division(480) == <<0::size(1), 480::size(15)>>
    
    # Verify value through binary parsing
    ppqn_96 = Sequence.create_metrical_division(96)
    <<format_bit::size(1), ppqn::size(15)>> = ppqn_96
    assert format_bit == 0
    assert ppqn == 96
  end

  test "create_smpte_division" do
    # Test creating SMPTE division values for all valid frame rates
    smpte_24_4 = Sequence.create_smpte_division(24, 4)
    smpte_25_40 = Sequence.create_smpte_division(25, 40)
    smpte_29_80 = Sequence.create_smpte_division(29, 80)
    smpte_30_100 = Sequence.create_smpte_division(30, 100)
    
    # Verify values through binary parsing
    <<format_bit_24::size(1), frames_bits_24::size(7), ticks_24::size(8)>> = smpte_24_4
    <<format_bit_25::size(1), frames_bits_25::size(7), ticks_25::size(8)>> = smpte_25_40
    <<format_bit_29::size(1), frames_bits_29::size(7), ticks_29::size(8)>> = smpte_29_80
    <<format_bit_30::size(1), frames_bits_30::size(7), ticks_30::size(8)>> = smpte_30_100
    
    # Check format bit is 1 for all
    assert format_bit_24 == 1
    assert format_bit_25 == 1
    assert format_bit_29 == 1
    assert format_bit_30 == 1
    
    # Check frames bits (7 bits, 2's complement negative)
    assert frames_bits_24 == 0b1101000  # -24 in 7-bit two's complement (0x68)
    assert frames_bits_25 == 0b1100111  # -25 in 7-bit two's complement (0x67)
    assert frames_bits_29 == 0b1100011  # -29 in 7-bit two's complement (0x63)
    assert frames_bits_30 == 0b1100010  # -30 in 7-bit two's complement (0x62)
    
    # Check ticks per frame values
    assert ticks_24 == 4
    assert ticks_25 == 40
    assert ticks_29 == 80
    assert ticks_30 == 100
  end

  test "set_bpm", context do
    original_bpm = Sequence.bpm(context[:seq])
    new_bpm = original_bpm + 10
    new_seq = Sequence.set_bpm(context[:seq], new_bpm)

    # Check that a new sequence is returned
    assert new_seq != context[:seq]

    # Check that the BPM was updated
    assert Sequence.bpm(new_seq) == new_bpm

    # Check that original sequence is unchanged
    assert Sequence.bpm(context[:seq]) == original_bpm
  end

  test "set_bpm with nil conductor_track" do
    seq = %Sequence{conductor_track: nil}
    # Should return the same sequence and print a warning
    assert Sequence.set_bpm(seq, 120) == seq
  end

  test "set_bpm with empty events" do
    seq = %Sequence{conductor_track: %Track{events: []}}
    # Should return the same sequence and print a warning
    assert Sequence.set_bpm(seq, 120) == seq
  end
end
