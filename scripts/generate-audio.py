"""Generate the original PCM WAV cues shipped with Chef al Mando.

The tones are authored in this file from sine-wave frequencies and envelopes.
They do not use third-party audio, voices, music, or network services.
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 44_100
DURATION_SECONDS = 0.22
AMPLITUDE = 0.26
CUES = {
    "arrival": (880.0, 1_176.0),
    "served": (659.25, 880.0),
    "warning": (349.23, 293.66),
}


def samples(frequencies: tuple[float, float]) -> bytes:
    frame_count = int(SAMPLE_RATE * DURATION_SECONDS)
    frames = bytearray()
    for index in range(frame_count):
        position = index / SAMPLE_RATE
        progress = index / frame_count
        envelope = min(1.0, progress * 30.0, (1.0 - progress) * 12.0)
        frequency = frequencies[0] if progress < 0.5 else frequencies[1]
        value = int(32_767 * AMPLITUDE * envelope * math.sin(2.0 * math.pi * frequency * position))
        frames.extend(struct.pack("<h", value))
    return bytes(frames)


def write_cue(directory: Path, name: str, frequencies: tuple[float, float]) -> None:
    target = directory / f"{name}.wav"
    with wave.open(str(target), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(samples(frequencies))


def main() -> None:
    directory = Path(__file__).resolve().parents[1] / "assets" / "audio"
    directory.mkdir(parents=True, exist_ok=True)
    for name, frequencies in CUES.items():
        write_cue(directory, name, frequencies)


if __name__ == "__main__":
    main()
