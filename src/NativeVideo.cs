using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using UnityEngine;

namespace Streplay
{
    internal sealed class NativeVideoSink : FrameSink
    {
        readonly Process _proc;
        readonly Stream _stdin;
        readonly Thread _logReader;
        readonly ManualResetEventSlim _ready = new ManualResetEventSlim();
        readonly Queue<string> _log = new Queue<string>();
        readonly string _audio;
        volatile bool _accepted;
        public static string Extension(RenderFormat f) => f == RenderFormat.ProRes4444 ? ".mov" : ".mp4";

        public NativeVideoSink(string output, RenderFormat format, int w, int h, int fps, int quality, string audio) : base(w, h)
        {
            string helper = NativeVideo.Find();
            if (helper == null) throw new IOException(NativeVideo.UnavailableMessage);
            OutputPath = output;
            _audio = audio;
            using (var chmod = Process.Start(new ProcessStartInfo("/bin/chmod")
            {
                UseShellExecute = false, ArgumentList = { "u+x", helper }
            }))
            {
                if (!chmod.WaitForExit(5000) || chmod.ExitCode != 0)
                    throw new IOException("Could not make the bundled video encoder executable.");
            }
            var info = new ProcessStartInfo(helper)
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardError = true
            };
            foreach (var arg in new[] { output, format.ToString(), w.ToString(), h.ToString(), fps.ToString(), quality.ToString(), audio ?? "" })
                info.ArgumentList.Add(arg);
            _proc = new Process { StartInfo = info };
            _logReader = new Thread(ReadLog) { IsBackground = true, Name = "Streplay encoder log" };
            try { _proc.Start(); }
            catch { _proc.Dispose(); _ready.Dispose(); throw; }
            _logReader.Start();
            if (!_ready.Wait(15000) || !_accepted)
            {
                if (!_proc.HasExited) _proc.Kill();
                _proc.WaitForExit();
                _logReader.Join();
                _proc.Dispose();
                _ready.Dispose();
                throw new IOException("Apple video encoder could not start: " + LastLog());
            }
            _stdin = _proc.StandardInput.BaseStream;
            StartWorkers(1);
        }

        void ReadLog()
        {
            try
            {
                string line;
                while ((line = _proc.StandardError.ReadLine()) != null)
                {
                    if (line == "READY") { _accepted = true; _ready.Set(); }
                    else lock (_log) { _log.Enqueue(line); while (_log.Count > 20) _log.Dequeue(); }
                }
            }
            catch (IOException) { }
            finally { _ready.Set(); }
        }

        protected override void Write(byte[] rgba, int index)
        {
            if (_proc.HasExited) throw new IOException("Apple video encoder stopped: " + LastLog());
            _stdin.Write(rgba, 0, rgba.Length);
        }

        string LastLog() { lock (_log) return string.Join(" | ", _log); }

        protected override void Close(bool cancelled)
        {
            try
            {
                try { _stdin.Close(); } catch (IOException) { }
                if (!_proc.WaitForExit(120000))
                {
                    _proc.Kill();
                    _proc.WaitForExit();
                    throw new IOException("Apple video encoder timed out while finishing. The WAV was kept.");
                }
                _logReader.Join();
                if (_proc.ExitCode != 0) throw new IOException($"Apple video encoder exit code {_proc.ExitCode}: {LastLog()}");
                if (!cancelled && _audio != null) try { File.Delete(_audio); } catch (IOException) { }
            }
            finally { _logReader.Join(); _proc.Dispose(); _ready.Dispose(); }
        }
    }

    internal static class NativeVideo
    {
        public static string Find()
        {
            if (Application.platform != RuntimePlatform.OSXPlayer && Application.platform != RuntimePlatform.OSXEditor) return null;
            string path = Path.Combine(Path.GetDirectoryName(typeof(NativeVideo).Assembly.Location) ?? "", "streplay-encoder");
            return File.Exists(path) ? path : null;
        }
        public static string UnavailableMessage => "Apple video encoder unavailable. Install streplay-encoder beside streplay.dll on macOS 12 or later. Rendering PNG frames instead.";
    }
}
