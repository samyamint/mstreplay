#!/usr/bin/env python3
import array
import json
import math
import platform
from pathlib import Path
import subprocess
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
ENCODER = ROOT / "bin/Release/streplay-encoder"
FRAME = bytes([0, 0, 255, 0]) * (64 * 32) + bytes([255, 0, 0, 0]) * (64 * 32)


class NativeEncoderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="streplay test # % ' ")
        cls.folder = Path(cls.temp.name)
        cls.inspector = cls.folder / "inspect"
        target = f"{platform.machine()}-apple-macosx12.0"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-target", target,
                        str(ROOT / "tests/InspectMovie.swift"), "-o", str(cls.inspector)], check=True)
        cls.wav = cls.folder / "stereo sound.wav"
        with wave.open(str(cls.wav), "wb") as sound:
            sound.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
            samples = array.array("h", (int(math.sin(i * 440 * 2 * math.pi / 48000) * 10000) for i in range(48000) for _ in range(2)))
            sound.writeframes(samples.tobytes())

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_encoder(self, name, codec="H264", data=FRAME * 15, audio="", width=64, expected=0):
        path = self.folder / (name + (".mov" if codec == "ProRes4444" else ".mp4"))
        result = subprocess.run([str(ENCODER), str(path), codec, str(width), "64", "30", "14", str(audio)], input=data, capture_output=True, timeout=40)
        self.assertEqual(result.returncode, expected, result.stderr.decode())
        return path, result

    def inspect(self, path):
        return json.loads(subprocess.check_output([str(self.inspector), str(path)], timeout=30))

    def test_codecs_audio_orientation_timing_and_cancelled_duration(self):
        for codec, fourcc in [("H264", "avc1"), ("H265", "hvc1"), ("ProRes4444", "ap4h")]:
            for audio in [False, True]:
                with self.subTest(codec=codec, audio=audio):
                    path, result = self.run_encoder(f"{codec}-{audio}", codec, audio=self.wav if audio else "")
                    self.assertIn(b"READY", result.stderr)
                    movie = self.inspect(path)
                    self.assertEqual(movie["codec"], fourcc)
                    self.assertEqual(movie["frames"], 15)
                    self.assertAlmostEqual(movie["duration"], 0.5, delta=0.04)
                    for i, time in enumerate(movie["times"]):
                        self.assertAlmostEqual(time, i / 30, delta=0.001)
                    self.assertGreater(movie["top"][0], 220)
                    self.assertLess(movie["top"][2], 30)
                    self.assertGreater(movie["bottom"][2], 220)
                    self.assertLess(movie["bottom"][0], 30)
                    if audio:
                        self.assertGreater(movie["audioSamples"], 20000)
                        self.assertAlmostEqual(movie["audioDuration"], 0.5, delta=0.04)
                    else:
                        self.assertEqual(movie["audioSamples"], 0)
        self.assertTrue(self.wav.exists(), "Helper must preserve source audio; parent owns cleanup")

    def test_incomplete_or_empty_frames_fail_cleanly(self):
        for name, data in [("empty", b""), ("partial", FRAME + b"short frame")]:
            path, _ = self.run_encoder(name, data=data, expected=1)
            self.assertFalse(path.exists())

    def test_invalid_dimensions_and_missing_audio(self):
        path, result = self.run_encoder("odd", width=63, expected=1)
        self.assertNotIn(b"READY", result.stderr)
        self.assertFalse(path.exists())
        path, result = self.run_encoder("bad-audio", audio=self.folder / "missing.wav", expected=1)
        self.assertNotIn(b"READY", result.stderr)
        self.assertFalse(path.exists())

    def test_existing_output_is_preserved(self):
        path = self.folder / "existing.mp4"
        path.write_bytes(b"keep this file")
        self.run_encoder("existing", expected=1)
        self.assertEqual(path.read_bytes(), b"keep this file")

    def test_fragmented_pipe_frames(self):
        path = self.folder / "fragmented.mp4"
        proc = subprocess.Popen([str(ENCODER), str(path), "H264", "64", "64", "30", "14", ""], stdin=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertEqual(proc.stderr.readline().strip(), b"READY")
            payload = FRAME * 3
            for start in range(0, len(payload), 997):
                proc.stdin.write(payload[start:start + 997])
                proc.stdin.flush()
            proc.stdin.close()
            proc.wait(timeout=30)
            self.assertEqual(proc.returncode, 0, proc.stderr.read().decode())
            self.assertEqual(self.inspect(path)["frames"], 3)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            proc.stderr.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
