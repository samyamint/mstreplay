using System;
using System.IO;
using System.Threading;
using Streplay;
namespace UnityEngine
{
    public enum RuntimePlatform { OSXPlayer, OSXEditor }
    public static class Application { public static RuntimePlatform platform => RuntimePlatform.OSXPlayer; }
    public static class SystemInfo { public static int processorCount => 4; }
    public static class ImageConversion
    {
        public static byte[] EncodeArrayToPNG(byte[] b, Experimental.Rendering.GraphicsFormat f, uint w, uint h)
            => throw new NotSupportedException("PNG requires Unity");
    }
}
namespace UnityEngine.Experimental.Rendering { public enum GraphicsFormat { R8G8B8A8_SRGB } }

static class Launcher
{
    static void Main(string[] args)
    {
        string root = args[0], wav = args[1];
        foreach (bool cancelled in new[] { false, true })
        {
            string audio = Path.Combine(root, $"source {cancelled}.wav");
            File.Copy(wav, audio);
            string output = Path.Combine(root, $"movie # % ' é {cancelled}.mp4");
            var sink = new NativeVideoSink(output, RenderFormat.H264, 64, 64, 30, 14, audio);
            for (int i = 0; i < 6; i++)
            {
                var pixels = sink.Rent();
                for (int n = 0; n < pixels.Length; n += 4) { pixels[n] = 255; pixels[n + 3] = 255; }
                sink.Submit(pixels, i);
            }
            using var done = new ManualResetEventSlim();
            sink.Finish(cancelled, _ => done.Set());
            if (!done.Wait(30000)) throw new Exception("C# sink did not finish");
            if (sink.Error != null) throw new Exception(sink.Error);
            if (sink.Written != 6 || sink.Backlog != 0 || new FileInfo(output).Length == 0)
                throw new Exception("Frame queue was not fully written");
            if (File.Exists(audio) != cancelled) throw new Exception("Incorrect WAV cleanup on success/cancellation");
            Console.WriteLine($"PASS: C# launcher, frame queue, paths and audio cleanup (cancelled={cancelled})");
        }
        try
        {
            new NativeVideoSink(Path.Combine(root, "invalid.mp4"), (RenderFormat)42, 64, 64, 30, 14, null);
            throw new Exception("Unsupported format should fail during setup");
        }
        catch (IOException) { Console.WriteLine("PASS: setup failure reported before submitting frames"); }
        string helper = NativeVideo.Find();
        File.Move(helper, helper + ".disabled");
        try
        {
            new NativeVideoSink(Path.Combine(root, "missing.mp4"), RenderFormat.H264, 64, 64, 30, 14, null);
            throw new Exception("Missing helper should fail during setup");
        }
        catch (IOException) { Console.WriteLine("PASS: missing helper reported for PNG fallback"); }
        finally { File.Move(helper + ".disabled", helper); }
    }
}
