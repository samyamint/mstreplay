#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile
import wave
from xml.sax.saxutils import escape

root = Path(__file__).resolve().parents[1]
sdk_major = int(subprocess.check_output(["dotnet", "--version"], text=True).split(".")[0])
assert sdk_major >= 8, "Use .NET SDK 8 or newer"
with tempfile.TemporaryDirectory(prefix="streplay launcher # % '") as temp:
    folder = Path(temp)
    project = folder / "Launcher.csproj"
    sources = [root / "tests/Launcher.cs", root / "src/RenderOutput.cs", root / "src/NativeVideo.cs"]
    items = "".join(f'<Compile Include="{escape(str(source))}" />' for source in sources)
    project.write_text(f'<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>'
                       f'<TargetFramework>net{sdk_major}.0</TargetFramework><EnableDefaultCompileItems>false</EnableDefaultCompileItems>'
                       f'</PropertyGroup><ItemGroup>{items}</ItemGroup></Project>')
    output = folder / "out"
    subprocess.run(["dotnet", "build", str(project), "-c", "Release", "-o", str(output), "--nologo"], check=True)
    helper = output / "streplay-encoder"
    shutil.copyfile(root / "bin/Release/streplay-encoder", helper)
    helper.chmod(0o600)
    wav = folder / "sound.wav"
    with wave.open(str(wav), "wb") as sound:
        sound.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        sound.writeframes(b"\0" * (48000 * 4))
    subprocess.run(["dotnet", str(output / "Launcher.dll"), str(folder), str(wav)], check=True, timeout=90)
