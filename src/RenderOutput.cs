using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using UnityEngine;
using UnityEngine.Experimental.Rendering;

namespace Streplay
{
    public enum RenderFormat { H264, H265, ProRes4444, PngSequence }

    // how the sub-frames of one output frame are weighted: Equal is a film camera's open shutter, Gaussian fades the
    // copies in and out at the ends of the shutter (the soft "frame blending" look of HLAE / RSMB / f0e's blur)
    public enum BlurWeighting { Equal, Gaussian }

    // Where finished RGBA frames go. Frames arrive in order on the main thread (rows bottom-up, as Unity
    // reads them back) and are written on worker threads. Submit never blocks: the PNG encoder needs Unity's
    // main thread to keep running, so the renderer holds still (see Backlog) instead of waiting here.
    internal abstract class FrameSink
    {
        protected readonly int W, H;
        readonly BlockingCollection<(byte[] data, int index)> _queue = new BlockingCollection<(byte[], int)>();
        readonly ConcurrentBag<byte[]> _pool = new ConcurrentBag<byte[]>();
        readonly List<Thread> _threads = new List<Thread>();
        volatile string _error;
        int _written, _backlog;
        public int Workers { get; private set; }
        // frames submitted but not written yet
        public int Backlog => Volatile.Read(ref _backlog);

        public string Error => _error;
        public int Written => _written;
        public string OutputPath { get; protected set; }
        public bool Finished { get; private set; }

        protected FrameSink(int w, int h) { W = w; H = h; }

        protected void StartWorkers(int count)
        {
            Workers = count;
            for (int i = 0; i < count; i++)
            {
                var t = new Thread(Work) { IsBackground = true, Name = "Streplay render writer" };
                _threads.Add(t);
                t.Start();
            }
        }

        public byte[] Rent() => _pool.TryTake(out var b) ? b : new byte[W * H * 4];

        public void Submit(byte[] rgba, int index)
        {
            if (_error != null) { _pool.Add(rgba); return; }
            Interlocked.Increment(ref _backlog);
            _queue.Add((rgba, index));
        }

        void Work()
        {
            foreach (var (data, index) in _queue.GetConsumingEnumerable())
            {
                try
                {
                    if (_error == null) { Write(data, index); Interlocked.Increment(ref _written); }
                }
                catch (Exception e)
                {
                    _error ??= e.Message;
                }
                _pool.Add(data);
                Interlocked.Decrement(ref _backlog);
            }
        }

        protected abstract void Write(byte[] rgba, int index);
        protected virtual void Close(bool cancelled) { }

        // Lets queued frames drain and closes the output on a background thread; Finished turns true after.
        public void Finish(bool cancelled, Action<FrameSink> done)
        {
            _queue.CompleteAdding();
            var t = new Thread(() =>
            {
                foreach (var w in _threads) w.Join();
                try { Close(cancelled); }
                catch (Exception e) { _error ??= e.Message; }
                done?.Invoke(this);
                Finished = true;
            }) { IsBackground = true, Name = "Streplay render finish" };
            t.Start();
        }
    }

    internal sealed class PngSink : FrameSink
    {
        readonly string _dir;

        public PngSink(string dir, int w, int h) : base(w, h)
        {
            _dir = dir;
            OutputPath = dir;
            StartWorkers(Math.Max(1, Math.Min(4, SystemInfo.processorCount / 2)));
        }

        protected override void Write(byte[] rgba, int index)
        {
            for (int i = 3; i < rgba.Length; i += 4) rgba[i] = 255; // camera alpha is meaningless
            var png = ImageConversion.EncodeArrayToPNG(rgba, GraphicsFormat.R8G8B8A8_SRGB, (uint)W, (uint)H);
            File.WriteAllBytes(Path.Combine(_dir, $"frame_{index:00000}.png"), png);
        }
    }

}
