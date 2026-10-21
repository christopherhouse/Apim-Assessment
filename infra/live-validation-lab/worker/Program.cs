namespace LabWorker;

internal static class Program
{
    internal static async Task<int> Main(string[] args)
    {
        try
        {
            if (!OperatingSystem.IsLinux() || args.Length != 1 || args[0] is not ("serve" or "job"))
                throw new InvalidDataException("InvalidWorkerCommand");
            var paths = WorkerPaths.Installed;
            var config = WorkerConfig.Parse(PrivateFiles.Read(paths.Config));
            if (args[0] == "serve")
            {
                await using var app = Backend.Build(config, paths);
                await app.RunAsync();
                return 0;
            }
            var job = JobRequest.Parse(PrivateFiles.Read(paths.Job, 4096));
            using var client = Jobs.CreateClient();
            var result = await new Jobs(config, paths, client, TimeProvider.System).Run(job);
            Console.Out.WriteLine(result.Code);
            return result.State switch { "Ready" => 0, "NotReady" => 3, _ => 1 };
        }
        catch
        {
            Console.Out.WriteLine("LAB_WORKER_FAILED");
            return 1;
        }
    }
}
